# Omarchy in VMPal

How to install [Omarchy](https://omarchy.org) 4 in a [VMPal](https://vmpal.com) virtual machine on an Apple Silicon Mac, with the desktop drawn on the Mac's GPU. VMPal has no Omarchy in its catalog, so the install is by hand: Alpine's ISO as the installer, Arch Linux ARM's root filesystem, then [omarchy-mac](https://github.com/omacom/omarchy-mac)'s installer. [OmacVM](https://github.com/gillesgoetsch/OmacVM) automates the same route for UTM, VMware Fusion and Parallels, and three of these scripts come from it.

If you only want to try Omarchy on a Mac, use [Try Omarchy](https://github.com/omacom/try-omarchy) instead. It is the official app and needs no setup.

Tested on 2026-10-28: MacBook Pro M3 Pro, macOS 27.0.1, VMPal 0.97, Alpine 3.23.7, Arch Linux ARM kernel 7.3.0, omarchy-mac 4.0.3rc4 (rc channel), Qt 6.12.0, Mesa 26.2.5. Hyprland reports `virgl (Apple M3 Pro)` as its renderer.

## What works

Checked in the running VM on 2026-10-28. "Not tested" means installed but not exercised.

Works:
- The desktop: Hyprland on the GPU, 2880×1696 at 120 Hz for a 1440×848 window, at scale 2.
- Omarchy's top bar, menu (Super + Space) and notifications, once the Qt 6.12 fix below is in.
- The terminal (Super + Return), Chromium, and the Tokyo Night theme.
- The screensaver after 150 s idle, the lock screen after 300 s, and unlocking it with the password.
- `grim`, which Omarchy's screenshots use, captures the full 2880×1696 display. The screenshot keys weren't tried.
- The Mac's battery shows up in Linux: VMPal Tools give it an `AC` and a `BAT0` that report the Mac's.
- VMPal's shared folder (`/media/VMPal`), VMPal Tools (system and desktop parts), and SSH.
- Keys: the right ⌘ is Super; the left ⌘ sends Ctrl for Mac shortcuts.

Doesn't work:
- Sound, out or in. VMPal gives the VM a virtio sound device, but Arch Linux ARM's kernel has no `virtio_snd` driver, so Linux finds no sound card. Omarchy's own `linux-omarchy` kernel (7.3, in its ARM repo) might have it; not tried.
- Screen recording. `gpu-screen-recorder` stops with `no usable output found`, and `wf-recorder` hangs without writing a file.
- Vulkan, and the games and apps that need it: VMPal's VirGL offers OpenGL only, and Hyprland gets OpenGL ES 3.0.
- Wi-Fi and Bluetooth: the VM has neither, only VMPal's virtual Ethernet, so those panels have nothing to manage.
- Omarchy's Windows VM: it needs KVM, and `/dev/kvm` doesn't exist while VMPal's nested virtualization is off, the default. `bin/vmpal set Omarchy --nested on` may change that; not tried.
- Hardware video decoding: there's no decoder device, so video plays on the CPU.
- Dictation: there's no microphone. VMPal's is off by default, and there's no sound card anyway.
- Suspend, and Linux apps as separate Mac windows, which VMPal does for GNOME only.

Set up but not tested:
- Clipboard and drag and drop between the Mac and Omarchy. Both are on in VMPal, and VMPal Tools have Hyprland support for them.
- Touch ID. VMPal Tools added the fingerprint rule for Omarchy's lock screen, which now asks for a finger, but VMPal's Touch ID setting is unset.
- Docker (its socket is active), Neovim, LibreOffice, Obsidian, LocalSend, mpv, text extraction (tesseract is installed), web apps, and `omarchy update`.

## Before you start

- macOS 27: VMPal says GPU acceleration for Linux needs it.
- About 30 GB free.
- Commands run from this folder. `bin/vmpal` is VMPal's own command line, run from inside the app, so nothing needs installing.

## 1. Key, settings and password

```sh
ssh-keygen -t ed25519 -N "" -C omarchy-vmpal -f ~/.ssh/omarchy-vmpal_ed25519
cp guest/omacvm.env.example guest/omacvm.env   # your user name, timezone, keyboard, hostname
touch ~/omarchy-vmpal-password.txt && chmod 600 ~/omarchy-vmpal-password.txt   # then put the password in it
```

## 2. Alpine's installer ISO

```sh
curl -L --remote-name-all https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-standard-3.23.7-aarch64.iso{,.sha256,.asc}
shasum -a 256 -c alpine-standard-3.23.7-aarch64.iso.sha256
curl -s https://alpinelinux.org/keys/ncopa.asc | gpg --import
gpg --verify alpine-standard-3.23.7-aarch64.iso.asc alpine-standard-3.23.7-aarch64.iso
```

The signing key's fingerprint should be `0482 D840 22F5 2DF1 C4E7 CD43 293A CD09 07D9 495A`, as published on [alpinelinux.org/downloads](https://alpinelinux.org/downloads/).

Archboot's ARM64 ISO didn't work here: under VMPal it never reached a network address or a screen.

## 3. The VM

```sh
bin/vmpal create --file alpine-standard-3.23.7-aarch64.iso --name Omarchy --cpus 6 --memory 8 --disk 64
```

VMPal doesn't recognise the ISO, so it boots it in the VM's window to be installed by hand, with Apple's graphics until the system counts as installed.

## 4. SSH into the installer

In the VM's window, log in as `root` (no password) and run:

```sh
setup-interfaces -a -r
setup-apkrepos -1
setup-sshd -c openssh -k "<the contents of ~/.ssh/omarchy-vmpal_ed25519.pub>"
ip addr
```

VMPal Tools aren't in the installer yet, so clipboard sharing isn't available. Type the key, or let VMPal type it through its MCP server:

```sh
id=$(bin/vmpal info Omarchy --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
args=$(python3 -c 'import json,sys; print(json.dumps({"timeoutMs": 45000, "actions": [{"action": "type", "text": "setup-sshd -c openssh -k \"%s\"\n" % open(sys.argv[1]).read().strip()}]}))' ~/.ssh/omarchy-vmpal_ed25519.pub)
bin/vmpal-mcp.py --mcp "$id" -- vmpal_act "$args"
```

`ip addr` shows the VM's address on VMPal's shared network, 192.168.64.x.

## 5. Arch Linux ARM

`guest/base-install-alpine.sh` erases the VM's disk (the largest writable fixed disk; the ISO is read-only and skipped). It lays out GPT with a 2 GiB EFI partition and btrfs (`@`, `@home`, `@log`), installs Arch Linux ARM's signed root tarball, checks its signature against key `68B3537F39A313B3E574D06777193F152BDBE6A6` ([archlinuxarm.org](https://archlinuxarm.org/about/package-signing)), then adds the base packages, your user, key-only root SSH and GRUB.

```sh
export VM_IP=192.168.64.x
bin/vmssh 'apk add bash util-linux libarchive-tools sgdisk dosfstools btrfs-progs curl coreutils e2fsprogs gnupg'
bin/vmssh 'umask 077; cat > /root/omacvm.env' < guest/omacvm.env
bin/vmssh 'umask 077; cat > /root/omacvm.pub' < ~/.ssh/omarchy-vmpal_ed25519.pub
{ printf '%s:' "$(sed -n 's/^OMA_USER=//p' guest/omacvm.env)"; cat ~/omarchy-vmpal-password.txt; } | bin/vmssh 'umask 077; cat > /root/user.pass'
bin/vmssh 'cat > /root/base-install-alpine.sh' < guest/base-install-alpine.sh
bin/vmssh 'setsid nohup bash /root/base-install-alpine.sh > /root/base-install.log 2>&1 < /dev/null &'
bin/vmssh 'tail -f /root/base-install.log'   # until "base system installed"
bin/vmssh reboot
```

The VM comes back from its own disk at the same address.

## 6. VMPal Tools and GPU acceleration

```sh
bin/vmssh 'bash -s' < guest/post-base.sh
bin/vmpal set Omarchy --gpu on
bin/vmpal stop Omarchy && bin/vmpal start Omarchy --wait
```

VMPal treats a hand-installed VM as still installing (no snapshots, Apple's graphics) until it has been shut down once with VMPal Tools inside. After this start, `bin/vmpal info Omarchy --json` shows `"installed": true` and GPU acceleration in the session. The guest sees a virtio-gpu with VirGL (`[drm] features: +virgl`).

A Linux VM with GPU acceleration has to be shut down for a snapshot. This is a good point for one:

```sh
bin/vmpal stop Omarchy && bin/vmpal snapshot Omarchy base && bin/vmpal start Omarchy --wait
```

## 7. Omarchy

```sh
bin/vmssh 'install -Dm755 /dev/stdin /usr/local/lib/omacvm/omarchy-targets.sh' < guest/omarchy-targets.sh
bin/vmssh 'cat > /root/omarchy-install.sh' < guest/omarchy-install.sh
bin/vmssh 'setsid nohup bash /root/omarchy-install.sh > /root/omarchy-install.out 2>&1 < /dev/null &'
bin/vmssh 'tail -f /root/omarchy-install.out'   # until "Omarchy installed"
```

`omarchy-targets.sh` has to be in place first: without it the installer stops with `target not found: hyprtoolkit`. Wait until the script has exited (`bin/vmssh 'pgrep -f omarchy-install.sh'` prints nothing): it removes its temporary passwordless sudo rule at the end. Then, before rebooting:

```sh
bin/vmssh 'sh -s' < guest/no-splash.sh
bin/vmssh 'install -Dm755 /dev/stdin /usr/local/lib/omarchy-vmpal/pin-qtquick.sh && /usr/local/lib/omarchy-vmpal/pin-qtquick.sh' < guest/pin-qtquick.sh
bin/vmssh 'install -Dm644 /dev/stdin /etc/pacman.d/hooks/zz-omarchy-vmpal-qtquick.hook' < guest/zz-omarchy-vmpal-qtquick.hook
bin/vmssh 'pacman -S --noconfirm omarchy/quickshell'
bin/vmpal restart Omarchy
```

The last `pacman` line installs Omarchy's own Quickshell build instead of Arch Linux ARM's. That is the setup tested; on its own it didn't fix the bar.

## 8. First login

SDDM asks for the password at every boot; there is no autologin. Once in, two settings make it fit VMPal's display and a non-US keyboard. Hyprland reloads them on save.

- `~/.config/hypr/monitors.lua`: `local omarchy_monitor_scale = 2`. VMPal makes the display twice the window's size in points, and Omarchy's `auto` picks 1.
- `~/.config/hypr/input.lua`: for example `hl.config({ input = { kb_layout = "es" } })`.

In VMPal the right ⌘ is Super: right ⌘ + Space opens Omarchy's menu, right ⌘ + Return a terminal. The left ⌘ stays a Mac shortcut key (⌘C sends Ctrl+C).

## What went wrong, and the fix for each

- **No splash.** Omarchy enables Plymouth's boot splash. With GPU acceleration on, the VM froze before Linux started: black window, one CPU at 100%, nothing in the journal. With GPU acceleration off it booted. `guest/no-splash.sh` takes `splash` off GRUB's command line. In the tested install that line was edited by hand; the script does the same edit and was tested on sample lines, not on a full install.
- **Qt 6.12's `Color`.** The bar, menu and notifications came up empty. Arch Linux ARM ships Qt 6.12, which added a QML type named `Color` (`QtQuick/Color 6.12`). Omarchy's shell has its own `Color` singleton and imports QtQuick unversioned, so Qt's type shadows it and every theme lookup is undefined (`Cannot read property 'background' of undefined`). `guest/pin-qtquick.sh` caps the 96 imports at `QtQuick 6.11`, and the pacman hook repeats it after Omarchy updates.
- **Missing Hyprland helpers.** omarchy-mac's installer asks Omarchy's repo for `hyprtoolkit` and `hyprland-guiutils`, which it stopped publishing for ARM on 2026-10-18 ([omarchy-mac#741](https://github.com/omacom/omarchy-mac/issues/741)). OmacVM's `omarchy-targets.sh` lets pacman take Arch Linux ARM's builds and installs a hook that keeps doing so.
- **GRUB without the initramfs.** Arch Linux ARM's kernel is `/boot/Image`, a name GRUB's config generator doesn't pair with `initramfs-linux.img`. `base-install-alpine.sh` names it with `GRUB_EARLY_INITRD_LINUX_CUSTOM`.
- **Alpine's device nodes.** Alpine's mdev doesn't create nodes for new partitions; the script runs `partx -u` and `mdev -s`.

## Limitations

VMPal (beyond the list above):
- A GPU-accelerated Linux VM has to be shut down for a snapshot, and quitting VMPal shuts it down.
- `vmpal set --user` rejected the user name in VMPal 0.97, so VMPal couldn't keep the password for its sign-in feature. Its Linux Touch ID option wasn't tried.
- VMPal shares the Mac's `~/Downloads` read-write into the VM by default (`/media/VMPal/Downloads`).
- Linux sees a 931 GiB disk; VMPal caps the VM at the `--disk` size, and Linux doesn't know about the cap.
- The shared-network address stopped answering from the Mac for a few minutes once, while the VM kept its internet.
- Not tried: non-Retina external displays, and how VMPal handles the notch.

This build:
- omarchy-mac's release candidate on Arch Linux ARM, not the image Try Omarchy runs, with Arch Linux ARM's Qt, Mesa and kernel. Qt 6.12 already broke the shell once.
- Arch Linux ARM's `[extra]` comes before `[omarchy]` in `pacman.conf`, so an update can pick Arch's version of a package Omarchy also builds.
- No Snapper snapshots in GRUB's menu (`grub-btrfs` isn't installed), and with GPU acceleration on the boot menu doesn't show anyway. Use VMPal snapshots to roll back.

## Files

- `bin/vmpal`: VMPal's command line, from inside the app.
- `bin/vmssh`, `bin/vmshot`: SSH into the VM, and a screenshot of the desktop taken inside it with grim.
- `bin/vmpal-mcp.py`: a small client for VMPal's per-VM MCP server (screen and keyboard).
- `guest/base-install-alpine.sh`: Arch Linux ARM from the Alpine installer.
- `guest/post-base.sh`: VMPal's shared folder and VMPal Tools.
- `guest/omarchy-install.sh`, `guest/omarchy-targets.sh`: omarchy-mac's installer, unattended, with the package fix.
- `guest/no-splash.sh`, `guest/pin-qtquick.sh`, `guest/zz-omarchy-vmpal-qtquick.hook`: the two Omarchy fixes.

## Credits

`guest/base-install-alpine.sh` is adapted from OmacVM's `src/vm/base-install.sh`, `guest/omarchy-install.sh` from its `src/vm/omarchy-install.sh`, and `guest/omarchy-targets.sh` is its `src/guest/omarchy-targets.sh` unchanged. OmacVM is MIT-licensed; its notice is in `THIRD_PARTY_NOTICES.md`. The rest is under `LICENSE`.
