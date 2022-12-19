#!/usr/bin/env -S runuser -s /bin/bash - root --

# The above runs this script in a sanitized environment, which runs 
# /etc/profile, too (if it is a bash shell). Just in case root has a different 
# shell in /etc/passwd, I also specified '-s /bin/bash' to ensure it is the 
# standard bash shell.

# Let's not pick up anything from /etc/locale.conf, but set a safe setting 
# which should be available.
#
# LC_ALL will always override LANG and all the other LC_* variables, whether 
# they are set or not. LC_ALL is the only LC_* variable which cannot be set in 
# locale.conf files: it is meant to be used only for testing or troubleshooting 
# purposes
export LC_ALL=C

bin="$(dirname "$0")"
btrfs='noatime,noacl,commit=300,autodefrag,compress=zstd'

# My normal script boilerplate:
set -e; . "$bin/bash-header2.sh"

# Have another gpg so we do not interfere with the root's gpg.
export GNUPGHOME=$td/.gnupg
# Make sure we bring down all its apps at the end.
push_clean gpgconf --kill all

shopt -s nullglob



### One-off sanity checks.

# arch-chroot only works if 
# 1) bash 4 or later is installed, and
# 2) unshare supports the --fork and --pid options
# as per 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_image_(recommended) 
if [[ ${BASH_VERSINFO[0]} -lt 4 ]] || ! unshare -h | grep -qe --fork || ! unshare -h | grep -qe --pid; then
  echo "ERROR: arch-chroot is not supported" >&2
  onexit 1
fi

if getopt -T >/dev/null || [[ $? -ne 4 ]]; then
  echo "ERROR: You have an incompatible version of getopt" >&2
  onexit 1
fi

if [[ $(whoami) != root ]]; then
  echo "ERROR: Must be run by root." >&2
  onexit 1
fi



### Parameters.

debug=
root=
pacserve=
eval set -- "$(getopt -o dr:p: -l root:,pacserve: -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      # Optional
      debug=y
      set -x
      ;;
    -r|--root)
      # Mandatory
      root="$2"
      shift
      ;;
    -p|--pacserve)
      # Optional
      pacserve="$2"
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

if   [[ -z $root ]]; then
  echo "ERROR: Root dir is not set" >&2
  onexit 1
fi

root_dir="$(dirname -- "$root")"

if [[ -e "$root" ]]; then
  btrfs su del -- "$root"
elif [[ ! -d $root_dir ]]; then
  echo "ERROR: $root_dir exists and it is not a directory" >&2
  onexit 1
fi
btrfs su create -- "$root"

root_vol="$(btrfs su show -- "$root" | head -1)"

if ! root_dev="$(findmnt -fn -o source -- "$root_dir")"; then
  echo "ERROR: $root_dir is not a mount point" >&2
  onexit 1
fi

root_snap="$root_dir/.snapshot/$(basename "$root")"
if   [[ ! -e   $root_snap ]]; then
  install -d  "$root_snap"
elif [[ ! -d   $root_snap ]]; then
  echo "ERROR: $root_snap exists and it is not a directory" >&2
  onexit 1
fi



pkg="$root_dir/pkg"
if [[ -e $pkg ]]; then
  if ! btrfs su show -- "$pkg" >/dev/null; then
    echo "ERROR: $pkg is not a BTRFS subvolume" >&2
    onexit 1
  fi
else
  btrfs su create -- "$pkg"
fi



if [[ $pacserve ]]; then
  if ! grep -q : <<<$pacserve; then
    # No custom port specified. Add the standard port.
    pacserve+=:15678
  fi

  if ! curl -sSI --connect-timeout 2 "http://$pacserve" >/dev/null; then
    echo "ERROR: Connection failed to pacserve = $pacserve" >&2
    onexit 1
  fi
fi



### Obtain mirrorlist.

country="$(curl -sS https://ipapi.co/country)"

# Some mirrors do not serve version. Try again, as new execution of 
# https://archlinux.org/mirrorlist/... will get you a list in a different 
# order.
try=0
version=
while [[ $((try++)) -lt 5 ]] && [[ -z $version ]]; do
  curl -sSfo $td/mirrorlist "https://archlinux.org/mirrorlist/?country=$country&use_mirror_status=on"
  sed -i 's/^#Server/Server/' $td/mirrorlist

  server=$(grep ^Server $td/mirrorlist | head -1 | sed 's/^Server = \(.*\)\/$repo\/os\/$arch/\1/')
  version="$(curl -sS "$server/iso/latest/arch/version")"
done

if [[ -z $version ]]; then
  echo "ERROR: Bootstrap version is empty" >&2
  onexit 1
fi

bootstrap="archlinux-bootstrap-$version-x86_64.tar.gz"



gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.de

if [[ -e "$pkg/$bootstrap" ]]; then
  gpg --verify "$pkg/$bootstrap.sig"

  tar xf "$pkg/$bootstrap" --numeric-owner -C $td
else
  ### Download and validate the bootstrap image.

  # Do not use -L on curl as pacserve redirects if the file is missing, but we are 
  # cheating with storing bootstrap under pacserve. It would not be at that 
  # location in a real host.
  #
  # As per above, if the bootstrap is not on pacserve it returns a URL of one of 
  # the mirrors. Hence the curl will not fail even if the bootstrap is not there. 
  # Hence I test the file.
  if [[ $pacserve ]] && curl -fo $td/$bootstrap "http://$pacserve/pacman/core/os/x86_64/$bootstrap" && gzip -t $td/$bootstrap; then
    curl -sSfo $td/$bootstrap.sig "http://$pacserve/pacman/core/os/x86_64/$bootstrap.sig"
  else
    curl   -fo $td/$bootstrap     "$server/iso/latest/$bootstrap"
    curl -sSfo $td/$bootstrap.sig "$server/iso/latest/$bootstrap.sig"
  fi

  gpg --verify $td/$bootstrap.sig

  tar xf $td/$bootstrap --numeric-owner -C $td

  mv -- $td/$bootstrap{,.sig} "$pkg"
fi

chrt=$td/root.x86_64



### /etc/pacman.conf

sed -i 's/^CheckSpace/#CheckSpace/' $chrt/etc/pacman.conf

# Add "Include = /etc/pacman.d/pacserve" before each repo. This makes 
# sense even if we do not use pacserve as we can keep that file empty.
sed -i '/^\[\(core\|extra\|community\)\]/a Include = /etc/pacman.d/pacserve' $chrt/etc/pacman.conf

mv $td/mirrorlist $chrt/etc/pacman.d/mirrorlist

if [[ $pacserve ]]; then
  echo "Server = http://$pacserve"'/pacman/$repo/$arch'
else
  :
fi >$chrt/etc/pacman.d/pacserve



### Prep for chroot

# As per "man 8 arch-chroot", do the below trick to avoid
#
# ==> WARNING: xxxx is not a mountpoint. This may have undesirable side effects.
#
# error message. This makes the installation safer as "pacman(8) or findmnt(8) 
# have an accurate hierarchy of the mounted filesystems within the chroot" 
# (apparently)
#
# This has to be before mounting "pkg" cache as the mount point of "pkg" would 
# be inside this "$chrt" mount point. If it is done in the other way around, 
# the "pkg" mount point would be empty.
push_clean umount    -- "$chrt"
mount --bind "$chrt" -- "$chrt"

push_clean umount                                       -- "$chrt/mnt"
mount -t btrfs -o $btrfs,subvol="$root_vol" "$root_dev" -- "$chrt/mnt"

# Use the centralised pkg cache, so even if I do not have pacserve running, the 
# previously downloaded packages are available.
install -d                                      -- "$chrt/mnt/var/cache/pacman/pkg"
push_clean umount                               -- "$chrt/mnt/var/cache/pacman/pkg"
mount -t btrfs -o $btrfs,subvol=pkg "$root_dev" -- "$chrt/mnt/var/cache/pacman/pkg"



### Chroot

cp -- "$bin/stage1-chroot.sh" "$bin/bash-header2.sh" $chrt/root

# I use "runuser - root -c" to sanitize the env variables, and '-' makes it 
# a login shell, so /etc/profile is executed. It will pass 
# /root/stage1-chroot.sh and the rest to the default shell. To make sure it is 
# bash, I used '-s /bin/bash'.
#
# Params passed to stage1-chroot.sh will be passed to pacstrap.
# - I need perl for editing configs in the next stages.
# - I need arch-install-scripts for ach-chroot in the next stages.
# - I install mkinitcpio here before main pacman run, which installs linux-lts, 
#   because I want to edit /etc/mkinitcpio.conf before linux-lst kicks off the 
#   ramdisk generation. This way we can get away with running mkinitcpio only 
#   once, and in addition we can rely on linux-lts to kick it off.
"$chrt/bin/arch-chroot" "$chrt" runuser -s /bin/bash - root -- /root/stage1-chroot.sh ${debug:+-d} /mnt base perl arch-install-scripts mkinitcpio

# systemd-tmpfiles creates 2 subvolumes if filesystem is btrfs.
# See:
#   - https://bugzilla.redhat.com/show_bug.cgi?id=1327596
#   - https://bbs.archlinux.org/viewtopic.php?id=260291
# I have to get rid of them and replace them with normal dir. Then, they remain 
# normal dirs.
for i in portables machines; do
  btrfs su del -- "$chrt/mnt/var/lib/$i"
  install -d   -- "$chrt/mnt/var/lib/$i"
done


# Pacstrap do not copy /etc/pacman.conf over, so I have to repeat commenting 
# out CheckSpace.
sed -i 's/^CheckSpace/#CheckSpace/'                                                    $chrt/mnt/etc/pacman.conf
sed -i '/^\[options\]/a NoExtract = etc/pacman.d/mirrorlist'                           $chrt/mnt/etc/pacman.conf

sed -i 's/^#\[multilib\]/[multilib]\nInclude = \/etc\/pacman.d\/mirrorlist/'           $chrt/mnt/etc/pacman.conf
sed -i '/^\[\(core\|extra\|community\|multilib\)\]/a Include = /etc/pacman.d/pacserve' $chrt/mnt/etc/pacman.conf
mv -- $chrt/etc/pacman.d/pacserve $chrt/mnt/etc/pacman.d



### Save the image.

btrfs su snap -r -- "$root" "$root_snap/$(date -uIs)"

onexit 0
