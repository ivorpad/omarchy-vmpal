#!/bin/bash
# In the new Arch Linux ARM system, as root: VMPal's shared folder at each boot,
# then VMPal Tools (Python with PyGObject first, as their install needs it).
set -euo pipefail
install -d /media/VMPal
grep -q '^vmpal ' /etc/fstab || echo 'vmpal /media/VMPal virtiofs defaults,nofail 0 0' >> /etc/fstab
mountpoint -q /media/VMPal || mount /media/VMPal
pacman -S --needed --noconfirm python python-gobject >/var/log/omarchy-vmpal-tools-deps.log 2>&1 ||
  { tail -20 /var/log/omarchy-vmpal-tools-deps.log; exit 1; }
sh "/media/VMPal/VMPal Tools/install.sh"
sleep 3
systemctl is-active vmpal-tools.service
