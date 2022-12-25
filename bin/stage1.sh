#!/usr/bin/env -S runuser -s /bin/bash - root --
bin="$(dirname "$0")"
set -e; . "$bin/bash-header2.sh"
shopt -s nullglob



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

# Have another gpg so we do not interfere with the root's gpg.
export GNUPGHOME=$td/.gnupg
# Make sure we bring down all its apps at the end.
push_clean gpgconf --kill all



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
pkg=
repo=
email=
pacserve=
hostname=
eval set -- "$(getopt -o dr:p:o:e:sh: -l root:,pkg:,repo:,email:,pacserve,hostname: -n "$(basename "$0")" -- "$@")"
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
    -p|--pkg)
      # Mandatory
      pkg="$2"
      shift
      ;;
    -o|--repo)
      # Optional
      repo="$2"
      shift
      ;;
    -e|--email)
      # Optional
      email="$2"
      shift
      ;;
    -s|--pacserve)
      # Optional
      pacserve=y
      ;;
    -h|--hostname)
      # Optional
      hostname="$2"
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



### Root dir (mandatory)

if [[ -z $root ]]; then
  echo "ERROR: Root dir is not set" >&2
  onexit 1
fi

if [[ -e $root ]]; then
  btrfs su del  -- "$root"
else
  install -d -- "$(dirname "$root")"
fi
btrfs su create -- "$root"

root_vol="$(btrfs su show -- "$root" | head -1)"
# This does not work:
# findmnt -o UUID,TARGET -nfT "$root" | read root_uuid root_mnt
# as bash runs in subshell if pipe is used. Hence this workaround.
read -r root_uuid root_mnt < <(findmnt -o UUID,TARGET -nfT "$root")

root_snp="$(dirname "$root")/.snapshot/$(basename -- "$root")"
install -d -- "$root_snp"



### Pkg dir (mandatory)

if [[ -z $pkg ]]; then
  echo "ERROR: Pkg dir is not set" >&2
  onexit 1
fi

if [[ ! -e $pkg ]]; then
  install -d -- "$(dirname "$pkg")"
  btrfs su create -- "$pkg"
fi

pkg_vol="$(btrfs su show -- "$pkg" | head -1)"
read -r pkg_uuid < <(findmnt -o UUID -nfT "$pkg")



### Your custom repo dir (optional)

if [[ $repo ]]; then
  repo_vol="$(btrfs su show -- "$repo" | head -1)"
  read -r repo_uuid < <(findmnt -o UUID -nfT "$repo")
  
  (cd -- "$repo" && ls -- *.db) | sed 's/\.db$//' >$td/repo-name

  if [[ ! -s $td/repo-name ]]; then
    echo "ERROR: Missing *.db in $repo. Cannot infer repo name" >&2
    onexit 1
  fi

  if [[ $(wc -l < $td/repo-name) -gt 1 ]]; then
    echo "ERROR: Multiple *.db in $repo. Cannot infer repo name" >&2
    cat -- $td/repo-name >&2
    onexit 1
  fi

  repo_name="$(cat $td/repo-name)"

  if [[ $email ]]; then
    gpg --auto-key-locate hkps://keys.openpgp.org --locate-external-key "$email"
    gpg -o $td/repo-pubkey.gpg --export "$email"
  fi
fi



### Obtain mirrorlist.

country="$(curl -sS https://ipapi.co/country)"

# Some mirrors do not serve version. Try again, as new execution of 
# https://archlinux.org/mirrorlist/... will get you the list in a different 
# order.
try=0
version=
while [[ $((try++)) -lt 10 ]] && [[ -z $version ]]; do
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

gpg --locate-external-key pierre@archlinux.de

if [[ -e "$pkg/.bootstrap/$bootstrap.sig" ]]; then
  gpg --verify "$pkg/.bootstrap/$bootstrap.sig"
else
  curl   -fo $td/$bootstrap     "$server/iso/latest/$bootstrap"
  curl -sSfo $td/$bootstrap.sig "$server/iso/latest/$bootstrap.sig"

  gpg --verify $td/$bootstrap.sig

  install -d -- "$pkg/.bootstrap"
  mv -- $td/$bootstrap{,.sig} "$pkg/.bootstrap"
fi

tar xf "$pkg/.bootstrap/$bootstrap" --numeric-owner -C $td
chrt=$td/root.x86_64

mv $td/mirrorlist $chrt/etc/pacman.d/mirrorlist



### Prepare bootstrap

btrfs='noatime,noacl,commit=300,autodefrag,compress=zstd'

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
push_clean umount -- "$chrt"
mount --bind      -- "$chrt" "$chrt"

push_clean umount --                                          "$chrt/mnt"
mount -t btrfs -o $btrfs,subvol="$root_vol" UUID="$root_uuid" "$chrt/mnt"

# Use the centralised pkg cache, so previously downloaded packages are
# cached locally.
install -d        --                                          "$chrt/mnt/var/cache/pacman/pkg"
push_clean umount --                                          "$chrt/mnt/var/cache/pacman/pkg"
mount -t btrfs -o $btrfs,subvol="$pkg_vol"  UUID="$pkg_uuid"  "$chrt/mnt/var/cache/pacman/pkg"

push_clean rm -- "$chrt"/root/{bash-header2.sh,stage1-bootstrap.sh}
cp -- "$bin"/{bash-header2.sh,stage1-bootstrap.sh} "$chrt"/root



### Bootstrap

# I use "runuser - root -c" to sanitize the env variables, and '-' makes it 
# a login shell, so /etc/profile is executed. It will pass 
# /root/stage1-bootstrap.sh and the rest to the default shell. To make sure it 
# is bash, I used '-s /bin/bash'.
#
# I need arch-install-scripts to place arch-chroot into $root to use next time 
# (post dropping the bootstrap).
"$chrt/bin/arch-chroot" "$chrt" runuser -s /bin/bash - root --\
  /root/stage1-bootstrap.sh ${debug:+-d} arch-install-scripts



### Clean-up after bootstrap.

pop_clean 4
rm -r $chrt
unset $chrt



### Prepare root

# systemd-tmpfiles created 2 subvolumes if filesystem is btrfs.
# See:
#   - https://bugzilla.redhat.com/show_bug.cgi?id=1327596
#   - https://bbs.archlinux.org/viewtopic.php?id=260291
# I have to get rid of them and replace them with normal dir. Then, they remain 
# normal dirs.
for i in portables machines; do
  btrfs su del -- "$root/var/lib/$i"
  install -d   -- "$root/var/lib/$i"
done


# Pacstrap copies the mirrorlist to the target. Here we make sure that now 
# *.pacnew files is created for the mirrorlist going forward.
sed -i '/^\[options\]/a NoExtract = etc/pacman.d/mirrorlist' $root/etc/pacman.conf

tee -a $root/etc/pacman.conf >/dev/null <<EOF

[multilib]
Include  = /etc/pacman.d/mirrorlist

[xyne-x86_64]
Server   = https://xyne.dev/repos/xyne

[xyne-any]
Server   = https://xyne.dev/repos/xyne

[$repo_name]
Server   = file:///mnt/repo/$repo_name
EOF

if [[ -z $email ]]; then
  echo 'SigLevel = Optional' >>$root/etc/pacman.conf
fi


echo -e "UUID=$root_uuid\t/\tbtrfs\t$btrfs,subvol=$root_vol\t0 0"                         >>$root/etc/fstab
echo -e "UUID=$pkg_uuid\t/var/cache/pacman/pkg\tbtrfs\t$btrfs,subvol=$pkg_vol\t0 0"       >>$root/etc/fstab

if [[ $repo ]]; then
  install -d -- $root/mnt/repo/$repo_name
  echo -e "UUID=$repo_uuid\t/mnt/repo/$repo_name\tbtrfs\t$btrfs,ro,subvol=$repo_vol\t0 0" >>$root/etc/fstab
fi

push_clean rm -- "$root"/root/{bash-header2.sh,stage1-root.sh,repo-pubkey.gpg}
cp -- "$bin"/{bash-header2.sh,stage1-root.sh} $td/repo-pubkey.gpg "$root"/root


if [[ $hostname ]]; then
  echo "$hostname" >$root/etc/hostname
fi



### Finalise root

push_clean umount -- "$root"
mount --bind      -- "$root" "$root"

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root --\
  /root/stage1-root.sh ${debug:+-d} ${pacserve:+-s} "$@"



### Create a snapshot.

btrfs su snap -r -- "$root" "$root_snp/$(date -uIs)"

onexit 0
