#!/usr/bin/env -S runuser -s /bin/bash - root --
export LC_ALL=C
gh=https://raw.githubusercontent.com/gabor-zoka/my-arch-install/main/bin
set -e; . <(curl -sS $gh/bash-header2.sh)



debug=
root=
host=
secret=
eval set -- "$(getopt -o dr:h:s: -l root:,host:,secret: -n "$(basename "$0")" -- "$@")"
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
    -s|--secret)
      # Mandatory
      secret="$2"
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



echo $host >$root/etc/hostname

if [[ $host == bud ]] || [[ $host == gla ]]; then
  ln -srf $root/usr/share/zoneinfo/Europe/London $root/etc/localtime

  # U2F needs this
  groupadd -R $root plugdev

  useradd  -R $root -u 1000 -M -G audio,video,optical,plugdev,wheel,games,scard,optical,systemd-journal gabor
  # sys is for printing (CUPS) as per 
  # https://wiki.archlinux.org/title/Users_and_groups#User_groups
  useradd  -R $root -u 1001 -M -G audio,video,optical,plugdev,sys agnes
  useradd  -R $root -u 1002 -M -G audio,video,optical,plugdev     browse
  useradd  -R $root -u 1003 -M -G plugdev                         bank
  useradd  -R $root -u 1004 -M -G audio,kvm                       winxp
  useradd  -R $root -u 1005 -M                                    tax
  useradd  -R $root -u 1006 -M                                    agnes-bank
  useradd  -R $root -u 1011 -M                                    citrix

  usermod  -R $root -a -G agnes,browse,bank,winxp,tax,agnes-bank,citrix gabor

elif [[ $host = laptop ]]; then
  ln -srf $root/usr/share/zoneinfo/Europe/London $root/etc/localtime

  useradd  -R $root -u 1001 -M -G audio,video,optical,plugdev,sys agnes
  useradd  -R $root -u 1006 -M agnes-bank
fi



### ssdh

perl -i -pe '$z+=s{^#Port .*}{Port 32455};END{die if $z!=1}'                                  $root/etc/ssh/sshd_config
perl -i -pe '$z+=s{^#PasswordAuthentication .*}{PasswordAuthentication no};END{die if $z!=1}' $root/etc/ssh/sshd_config



### Network

cat >$root/etc/NetworkManager/NetworkManager.conf <<'EOF'
[main]
plugins=keyfile
dns=dnsmasq
EOF



### Inputrc

perl -i -pe '$z+=s{^#set bell-style.*}{set bell-style none};END{die if $z!=1}' $root/etc/inputrc



### Wifi Powersave Off

if [[ $host == laptop ]]; then
    # To solve the intermittent delays as per
    # http://www3.intel.com/content/www/us/en/support/network-and-i-o/wireless-networking/000005645.html
    # turn off the power save polling.

    # https://wiki.archlinux.org/index.php/Power_management#Network_interfaces
    #
    # Note: In this case, the name of the configuration file is
    # important. Due to the introduction of persistent device names
    # via 80-net-setup-link.rules in systemd, it is important that the
    # network powersave rules are named lexicographically before
    # 80-net-setup-link.rules so that they are applied before the
    # devices are named e.g. enp2s0. However, be advised that commands
    # ran with RUN are executed after all rules have been processed --
    # in which case the naming of the rules file is irrelevant and the
    # persistent device names should be used.
    echo 'ACTION=="add",SUBSYSTEM=="net",KERNEL=="wlan*",RUN+="/usr/bin/iw dev %k set power_save off"'\
        >$root/etc/udev/rules.d/70-wifi-powersave.rules
fi



### X11 Keymap

# This mimics "localectl set-x11-keymap" command, which we cannot use un chroot 
# as it used DBUS.

install -d $root/etc/X11/xorg.conf.d

if [[ $host == laptop ]]; then
    cat   >$root/etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
# Read and parsed by systemd-localed. It's probably wise not to edit this file
# manually too freely.
Section "InputClass"
        Identifier          "system-keyboard"
        MatchIsKeyboard     "on"
        Option "XkbLayout"  "hu"
        Option "XkbModel"   "pc105"
EndSection
EOF
else
    cat   >$root/etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
# Read and parsed by systemd-localed. It's probably wise not to edit this file
# manually too freely.
Section "InputClass"
        Identifier          "system-keyboard"
        MatchIsKeyboard     "on"
        Option "XkbLayout"  "us"
        Option "XkbModel"   "pc105"
        Option "XkbVariant" "altgr-intl"
EndSection
EOF
fi



### Issue

cat >$root/etc/issue <<'EOF'
\S{NAME} \S{VERSION} \r (\l)

EOF



### OS

ver="$host-$(date +%Y%m%d)"

# By default /etc/os-release is a soft-link onto /usr/lib/os-release. 1st we 
# have to remove it otherwise cp failes with "cp: '/usr/lib/os-release' and 
# '/etc/os-release' are the same file"
rm $root/etc/os-release
cp $root/usr/lib/os-release /etc

cat >>$root/etc/os-release <<EOF
VERSION_ID=$ver
VERSION=$ver
EOF



### Systemd

install -d $root/etc/systemd/logind.conf.d
cat       >$root/etc/systemd/logind.conf.d/99-my.conf <<'EOF'
echo KillUserProcesses=yes
EOF

install -d $root/etc/systemd/journald.conf.d
cat       >$root/etc/systemd/journald.conf.d/99-my.conf <<'EOF'
echo SystemMaxUse=50M
EOF

install -d $root/etc/systemd/timesyncd.conf.d
cat       >$root/etc/systemd/timesyncd.conf.d/99-my.conf <<'EOF'
# As per http://www.pool.ntp.org/en/use.html these hosts
# will connect to the closest servers.
NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
# Windows time server
FallbackNTP=time-nw.nist.gov
EOF

# https://wiki.archlinux.org/index.php/Iptables#Configuration_and_usage
#
# Security reasons it is recommended that firewalls be started before the 
# network-pre.target target so that the firewall is running before any network 
# is configured.
install -d $root/etc/systemd/system/iptables.service.d
cat       >$root/etc/systemd/system/iptables.service.d/00-pre-network.conf <<'EOF'
[Unit]
Wants=network-pre.target
Before=network-pre.target
EOF



### /etc/fstab

root_uuid=$(findmnt -fn -o uuid $(dirname $root))
home_uuid=$(findmnt -fn -o uuid $(dirname $home))
boot_uuid=$(findmnt -fn -o uuid $(dirname $boot))

cat $root/etc/fstab <<EOF
UUID=$root_uuid     /            btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,subvol=$(basename $root)  0 0
UUID=$root_uuid     /mnt/syst    btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,noauto                    0 0
UUID=$home_uuid     /home        btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,subvol=$(basename $home)  0 0
UUID=$home_uuid     /mnt/data    btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,noauto                    0 0
UUID=$boot_uuid     /mnt/boot    ext4   noatime,noacl,commit=300,noauto_da_alloc,noauto                             0 2

/dev/cdrom    /mnt/cdrom   auto   noatime,noauto                                     0 0
/dev/camera1  /mnt/camera  vfat   noatime,utf8,uid=gabor,gid=gabor,noauto            0 0

# vers=1.0 is very important as WinXP only supports this acient version. If not
# set, it hangs as Linux depreciated this.
//192.168.0.103/shared  /mnt/winxp-laptop  cifs  user=Administrator,uid=gabor,gid=gabor,iocharset=utf8,file_mode=0660,dir_mode=0770,vers=1.0,noauto  0 0

LABEL=00  /mnt/00  ext4   noatime,noacl,noauto_da_alloc,noauto                      0 0
LABEL=01  /mnt/01  btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,noauto  0 0
LABEL=02  /mnt/02  ext4   noatime,noacl,noauto_da_alloc,noauto                      0 0
EOF

for i in {03..39}; do
  echo "LABEL=$i  /mnt/$i  btrfs  noatime,noacl,commit=300,autodefrag,compress=zstd,noauto  0 0" >>$root/etc/fstab
done

mkdir /mnt/{syst,data,boot,cdrom,camera,winxp-laptop} /mnt/{00..39}



### Mount /var/cache/pacman/pkg

push_clean umount    "$root"
mount --bind "$root" "$root"

mount="$(dirname "$root")"
dev="$(findmnt -fn -o source "$mount")"
push_clean umount "$root/var/cache/pacman/pkg"
mount -t btrfs -o noatime,commit=300,subvol=pkg "$dev" "$root/var/cache/pacman/pkg"



### Chroot

curl -sSfo "$root/root/stage2-chroot.sh" $gh/stage2-chroot.sh
chmod +x   "$root/root/stage2-chroot.sh"

"$root/bin/arch-chroot" "$root" runuser -s /bin/bash - root -- /root/stage3-chroot.sh ${debug:+-d} ${host:+-h $host}



### Secrets

# pacman will use a gpg, too, so have our own just like in stage1.sh.
export GNUPGHOME="$secret/.gnupg"
push_clean gpgconf --kill all

# SHA512 is the new Arch default.
cat | chpasswd -c SHA512 -R $root <<EOF
root:$(gpg       -d "$secret"/.password-store/tech/linux/root.gpg       | head -1)
agnes:$(gpg      -d "$secret"/.password-store/tech/linux/agnes.gpg      | head -1)
agnes-bank:$(gpg -d "$secret"/.password-store/tech/linux/agnes-bank.gpg | head -1)
EOF



### Snapshot the image.

btrfs su snap -r "$root" "$(dirname "$root")/.snapshot/$(basename "$root")/$(date -uIs)"



### Advice

if [[ $host == laptop ]]; then
  cat <<'EOF'

Printer (CUPS) Setup
====================
- Connect up the printer
- Log in as agnes
- Visit http://localhost:631/admin
- Choose "Add Printer". You will be prompted for login id and login
  password. You should be able to select the printer connected.
- Set the default values (like using A4 papers).

Display
=======
- Plug in the HDMI cable
- Settings->Devices->Display->Display Mode->Set it to Mirror (i.e. show the 
  same on both screens).

EOF
fi

cat <<'EOF'
Multimedia
==========
- Login as agnes/julcsi
- After upgrade audio via Chrome did not work. This sorted it:

  killall pulseaudio && rm -rf ~agnes/.config/pulse && pulseaudio --start

- Put up the input volume. (It is off by default.)

  ponymix unmute && ponymix set-volume 60

- Check you can click on mp3 or mp4 and VLC comes up. (In the past when 
  mplayer was installed, it ran mplayer, but then nothing showed up on the 
  screen, and one could not close the player.)

EOF

onexit 0
