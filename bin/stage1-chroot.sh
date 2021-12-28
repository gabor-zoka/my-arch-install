#!/usr/bin/env bash
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header.sh)

# Safe setting and should be available.
export LC_ALL=C



### Prepare the keyring.

pacman-key --init
pacman-key --populate archlinux
# Update the db-s, and also refresh archlinux-keyring. (Often *.iso image has 
# obsolete keyring, which makes the install fail.)
pacman -Sy --noconfirm --needed archlinux-keyring



# Install all modules passed as parameters.
pacstrap "$@"

onexit 0
