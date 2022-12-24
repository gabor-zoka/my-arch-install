#!/usr/bin/env bash
set -e; . /root/bash-header2.sh
shopt -s nullglob

export LC_ALL=C

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME=$td/.gnupg
push_clean gpgconf --kill all



### Parameters.

pacserve=
eval set -- "$(getopt -o ds -n "$(basename "$0")" -- "$@")"
while true; do
  case $1 in
    -d)
      set -x
      ;;
    -s)
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



### Prepare the keyring.

push_clean umount -- /var/cache/pacman/pkg
mount             -- /var/cache/pacman/pkg

if [[ -e /mnt/repo ]]; then
  for i in /mnt/repo/*; do
    push_clean umount -- $i
    mount             -- $i
  done
fi



### Pubkey of the custom repo

if [[ -e /root/repo-pubkey.gpg ]]; then
  pacman-key --add /root/repo-pubkey.gpg
  keyid="$(gpg --list-packets /root/repo-pubkey.gpg | grep '^:signature packet:' | head -1 | awk '{print $NF}')"
  pacman-key --lsign-key "$keyid"
fi



### Get latest db-s (note we added new repositories since bootstrap

pacman --noconfirm -Sy



### Pacserve

if [[ $pacserve ]]; then
  pacman --noconfirm --needed -S pacserve

  # Adding the pacserve to pacman.conf.
  sed -i '/^\(Include\|Server\) /i Include = /etc/pacman.d/pacserve' /etc/pacman.conf

  pacman=pacsrv
else
  pacman=pacman
fi



### Install

$pacman --noconfirm --needed -S "$@"

onexit 0
