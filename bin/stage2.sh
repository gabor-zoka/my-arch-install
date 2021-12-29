#!/usr/bin/env bash
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header.sh)

# Safe setting and should be available.
export LC_ALL=C



debug=
root=
host=
eval set -- "$(getopt -o dr:h: -l root:,host: -n "$(basename "$0")" -- "$@")"
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

if   [[ -z $root ]]; then
  echo "ERROR: Root dir is not set" >&2
  onexit 1
fi



curl -sSfo $root/root/stage2-chroot.sh $gh/stage2-chroot.sh
chmod +x   $root/root/stage2-chroot.sh

"$root/bin/arch-chroot" "$root" /root/stage2-chroot.sh ${debug:+-d} ${host:+-h $host}



### Snapshot the image.

root_snap="$(dirname "$root")/.snapshot/$(basename "$root")"; mkdir -p "$root_snap"
btrfs su snap -r "$root" "$root_snap/$(date -uIm)"

onexit 0
