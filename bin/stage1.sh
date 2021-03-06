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

# My normal script boilerplate:
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header2.sh)

# Have another gpg so we do not interfere with the root's gpg.
export GNUPGHOME=$td/.gnupg
# Make sure we bring down all its apps at the end.
push_clean gpgconf --kill all

btrfs='noatime,noacl,commit=300,autodefrag,compress=zstd'

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
host=
pacserve=
repo=
eval set -- "$(getopt -o dr:h:p:e: -l root:,host:,pacserve:,repo: -n "$(basename "$0")" -- "$@")"
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
    -h|--host)
      # Mandatory
      host="$2"
      shift
      ;;
    -p|--pacserve)
      # Optional
      pacserve="$2"
      shift
      ;;
    -e|--repo)
      # Mandatory
      repo="$2"
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

mount="$(dirname -- "$root")"
name="$(basename -- "$root")"

if ! dev="$(findmnt -fn -o source -- "$mount")"; then
  echo "ERROR: $mount is not a mount point" >&2
  onexit 1
fi

if [[ -e "$root" ]]; then
  btrfs su del -- "$root"
fi

root_snap="$mount/.snapshot/$name"

if [[ -e $root_snap ]]; then
  for i in "$root_snap"/*; do
    btrfs su del -- "$i"
  done
fi

if [[ -e "$mount/pkg" ]]; then
  if ! btrfs su show -- "$mount/pkg" >/dev/null; then
    echo "ERROR: $mount/pkg is not a BTRFS subvolume" >&2
    onexit 1
  fi
else
  btrfs su create -- "$mount/pkg"
fi



country=
case $host in
  bud|laptop)
    country=HU
    ;;
  gla)
    country=GB
    ;;
  *)
    echo "ERROR: host = $host is invalid" >&2
    onexit 1
esac

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

if [[ $repo ]]; then
  if ! curl -sSI --connect-timeout 2 "http://$repo" >/dev/null; then
    echo "ERROR: Connection failed to repo = $repo" >&2
    onexit 1
  fi
else
  echo "ERROR: --repo (aka my custom repo) is not set" >&2
  onexit 1
fi



### Obtain mirrorlist.

if [[ -z $country ]]; then
  country="$(curl -sS https://ipapi.co/country)"
fi

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

if [[ -e "$mount/pkg/$bootstrap" ]]; then
  gpg --verify "$mount/pkg/$bootstrap.sig"

  tar xf "$mount/pkg/$bootstrap" --numeric-owner -C $td
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

  mv $td/$bootstrap{,.sig} "$mount/pkg"
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

btrfs su create -- "$root"

push_clean umount                              -- "$chrt/mnt"
mount -t btrfs -o $btrfs,subvol="$name" "$dev" -- "$chrt/mnt"

# Use the centralised pkg cache, so even if I do not have pacserve running, the 
# previously downloaded packages are available.
install -d                                 -- "$chrt/mnt/var/cache/pacman/pkg"
push_clean umount                          -- "$chrt/mnt/var/cache/pacman/pkg"
mount -t btrfs -o $btrfs,subvol=pkg "$dev" -- "$chrt/mnt/var/cache/pacman/pkg"



### Chroot

curl -sSfo $chrt/root/stage1-chroot.sh $gh/stage1-chroot.sh
chmod +x   $chrt/root/stage1-chroot.sh

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
# I have to get rid of them
for i in portables machines; do
  btrfs su del -- "$chrt/mnt/var/lib/$i"
  install -d   -- "$chrt/mnt/var/lib/$i"
done

# Save repo files here (albeit we did not need it in this script) so we do not 
# need to support --pacserve and --repo parameters beyond this point.
mv $chrt/etc/pacman.d/pacserve $chrt/mnt/etc/pacman.d
echo "Server = http://$repo"  >$chrt/mnt/etc/pacman.d/gabor-zoka 



### Save the image.

install -d -- "$root_snap"
btrfs su snap -r -- "$root" "$root_snap/$(date -uIs)"

onexit 0
