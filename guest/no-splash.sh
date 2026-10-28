#!/bin/sh
# Omarchy turns on Plymouth's boot splash. In VMPal with GPU acceleration on,
# the splash freezes the VM before Linux starts: a black window, one CPU busy,
# nothing in the journal. This takes `splash` off GRUB's default kernel command
# line and rebuilds grub.cfg. Omarchy's file is kept once as grub.omarchy.
# Run as root after guest/omarchy-install.sh, before the next reboot.
set -eu
cp -n /etc/default/grub /etc/default/grub.omarchy
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { s/ splash\b//g; s/"splash /"/; s/^(GRUB_CMDLINE_LINUX_DEFAULT=)"splash"$/\1""/ }' /etc/default/grub
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
