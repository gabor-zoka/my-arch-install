#!/usr/bin/env bash
set -e; . "$(dirname "$0")"/bash-header2.sh
shopt -s nullglob



### Parameters.

eval set -- "$(getopt -o d -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      set -x
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



### Env

set +u
. /etc/profile
set -u

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all



### Mount pkg and repo

push_clean umount -- /var/cache/pacman/pkg
mount             -- /var/cache/pacman/pkg

if [[ -e /mnt/repo ]]; then
  for i in /mnt/repo/*; do
    push_clean umount -- $i
    mount             -- $i
  done
fi

push_clean umount -- /home
mount             -- /home



### Run

"$@"

onexit 0
