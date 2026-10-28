#!/bin/bash
# Install Arch Linux ARM onto the VMPal VM's disk from the Alpine live ISO.
# Adapted from OmacVM's src/vm/base-install.sh (MIT, Gilles Goetsch): same disk
# layout (GPT, 2 GiB EFI at /boot + btrfs @, @home, @log), same base packages,
# user, sudo, key-only root SSH and GRUB with a --removable copy. Alpine has no
# pacstrap, so the system comes from Arch Linux ARM's signed root tarball and
# the rest is installed with pacman inside a chroot.
# Needs /root/omacvm.env (OMA_*), /root/omacvm.pub and /root/user.pass.
set -euo pipefail
source /root/omacvm.env
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    if (( i < 3 )); then echo "failed (try $i of 3), again in $((i * 10)) s: $*" >&2; sleep $((i * 10)); fi
  done
  return 1
}

D=$(lsblk -dnpbo NAME,SIZE,TYPE,RO,RM | awk '$1 ~ /^\/dev\/(nvme[0-9]+n[0-9]+|vd[a-z]+|sd[a-z]+)$/ && $3 == "disk" && $4 == 0 && $5 == 0 { print $2, $1 }' | sort -rn | awk 'NR == 1 { print $2 }')
[[ -b ${D:-} ]] || { lsblk -dnpo NAME,SIZE,TYPE,RO,RM,TRAN >&2; die "no writable fixed disk found"; }
[[ $D =~ [0-9]$ ]] && P=${D}p || P=$D
log "target disk: $D ($(lsblk -dno SIZE "$D"))"

log "clock"
web=$(curl -sI --max-time 6 http://mirror.archlinuxarm.org/aarch64/core/core.db 2>/dev/null |
  tr -d '\r' | sed -n 's/^[Dd]ate: //p' | head -1 || true)
if [[ -n $web ]] && ref=$(date -u -d "$web" +%s 2>/dev/null); then
  off=$(( $(date -u +%s) - ref ))
  if (( off > 300 || off < -300 )); then date -u -s "@$ref" >/dev/null || echo "WARNING: could not set the clock"; fi
fi
echo "clock: $(date -u '+%F %T') UTC"

log "partitions on $D"
sgdisk --zap-all "$D" >/dev/null
sgdisk -n1:1MiB:+2GiB -t1:ef00 -c1:EFI -n2:0:0 -t2:8300 -c2:omarchy "$D" >/dev/null
# Alpine's mdev doesn't make the new partitions' nodes on its own.
partx -u "$D" 2>/dev/null || blockdev --rereadpt "$D" 2>/dev/null || true
mdev -s 2>/dev/null || true
for i in 1 2 3 4 5 6 7 8 9 10; do [[ -b ${P}1 && -b ${P}2 ]] && break; sleep 1; mdev -s 2>/dev/null || true; done
[[ -b ${P}1 && -b ${P}2 ]] || die "the new partitions didn't show up as ${P}1 and ${P}2"
mkfs.fat -F32 -n OMARCHYEFI "${P}1" >/dev/null
mkfs.btrfs -f -L omarchy "${P}2" >/dev/null
mount "${P}2" /mnt
for s in @ @home @log; do btrfs subvolume create "/mnt/$s" >/dev/null; done
umount /mnt
O=noatime,compress=zstd:1,space_cache=v2,discard=async
mount -o "$O,subvol=@" "${P}2" /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/boot
mount -o "$O,subvol=@home" "${P}2" /mnt/home
mount -o "$O,subvol=@log" "${P}2" /mnt/var/log
mount -o umask=0077 "${P}1" /mnt/boot

log "Arch Linux ARM root filesystem (signed tarball)"
T=/mnt/var/tmp/alarm; mkdir -p "$T"
U=https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
retry curl -fsSL -o "$T/root.tar.gz.sig" "$U.sig" || die "could not get the tarball's signature"
retry curl -fsSL -o "$T/root.tar.gz" "$U" || die "could not get the tarball"
export GNUPGHOME=$(mktemp -d)
FPR=68B3537F39A313B3E574D06777193F152BDBE6A6
retry curl -fsSL -o "$GNUPGHOME/alarm.asc" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$FPR" || die "could not get the ALARM build key"
gpg -q --import "$GNUPGHOME/alarm.asc" 2>/dev/null
gpg --batch --status-fd 1 --verify "$T/root.tar.gz.sig" "$T/root.tar.gz" 2>/dev/null | grep -q "VALIDSIG $FPR" ||
  die "the tarball's signature is not a valid one by $FPR"
echo "signature: valid, by $FPR"
# /boot is the FAT EFI partition: the kernel package is installed again with
# pacman below, which writes it there.
bsdtar -xpf "$T/root.tar.gz" -C /mnt --exclude './boot/*' --exclude 'boot/*'
rm -rf "$T" "$GNUPGHOME"

log "fstab"
root_uuid=$(blkid -s UUID -o value "${P}2"); efi_uuid=$(blkid -s UUID -o value "${P}1")
cat > /mnt/etc/fstab <<EOF
UUID=$root_uuid / btrfs $O,subvol=@ 0 0
UUID=$root_uuid /home btrfs $O,subvol=@home 0 0
UUID=$root_uuid /var/log btrfs $O,subvol=@log 0 0
UUID=$efi_uuid /boot vfat umask=0077 0 2
EOF

log "chroot"
install -m600 /root/omacvm.env /mnt/root/omacvm.env
install -m600 /root/omacvm.pub /mnt/root/omacvm.pub
install -m600 /root/user.pass /mnt/root/user.pass
for d in proc sys dev run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
rm -f /mnt/etc/resolv.conf; cp -L /etc/resolv.conf /mnt/etc/resolv.conf
cat > /mnt/root/setup-base.sh <<'EOF'
set -euo pipefail
source /root/omacvm.env
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
retry() { local i; for i in 1 2 3; do "$@" && return 0; (( i < 3 )) && sleep $((i * 10)); done; return 1; }
log "package signing keys"
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1
log "fastest Arch Linux ARM mirrors from here"
ranked=$(for m in de3 de4 dk hu nl fl.us ca.us nj.us il.us tx.us; do
  if t=$(curl -fo /dev/null -s -w '%{time_total}' --max-time 6 "https://$m.mirror.archlinuxarm.org/aarch64/core/core.db"); then
    printf '%s %s\n' "$t" "$m"
  fi
done | sort -n | head -4 | awk '{ print $2 }' || true)
{ for m in $ranked; do echo "Server = https://$m.mirror.archlinuxarm.org/\$arch/\$repo"; done
  echo 'Server = http://mirror.archlinuxarm.org/$arch/$repo'; } > /etc/pacman.d/mirrorlist
cat /etc/pacman.d/mirrorlist
log "system update and base packages"
retry pacman -Syu --noconfirm >/var/log/omarchy-vmpal-pacman.log 2>&1 || { tail -20 /var/log/omarchy-vmpal-pacman.log; exit 1; }
retry pacman -S --noconfirm --needed base base-devel linux-aarch64 linux-aarch64-headers archlinuxarm-keyring \
  btrfs-progs dosfstools grub efibootmgr openssh sudo git networkmanager nano vim man-db >>/var/log/omarchy-vmpal-pacman.log 2>&1 ||
  { tail -20 /var/log/omarchy-vmpal-pacman.log; exit 1; }
# The kernel's files went to the FAT /boot only if pacman wrote them there: make sure.
[[ -s /boot/Image ]] || retry pacman -S --noconfirm linux-aarch64 >>/var/log/omarchy-vmpal-pacman.log 2>&1
ls /boot
log "base system: $OMA_TZ, $OMA_LANG, keyboard $OMA_XKB_LAYOUT, user $OMA_USER"
userdel -r alarm 2>/dev/null || true
ln -sf "/usr/share/zoneinfo/$OMA_TZ" /etc/localtime
grep -q "^${OMA_LANG} " /usr/share/i18n/SUPPORTED || OMA_LANG=en_US.UTF-8
sed -i "s/^#en_US.UTF-8/en_US.UTF-8/; s/^#${OMA_LANG}/${OMA_LANG}/" /etc/locale.gen
locale-gen >/dev/null
echo "LANG=$OMA_LANG" > /etc/locale.conf
keymap=$(awk -v l="$OMA_XKB_LAYOUT" -v v="${OMA_XKB_VARIANT:-}" \
  '!/^#/ && $2 == l && ($4 == v || (v == "" && $4 == "-")) { print $1; exit }' /usr/share/systemd/kbd-model-map)
echo "KEYMAP=${keymap:-us}" > /etc/vconsole.conf
echo "$OMA_HOSTNAME" > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s.localdomain %s\n' "$OMA_HOSTNAME" "$OMA_HOSTNAME" > /etc/hosts
useradd -m -G wheel -s /bin/bash -c "$OMA_FULLNAME" "$OMA_USER"
chpasswd < /root/user.pass; rm -f /root/user.pass
passwd -l root >/dev/null
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
install -d -m700 /root/.ssh; install -m600 /root/omacvm.pub /root/.ssh/authorized_keys
install -d /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-omacvm.conf <<EOT
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOT
# NetworkManager runs the network, as in Omarchy: the tarball's systemd-networkd goes.
systemctl disable systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true
systemctl enable NetworkManager sshd systemd-timesyncd fstrim.timer >/dev/null 2>&1
log "initramfs and GRUB"
mkinitcpio -P >/var/log/omarchy-vmpal-mkinitcpio.log 2>&1 || { tail -20 /var/log/omarchy-vmpal-mkinitcpio.log; exit 1; }
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/; s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet mitigations=off nowatchdog"/; s/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub
# Arch Linux ARM's kernel is /boot/Image, a name GRUB's 10_linux doesn't pair
# with initramfs-linux.img: name the initramfs, or the entries boot without it.
grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM=' /etc/default/grub ||
  echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="initramfs-linux.img"' >> /etc/default/grub
mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
grub-install --target=arm64-efi --efi-directory=/boot --bootloader-id=GRUB 2>&1 | tail -1
grub-install --target=arm64-efi --efi-directory=/boot --removable 2>&1 | tail -1
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -1
rm /root/omacvm.pub
EOF
chroot /mnt /bin/bash /root/setup-base.sh
rm -f /mnt/root/setup-base.sh
sync
# The rbind mounts keep /mnt/dev busy for a plain umount -R.
umount -lR /mnt
log "base system installed on $D"
