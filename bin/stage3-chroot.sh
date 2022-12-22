#!/usr/bin/env bash
set -e; . /root/bash-header2.sh
shopt -s nullglob

export LC_ALL=C

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all



### Parameters.

host=
pacserve=
eval set -- "$(getopt -o dh: -l host: -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      set -x
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

if [[ ! -e /etc/pacserve ]]; then
  pacman=pacman
else
  pacman=pacsrv
fi



echo BLAH

onexit 0
