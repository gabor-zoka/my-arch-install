#!/usr/bin/env bash
set -e; . /root/bash-header2.sh
shopt -s nullglob

export LC_ALL=C

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all



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



### Prepare the keyring.

pacman-key --init
pacman-key --populate archlinux

# Update the db-s, and also refresh archlinux-keyring. (Often *.iso image has 
# obsolete keyring, which makes the install fail.)
pacman -Sy --noconfirm --needed archlinux-keyring

# Install all modules passed as parameters.
pacstrap "$@"

onexit 0
