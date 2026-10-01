# Runbook: reset a forgotten root password (RHEL 10 family, web01)

This needs console access. In the lab that means the VirtualBox VM window. The same steps are an RHCSA exam task.

1. Reboot the VM. When the GRUB menu appears, select the normal kernel and press **`e`**. If the menu flashes past, hold **Shift** or press **Esc** during boot.
2. Find the line starting with `linux` and go to its end (**Ctrl+E**). Append:
   ```
   rd.break
   ```
3. Press **Ctrl+X** to boot. You land in the initramfs shell (`switch_root:/#`), before the real root is mounted read-write.
4. Run:
   ```bash
   mount -o remount,rw /sysroot
   chroot /sysroot
   passwd root
   touch /.autorelabel          # passwd rewrote /etc/shadow without an SELinux label; relabel on next boot
   exit
   exit
   ```
5. The system relabels its whole filesystem and reboots once (a minute or two on this VM). Log in on the console as root with the new password.

**Why `/.autorelabel`?** Inside `rd.break`, SELinux policy isn't loaded, so the new `/etc/shadow` gets no label. Without the relabel, nothing can read it after boot and every login fails. The faster alternative, which skips the full relabel: after `passwd`, run `load_policy -i` and `restorecon -v /etc/shadow`, then exit twice.

**Verify:** you can log in as root on the console, `getenforce` says `Enforcing`, and `ls -Z /etc/shadow` shows `shadow_t`.
