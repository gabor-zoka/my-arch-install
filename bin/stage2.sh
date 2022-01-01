#!/usr/bin/env -S runuser -s /bin/bash - root --
export LC_ALL=C
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header2.sh)



debug=
root=
host=
eval set -- "$(getopt -o dr:h: -l root:,host: -n "$(basename "$0")" -- "$@")"
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
fi



### Mount /var/cache/pacman/pkg

mount="$(dirname "$root")"
dev="$(findmnt -fn -o source "$mount")"
push_clean umount "$root/var/cache/pacman/pkg"
mount -t btrfs -o noatime,commit=300,subvol=pkg "$dev" "$root/var/cache/pacman/pkg"



### Chroot

curl -sSfo "$root/root/stage2-chroot.sh" $gh/stage2-chroot.sh
chmod +x   "$root/root/stage2-chroot.sh"

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root /root/stage2-chroot.sh ${debug:+-d} ${host:+-h $host}



### Snapshot the image.

btrfs su snap -r "$root" "$(dirname "$root")/.snapshot/$(basename "$root")/$(date -uIs)"

onexit 0
