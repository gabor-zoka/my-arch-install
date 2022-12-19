#!/usr/bin/env -S runuser -s /bin/bash - root --
export LC_ALL=C
bin="$(dirname "$0")"
btrfs='noatime,noacl,commit=300,autodefrag,compress=zstd'

set -e; . "$bin/bash-header2.sh"



debug=
root=
host=
repo=
eval set -- "$(getopt -o dr:p:h:e: -l root:,host:,repo: -n "$(basename "$0")" -- "$@")"
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
elif [[ -z $host ]]; then
  echo "ERROR: Host is not set" >&2
  onexit 1
elif [[ -z $repo ]]; then
  echo "ERROR: Repo is not set" >&2
  onexit 1
fi

root_vol="$(btrfs su show -- "$root" | head -1)"
root_dir="$(dirname -- "$root")"
root_dev="$(findmnt -fn -o source -- "$root_dir")"
pkg="$root_dir/pkg"

case $host in
  bud|gla)
    list=bud
    ;;
  laptop)
    list=laptop
    ;;
  *)
    echo "ERROR: host = $host is invalid" >&2
    onexit 1
esac



if   [[ -z $repo ]]; then
  echo "ERROR: Repo dir is not set" >&2
  onexit 1
fi

repo_vol="$(btrfs su show -- "$repo" | head -1)"
repo_dir="$(dirname -- "$repo")"

if ! repo_dev="$(findmnt -fn -o source -- "$repo_dir")"; then
  echo "ERROR: $repo_dir is not a mount point" >&2
  onexit 1
fi



### Mount /var/cache/pacman/pkg

push_clean umount    "$root"
mount --bind "$root" "$root"

push_clean umount                                          -- "$root/var/cache/pacman/pkg"
mount -t btrfs -o $btrfs,subvol=pkg "$root_dev"            -- "$root/var/cache/pacman/pkg"

install -d                                                 -- "$root/mnt/repo"
push_clean umount                                          -- "$root/mnt/repo"
mount -t btrfs -o $btrfs,ro,subvol="$repo_vol" "$repo_dev" -- "$root/mnt/repo"



### Chroot

cp -- "$bin/stage2-chroot.sh" "$bin/bash-header2.sh" "$bin/../list/$list/"* $root/root

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root -- /root/stage2-chroot.sh ${debug:+-d} ${host:+-h $host}



### Pacnew check

if [[ $(find $root/etc -iname '*.pacnew') ]]; then
  echo "ERROR: *.pacnew file(s) in $root/etc"
  onexit 1
fi



### Snapshot the image.

btrfs su snap -r -- "$root" "$root_snap/$(date -uIs)"

onexit 0
