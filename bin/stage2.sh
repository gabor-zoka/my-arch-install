#!/usr/bin/env -S runuser -s /bin/bash - root --
bin="$(dirname "$0")"
set -e; . "$bin/bash-header2.sh"
shopt -s nullglob



export LC_ALL=C



debug=
root=
host=
repo=
pacserve=
eval set -- "$(getopt -o dr:h:e:p -l root:,host:,repo:,pacserve -n "$(basename "$0")" -- "$@")"
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
    -p|--pacserve)
      pacserve=y
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
  echo "ERROR: Root is not set" >&2
  onexit 1
elif [[ -z $host ]]; then
  echo "ERROR: Host is not set" >&2
  onexit 1
elif [[ -z $repo ]]; then
  echo "ERROR: Repo is not set" >&2
  onexit 1
fi

root_dir="$(dirname -- "$root")"
root_vol="$(btrfs su show -- "$root" | head -1)"
root_dev="$(findmnt -fn -o source -- "$root_dir")"
root_snap="$root_dir/.snapshot/$(basename -- "$root")"

pkg="$root_dir/pkg"

if   [[ -z $repo ]]; then
  echo "ERROR: Repo is not set" >&2
  onexit 1
fi

repo_dir="$(dirname -- "$repo")"
repo_vol="$(btrfs su show -- "$repo" | head -1)"

if ! repo_dev="$(findmnt -fn -o source -- "$repo_dir")"; then
  echo "ERROR: $repo_dir is not a mount point" >&2
  onexit 1
fi

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



### Mount for chroot

btrfs='noatime,noacl,commit=300,autodefrag,compress=zstd'

push_clean umount -- "$root"
mount --bind      -- "$root" "$root"

push_clean umount                              --             "$root/var/cache/pacman/pkg"
mount -t btrfs -o $btrfs,subvol=pkg            -- "$root_dev" "$root/var/cache/pacman/pkg"

install -d                                     --             "$root/mnt/repo"
push_clean umount                              --             "$root/mnt/repo"
mount -t btrfs -o $btrfs,subvol="$repo_vol",ro -- "$repo_dev" "$root/mnt/repo"



### Chroot

push_clean rm -- "$root"/root/{bash-header2.sh,stage2-chroot.sh,exp.list,grp.list}
cp -- "$bin"/{bash-header2.sh,stage2-chroot.sh} "$bin/../list/$list"/{exp.list,grp.list} "$root"/root

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root --\
  /root/stage2-chroot.sh ${debug:+-d} ${host:+-h $host} ${pacserve:+-p}



### Pacnew check

if [[ $(find $root/etc -iname '*.pacnew') ]]; then
  echo "ERROR: *.pacnew file(s) in $root/etc"
  onexit 1
fi



### Snapshot the image.

btrfs su snap -r -- "$root" "$root_snap/$(date -uIs)"

onexit 0
