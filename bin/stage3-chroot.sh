### Firewall

cmd=(set-simple-stateful-firewall --ssh-port 32455 --wan eth0)

if [[ $host == laptop ]]; then
  cmd+=(--wan wlan0)
elif [[ $host == bud ]]; then
  # Open port 8000 in the local network for installing on laptop and
  # julcsi with --local-mirror bud (prior to pacserv).    
  cmd+=(--local-port 8000 --local-port 8001)
fi

# /etc/iptables dir has already been created by the "iptables" package.
"${cmd[@]}" >/etc/iptables/iptables.rules
chmod og-rwx /etc/iptables/iptables.rules



{
  echo 'auth sufficient pam_exec.so quiet expose_authtok /usr/bin/pam-gpg-smartcard-wrapper gabor'
  echo
  cat /etc/pam.d/system-auth
} | sponge /etc/pam.d/system-auth



# "timedatectl set-ntp true" cannot be used as DBUS is not available in chroot. 
# This command simply starts and enables systemd-timesyncd service.
systemctl enable NetworkManager sshd iptables systemd-timesyncd chk-boot

if   [[ $host == laptop ]]; then
  systemctl enable bluetooth cups
elif [[ $host == bud ]] || [[ $host == gla ]]; then
  systemctl enable kill-gpg-agent
elif [[ $host == bud ]] || [[ $host == laptop ]]; then
  systemctl enable ddclient
fi



### Post-Install Steps

pkgfile --update

if [[ $host == laptop ]]; then
  # To stop this ****er to pop up constantly.
  pacman --noconfirm -ddR gnome-keyring
fi






