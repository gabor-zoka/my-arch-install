#!/usr/bin/env bash
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header.sh)

# Safe setting and should be available.
export LC_ALL=C



### Parameters.

eval set -- "$(getopt -o D -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -D)
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
