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

root=
cache=
country=
eval set -- "$(getopt -o r:c:C: -l root:,cache:,country: -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -r|--root)
      root="$2"
      shift
      ;;
    -c|--cache)
      cache="$2"
      shift
      ;;
    -C|--country)
      cache="$2"
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



### Obtain mirrorlist.

if [[ -z $country ]]; then
  country="$(curl -sS https://ipapi.co/country)"
fi

curl -sS "https://archlinux.org/mirrorlist/?country=$country&use_mirror_status=on" >$td/mirrorlist
sed -i 's/^#Server/Server/' $td/mirrorlist

server=$(grep ^Server $td/mirrorlist | head -1 | sed 's/^Server = \(.*\)\/$repo\/os\/$arch/\1/')
version="$(curl -sS "$server/iso/latest/arch/version")"
bootstrap="$server/iso/latest/archlinux-bootstrap-$version-x86_64.tar.gz"



### Download and validate the bootstrap image.

curl     -o $td/bootstrap-x86_64.tar.gz     "$bootstrap"
curl -sS -o $td/bootstrap-x86_64.tar.gz.sig "$bootstrap".sig

export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all
gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.de
gpg --verify $td/bootstrap-x86_64.tar.gz.sig

tar xf $td/bootstrap-x86_64.tar.gz --numeric-owner -C $td
rm     $td/bootstrap-x86_64.tar.gz
chr=$td/root.x86_64



### Prepare $c/etc/pacman.conf

sed -i 's/^CheckSpace.*/#&/' $chr/etc/pacman.conf



### Prepare $c/etc/pacman.d/mirrorlist

if [[ $cache ]]; then
  echo "Server = $cache"
else
  :
fi                  >$chr/etc/pacman.d/mirrorlist
cat $td/mirrorlist >>$chr/etc/pacman.d/mirrorlist



### Chroot stage

curl -sS -o $chr/bin/stage1-chroot.sh $gh/stage1-chroot.sh
chmod +x    $chr/bin/stage1-chroot.sh

# Params passed to stage1-chroot.sh will be passed to pacstrap.
# - I need perl for editing configs in the next stages.
# - I need arch-install-scripts for ach-chroot in the next stages.
# - I install mkinitcpio here before main pacman run, which installs linux-lts, 
#   because I want to edit /etc/mkinitcpio.conf before linux-lst kicks off the 
#   ramdisk generation. This way we can get away with running mkinitcpio only 
#   once, and in addition we can rely on linux-lts to kick it off.
$chr/bin/arch-chroot $chr /bin/stage1-chroot.sh /mnt base perl arch-install-scripts mkinitcpio



### Save the image.

btrfs su create "$root"
root_snap="$(dirname "$root")/.snapshot/$(basename "$root")"; mkdir -p "$root_snap"

tar cf - --numeric-owner -C $chr/mnt . | (cd -- "$root" && tar xf - --numeric-owner)

btrfs su snap -r "$root" "$root_snap/$(date -uIm)"

onexit 0
