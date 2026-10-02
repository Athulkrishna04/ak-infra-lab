# Runbook: reset a forgotten root password (RHEL 10 family, web01)

This needs console access. In the lab that means the VirtualBox VM window. The same steps are an RHCSA exam task.

> **Rocky/RHEL 10: `rd.break` no longer works for this when root has a password.** Tested 2026-10-02 (INC-009): the dracut emergency shell asks *"Give root password for maintenance (or press Control-D to continue)"*, the very password being reset. Use `init=/bin/bash` (below). Ctrl+D at that prompt simply continues the normal boot.

## Method: `init=/bin/bash` (works on Rocky 10.2)

1. Reboot the VM. At the GRUB menu, select the normal kernel and press **`e`**.
   - Rocky hides the menu after a successful boot (`menu_auto_hide`). To make it show: hold **Shift** or press **Esc** during boot, or beforehand run `sudo grub2-editenv - unset menu_auto_hide` (and `set menu_auto_hide=1` afterwards).
2. Go to the line starting with `linux`, jump to its end with **Ctrl+E**, and append:
   ```
   init=/bin/bash
   ```
3. Press **Ctrl+X** to boot. The kernel starts a root shell (`bash-5.2#`) instead of systemd, with **no login**. The real root filesystem is mounted, read-only.
4. Run:
   ```bash
   mount -o remount,rw /
   passwd root
   touch /.autorelabel          # no SELinux policy is loaded in this shell; relabel on the next boot
   sync; /usr/sbin/reboot -ff   # systemd isn't running, so a normal `reboot` can't work; -ff reboots via the kernel
   ```
5. The system relabels its filesystem and reboots once (a minute or two on this VM). Log in on the console as root with the new password.

**Why `/.autorelabel`?** No SELinux policy is loaded in the `init=/bin/bash` shell, so a rewritten `/etc/shadow` may end up without its proper label (`shadow_t`). If that happens, nothing can read it after boot and every login fails. The relabel makes sure.

**Verify:** you can log in as root on the console, `getenforce` says `Enforcing`, and `ls -Z /etc/shadow` shows `shadow_t`.

## Classic method: `rd.break` (RHEL 8 / older RHEL 9 material)

Append `rd.break` instead, then at `switch_root:/#`: `mount -o remount,rw /sysroot; chroot /sysroot; passwd root; touch /.autorelabel; exit; exit`. Many guides and courses still teach this. On this system it stops at the root-password prompt described above.

## Security note

This works for **anyone with console access**, which is why console/iLO/hypervisor access is as sensitive as root. Protections: a GRUB password (`grub2-setpassword`) blocks editing the boot entry; disk encryption blocks booting another OS against the disk.
