#!/usr/bin/env bash
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header2.sh)

# Safe setting and should be available.
export LC_ALL=C

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all



### Parameters.

host=
eval set -- "$(getopt -o dh: -l host: -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      set -x
      ;;    
    -h|--host)
      host="$2"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "ERROR: Programming error #1: $1" >&2
      onexit 1
  esac
  shift
done

case $host in
  bud|gla)
    keymap=us-altgr-intl-console-hu
    city=Europe/London
    list=bud
    ;;
  laptop)
    keymap=hu
    city=Europe/Budapest
    list=laptop
    ;;
  *)
    echo "ERROR: host = $host is invalid" >&2
    onexit 1
esac



### Set the locales

perl -i -pe '$z+=s{^#((en_US|en_DK|hu_HU)\.UTF-8 .*)}{$1};END{die if $z!=3}' /etc/locale.gen
locale-gen

install -d /etc/skel/.config
cat >/etc/skel/.config/locale.conf <<'EOF'
LANG=en_US.UTF-8

# Use locale -k LC_XXX to display their meaning.

# Set the short date to YYYY-MM-DD (test with "date +%c")
LC_TIME=en_DK.UTF-8

# Make the ls command sort dotfiles first, followed by uppercase and
# lowercase filenames.
LC_COLLATE=C

# To prevent system messages from being translated
LC_MESSAGES=C
EOF

cp /etc/skel/.config/locale.conf /etc/locale.conf

if [[ $host == laptop ]]; then
    perl -i -pe '$z+=s{^LANG=.*}{LANG=hu_HU.UTF-8};END{die if $z!=1}' /etc/locale.conf
fi

# Reset the local to the new settings.

# LC_ALL overrides all LC_* variables. It was the safe choice until now, but we 
# have to unset it now to let the rest take effect.
unset LC_ALL
# /etc/profile.d/locale.sh refers to undefined vars in a number of places (not 
# just at 'unset LANG'). Hence I have to turn off 'set -u'.
set +u
# The below 2 lines from 
# https://wiki.archlinux.org/title/Locale#Make_locale_changes_immediate
unset LANG
source /etc/profile.d/locale.sh
set -u

# I also set the time-zone here out of convenince.
ln -sf /usr/share/zoneinfo/$city /etc/localtime



### /etc/pacman.conf

# Pacstrap do not copy /etc/pacman.conf over, so I have to repeat commenting 
# out CheckSpace.
sed -i 's/^CheckSpace/#CheckSpace/'                                          /etc/pacman.conf
sed -i '/^\[\(core\|extra\|community\)\]/a Include = /etc/pacman.d/pacserve' /etc/pacman.conf
sed -i '/^\[options\]/a NoExtract = etc/pacman.d/mirrorlist'                 /etc/pacman.conf

tee -a /etc/pacman.conf >/dev/null <<'EOF'

# Enable multilib for Wine
[multilib]
Include  = /etc/pacman.d/pacserve
Include  = /etc/pacman.d/mirrorlist

[xyne-x86_64]
SigLevel = Required
Include  = /etc/pacman.d/pacserve
Server   = https://xyne.dev/repos/xyne

[xyne-any]
SigLevel = Required
Include  = /etc/pacman.d/pacserve
Server   = https://xyne.dev/repos/xyne

[gabor-zoka]
SigLevel = Required
Include  = /etc/pacman.d/pacserve
Include  = /etc/pacman.d/gabor-zoka
EOF



### Add me to the keyring.

curl -sS -o $td/gabor-zoka.asc https://raw.githubusercontent.com/gabor-zoka/personal/master/public-key.asc

pacman-key --add $td/gabor-zoka.asc
pacman-key --lsign-key "$(gpg --list-packets $td/gabor-zoka.asc | perl -lne 'if(m{^\s+keyid:\s*(.*)}){print $1;exit()}')"



### /etc/mkinitcpio.conf

if [[ $host == qemu ]]; then
    perl -i -pe '$z+=s{^MODULES=.*}{MODULES=(virtio virtio_blk virtio_pci virtio_net i915)};END{die if $z!=1}' /etc/mkinitcpio.conf
else
    perl -i -pe '$z+=s{^MODULES=.*}{MODULES=(ext2 i915)};END{die if $z!=1}' /etc/mkinitcpio.conf
fi

hooks=(base consolefont udev autodetect modconf block keyboard keymap)
[[ $host == bud ]] && [[ $host == gla ]] && {
    hooks+=(gnupg)
}
[[ $host != qemu ]] && {
    hooks+=(encrypt-multi)
}
hooks+=(filesystems)
[[ $host != qemu ]] && {
    hooks+=(chk-boot)
}

perl -i -pe '$z+=s{^HOOKS=.*}{HOOKS=('"$(echo ${hooks[@]})"')};END{die if $z!=1}' /etc/mkinitcpio.conf



### /etc/vconsole.conf (needed for generating the ramdisk) 

cat >/etc/vconsole.conf <<EOF
KEYMAP=$keymap
FONT=Lat2-Terminus16
EOF



### Install

curl -sSfo $td/grp.list $gh/../list/$list/grp.list
curl -sSfo $td/exp.list $gh/../list/$list/exp.list

# Remove comments, and pacserve.
#
# pacserve install conflicts on my custom /etc/pacman.d/pacserve. We install 
# that as the last one seperately.
perl -i -ne 'if(!m{^\s*(\#|$)} && !m{^\s*pacserve\s*$}){print}' $td/grp.list $td/exp.list

pacman -Sy --noconfirm --needed $(cat $td/grp.list $td/exp.list)

# There was an issue umounting /run dir. So it seems we need to sleep a bit 
# before arch-chroot umounts everything.
sleep 5

onexit 0
