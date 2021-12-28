#!/usr/bin/env bash
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header.sh)

# Safe setting and should be available.
export LC_ALL=C



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
country=
eval set -- "$(getopt -o dr:p:c: -l root:,pacserve:,country: -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      debug=y
      set -x
      ;;
    -r|--root)
      root="$2"
      shift
      ;;
    -p|--pacserve)
      pacserve="$2"
      shift
      ;;
    -c|--country)
      country="$2"
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
elif [[ -e $root ]]; then
  echo "ERROR: Root dir = $root exists" >&2
  onexit 1
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

if [[ -z $country ]]; then
  country="$(curl -sS https://ipapi.co/country)"
fi

curl -sSfo $td/mirrorlist "https://archlinux.org/mirrorlist/?country=$country&use_mirror_status=on"
sed -i 's/^#Server/Server/' $td/mirrorlist

server=$(grep ^Server $td/mirrorlist | head -1 | sed 's/^Server = \(.*\)\/$repo\/os\/$arch/\1/')

version="$(curl -sS "$server/iso/latest/arch/version")"

if [[ -z $version ]]; then
  # Some mirrors do not serve version. Try again, as new execution of 
  # https://archlinux.org/mirrorlist/... will get you a list in a different 
  # order.
  echo "ERROR: Bootstrap version is empty. Try again" >&2
  onexit 1
fi

bootstrap="archlinux-bootstrap-$version-x86_64.tar.gz"



### Download and validate the bootstrap image.

if [[ $pacserve ]] && curl -fo $td/$bootstrap "http://$pacserve/pacman/core/os/x86_64/$bootstrap"; then
  curl -sSfo $td/$bootstrap.sig "http://$pacserve/pacman/core/os/x86_64/$bootstrap.sig"
else
  curl   -fo $td/$bootstrap     "$server/iso/latest/$bootstrap"
  curl -sSfo $td/$bootstrap.sig "$server/iso/latest/$bootstrap.sig"
fi

export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all
gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.de
gpg --verify $td/$bootstrap.sig

tar xf $td/$bootstrap --numeric-owner -C $td
chr=$td/root.x86_64



### /etc/pacman.conf

sed -i 's/^CheckSpace.*/#&/' $chr/etc/pacman.conf

# Add "Include = /etc/pacman.d/pacserve" before each repo. This makes 
# sense even if we do not use pacserve as we can keep that file empty.
sed -i '/^\[\(core\|extra\|community\)\]/a Include = /etc/pacman.d/pacserve' $chr/etc/pacman.conf



### Mirror lists

mv $td/mirrorlist $chr/etc/pacman.d/mirrorlist

if [[ $pacserve ]]; then
  echo "Server = http://$pacserve"'/pacman/$repo/$arch'
else
  :
fi >$chr/etc/pacman.d/pacserve



### Chroot stage

curl -sSfo $chr/bin/stage1-chroot.sh $gh/stage1-chroot.sh
chmod +x   $chr/bin/stage1-chroot.sh

# Params passed to stage1-chroot.sh will be passed to pacstrap.
# - I need perl for editing configs in the next stages.
# - I need arch-install-scripts for ach-chroot in the next stages.
# - I install mkinitcpio here before main pacman run, which installs linux-lts, 
#   because I want to edit /etc/mkinitcpio.conf before linux-lst kicks off the 
#   ramdisk generation. This way we can get away with running mkinitcpio only 
#   once, and in addition we can rely on linux-lts to kick it off.
$chr/bin/arch-chroot $chr /bin/stage1-chroot.sh ${debug:+-d} /mnt base perl arch-install-scripts mkinitcpio

# Save the bootstrap so we can save this download next time with pacserve.
mv $td/$bootstrap{,.sig} $chr/mnt/var/cache/pacman/pkg



### Save the image.

btrfs su create "$root"
root_snap="$(dirname "$root")/.snapshot/$(basename "$root")"; mkdir -p "$root_snap"

tar cf - --numeric-owner -C $chr/mnt . | (cd -- "$root" && tar xf - --numeric-owner)

btrfs su snap -r "$root" "$root_snap/$(date -uIm)"

onexit 0
