# Runbook: locked out of SSH

**Prevention first. Every SSH or firewall change follows this sequence:**
1. Take a VirtualBox snapshot.
2. Keep your current SSH session open.
3. `sudo sshd -t` before any reload.
4. Test from a **second, new** session before closing the first.
5. Add the `mgmt` zone before removing ssh from `public`.

## If it happens anyway

The VirtualBox console is your out-of-band access. It's the lab's equivalent of iLO/iDRAC: *VirtualBox → select the VM → Show* (or double-click it). Log in there as `akadmin` (password) or as `root`.

| Symptom from Windows | Likely cause | Check on the console | Fix |
|---|---|---|---|
| `Connection timed out` | Firewall | `sudo firewall-cmd --get-active-zones`, `--zone=mgmt --list-all` | `sudo firewall-cmd --zone=mgmt --add-service=ssh` (+ `--permanent`) |
| `Connection refused` | sshd not running (a config error stopped it) | `systemctl status sshd` (`ssh` on Ubuntu), `sudo sshd -t` | Fix the file named by `sshd -t`, then `systemctl restart sshd` |
| `Permission denied (publickey)` | Key missing, or wrong permissions or SELinux label on `~/.ssh` | `ls -ldZ ~/.ssh ~/.ssh/authorized_keys`; `journalctl -u sshd -n 20` | `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; restorecon -Rv ~/.ssh` |
| `Permission denied` for one user only | Not in `AllowGroups`, or the account has expired | `id <user>`; `sudo chage -l <user>` | `usermod -aG ops <user>`; `chage -E -1 <user>` |
| Host key warning | VM rebuilt or reverted | Compare fingerprints on the console: `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` | On Windows: `ssh-keygen -R <host>` |

If nothing works within 15 minutes, revert to the last snapshot and redo the change in smaller steps.
