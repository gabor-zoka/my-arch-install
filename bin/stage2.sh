#!/usr/bin/env -S runuser -s /bin/bash - root --
bin="$(dirname "$0")"
set -e; . "$bin/bash-header2.sh"
shopt -s nullglob



export LC_ALL=C



debug=
root=
eval set -- "$(getopt -o dr: -l root: -n "$(basename "$0")" -- "$@")"
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

if [[ -z $root ]]; then
  echo "ERROR: Root is not set" >&2
  onexit 1
fi

root_snap="$(dirname -- "$root")/.snapshot/$(basename -- "$root")"



### Mount for chroot

push_clean umount -- "$root"
mount --bind      -- "$root" "$root"



### Chroot

push_clean rm -r -- "$root"/root/.my-arch-install
install       -d -- "$root"/root/.my-arch-install
cp -- "$bin"/{bash-header2.sh,stage2-root.sh} "$root"/root/.my-arch-install

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root --\
  /root/.my-arch-install/stage2-root.sh ${debug:+-d} "$@"



### Snapshot the image.

btrfs su snap -r -- "$root" "$root_snap/$(date -uIs)"

onexit 0
