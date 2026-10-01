# Build guide: ak-infra-lab, step by step

This is the "how" of the project. Every step says **why** you're doing it, gives the **commands**, and shows the **expected** result and the **evidence** to keep. Work top to bottom. Don't start a milestone until the previous gate has passed.

## How to read this guide

| Marker | Meaning |
|---|---|
| `PS>` | Windows PowerShell or Windows Terminal on the laptop |
| `mon01$` / `web01$` | A shell on that VM, logged in as `akadmin` over SSH, unless the step says "VM console" |
| **Expected** | What you should see. If you see something else, stop and work out why before going on |
| 📸 **Evidence** | Save it: a screenshot in `docs/screenshots/` named `<step>-<what>.png`, or the text output pasted into `tests/test-plan.md` or the incident report |
| 🚦 **Gate** | Pass/fail checkpoint. It must pass before you continue |

**Golden rules** (these are also good interview answers):
1. **Snapshot before anything risky** (SSH, firewall, fstab, patching).
2. **Keep a second SSH session open** while changing SSH, sudo or the firewall.
3. **Never `setenforce 0` as a fix.** SELinux problems get a real fix (context, boolean, port label).
4. **`sudo mount -a && sudo findmnt --verify` after every fstab edit**, before any reboot.
5. **Validate before you apply:** `visudo -c`, `sshd -t`, `nginx -t`, `rsyslogd -N1`.
6. **Record real output.** Never type up what the output "should" say.
7. **15-minute rule:** stuck for 15 minutes after a change? Roll back to the last good state, then retry in smaller steps.

**The repo lives on Windows** (`D:\…\Project 2`) and is the source of truth. You edit files there, copy them to the VMs with `tools\sync-to-lab.ps1` (they land in `~/ak-infra-lab/`), and install them from that copy.

### Time budget (at ~2 h per evening)

| Milestone | Effort | Gate |
|---|---|---|
| M0 Host & VMs | 3–4 h | G0: both VMs reachable by SSH key from Windows, snapshot `clean-install` |
| M1 Baseline admin | 3–4 h | G1: T01–T03, T06, T16, T18, T19 |
| M2 Storage + service | 2–3 h | G2: T04, T05, T07, T08, T17, reboot test, INC-001 written |
| M3 Monitoring + backup | 4–5 h | G3: T09–T12b, T15 |
| M4 Document & publish v1.0 | 2–3 h | G4: `verify.sh` 0 FAIL, repo pushed, tag `v1.0` |
| **MVP total** | **~14–19 h** | about two weeks of evenings |
| E1 Hardening + central logs | 3–4 h | T13, T14, T20 |
| E2 Patching + 8 incidents | 6–8 h | 2 change records, 8 incident reports |
| E3 Ansible | 6–8 h | fresh VM converges; second run `changed=0` |
| E4 / E5 | optional | see the end of this guide |

---

## M0: Host and VMs

### M0.1 Check the laptop (read-only)

**Why:** this laptop has 7.7 GB RAM, only ~18 GB free on C:, and a Windows hypervisor that's running. All three change how you set up VirtualBox.

```powershell
PS> cd "D:\AA_Projects For new resume\Claude complete portofolio\Networking projects\Project 2"
PS> powershell -ExecutionPolicy Bypass -File tools\preflight.ps1
```

**Expected (today):** PASS for RAM (8 GB layout) and D: space. WARN for the running hypervisor, Memory Integrity, and VirtualBox not installed. Re-run this script after every M0 step. Your goal is no WARN lines except the ones you've chosen to accept.

### M0.2 Give VirtualBox the CPU's virtualization (your decision)

**Why:** WSL2 and **Memory Integrity** keep the Windows hypervisor running. VirtualBox then has to run on top of it through the Hyper-V API. It's slow (the green turtle icon) and may hide AVX2, which Rocky Linux 10 needs (x86-64-v3). See [ADR-004](decisions/ADR-004-host-hypervisor-off.md).

**Trade-off:** while the hypervisor is off, Memory Integrity isn't protecting Windows, and WSL2/Docker won't start. It's only for lab days and it can be switched back.

Lab-day setup:
1. `PS> wsl --shutdown`
2. *Windows Security → Device security → Core isolation details →* **Memory integrity: Off**. Windows asks you to restart; restart later, after step 3.
3. Open **Terminal (Admin)** and run:
   ```powershell
   PS> bcdedit /set hypervisorlaunchtype off
   ```
4. Restart Windows, then re-run `tools\preflight.ps1`.

**Expected:** `PASS Windows hypervisor is off`.

Back to normal (for WSL2 or Docker days): run `bcdedit /set hypervisorlaunchtype auto` in an admin terminal, turn Memory integrity back **On**, and restart.

> **If you'd rather not switch it off:** skip this step. VirtualBox runs in NEM mode (slower). In M0.7 you'll find out whether AVX2 reached the VM. If it didn't, use the AlmaLinux 10 **x86_64_v2** ISO for web01 instead of Rocky 10, and write that down in [ADR-001](decisions/ADR-001-rocky-first-fleet.md).

### M0.3 Install VirtualBox 7.2.x

1. Download the **Windows hosts** installer for the latest **7.2.x** from virtualbox.org (the 7.1 branch is no longer supported).
2. Run it and accept the defaults. It may ask for the Microsoft Visual C++ redistributable; install it. The network may drop for a few seconds while the host-only adapter is created.
3. Skip the Extension Pack, which isn't needed.

**Expected:** `tools\preflight.ps1` shows `PASS VirtualBox 7.2.x installed` and `FAIL Default machine folder…`. That FAIL is next.

### M0.4 Machine folder on D:, and the two networks

**Why:** C: has only ~18 GB free. Two VMs with snapshots can easily use 30–40 GB.

1. **Machine folder:** *File → Preferences → General → Default Machine Folder* → `D:\VirtualBox VMs`. Or:
   ```powershell
   PS> & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" setproperty machinefolder "D:\VirtualBox VMs"
   ```
2. **NAT Network `labnet`** (adapter 1: internet for dnf/apt): *File → Tools → Network Manager → NAT Networks → Create*. Set name `labnet`, IPv4 prefix `10.0.10.0/24`, **Enable DHCP** ticked, then *Apply*. Or:
   ```powershell
   PS> & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork add --netname labnet --network "10.0.10.0/24" --enable --dhcp on
   ```
3. **Host-only network** (adapter 2: management): *Network Manager → Host-only Networks*. The installer already created *VirtualBox Host-Only Ethernet Adapter* with `192.168.56.1/24`. Select it, open the **DHCP Server** tab, **untick Enable Server**, then *Apply*. The VMs get static IPs on this network. Or:
   ```powershell
   PS> & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" dhcpserver modify --network "HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter" --disable
   ```

> **VirtualBox 7.2 note:** the *File → Tools* menu no longer lists a Network Manager. The `VBoxManage` commands above do the same job. Check the result with `VBoxManage natnetwork list` and `VBoxManage list dhcpservers`: labnet should be enabled with DHCP, and the host-only DHCP server should show `Enabled: No`.

**Expected:** preflight shows `PASS Default machine folder: D:\VirtualBox VMs`, `PASS NAT network 'labnet' exists` and `PASS Host-only adapter has 192.168.56.1`.
📸 **Evidence:** `M0-networks.png`, a screenshot of both Network Manager tabs.

### M0.5 Download and verify the ISOs

```powershell
PS> New-Item -ItemType Directory -Force D:\ISO
```
`D:\ISO` already holds `ubuntu-26.04-desktop-amd64.iso` and a Kali ISO. **Neither is used here.** This lab needs the **24.04 live *server*** ISO (no desktop; the Zabbix 7.0 packages target 24.04) and Rocky 10 Minimal.

| ISO | Where | Checksum file |
|---|---|---|
| Ubuntu Server **24.04.x LTS** (amd64, live server) | ubuntu.com/download/server | `SHA256SUMS` on releases.ubuntu.com/24.04/ |
| Rocky Linux **10.x Minimal** (x86_64) | rockylinux.org/download | `CHECKSUM` next to the ISO |

Verify each ISO before you use it:

```powershell
PS> Get-FileHash D:\ISO\ubuntu-24.04*-live-server-amd64.iso -Algorithm SHA256
PS> Get-FileHash D:\ISO\Rocky-10*-x86_64-minimal.iso -Algorithm SHA256
```

**Expected:** each hash is identical to the one in the checksum file. A mismatch means a corrupt download, so download it again.

### M0.6 Create mon01 and install Ubuntu Server 24.04

**Create the VM:** *Machine → New*.
- Name `mon01`, folder `D:\VirtualBox VMs`, ISO = the Ubuntu ISO, OS Linux / Ubuntu (64-bit).
- **Tick "Skip Unattended Installation".** You want the real installer, and the unattended one creates its own user with a default password.
- Hardware: **2048 MB**, **2 CPUs**. Disk: **25 GB**, VDI, dynamically allocated.

**Before the first boot:** *Settings*:
- *Network → Adapter 1*: **NAT Network**, name `labnet`.
- *Adapter 2*: tick Enable, **Host-only Adapter**, *VirtualBox Host-Only Ethernet Adapter*.
- *Audio*: untick. *USB*: untick.
- *System → Processor*: 2 CPUs. *Display*: VMSVGA, 16 MB is plenty.

**Install** (keyboard only):
1. Language English, keep the keyboard. "Installer update available": *Continue without updating*.
2. Type of install: **Ubuntu Server** (not minimized).
3. **Network:** `enp0s3` gets a 10.0.10.x address by DHCP. Select `enp0s8` → *Edit IPv4* → **Manual**:
   - Subnet `192.168.56.0/24`
   - Address `192.168.56.10`
   - Gateway **empty**, name servers **empty**
4. Proxy empty, mirror default.
5. Storage: *Use an entire disk*, **Set up this disk as an LVM group** ticked (default). Accept the summary.
6. Profile: your name, server name **`mon01`**, username **`akadmin`**, and a strong password you'll remember.
7. Ubuntu Pro: *Skip*. SSH: **tick Install OpenSSH server**, don't import keys. Featured snaps: **none**.
8. When it finishes: *Reboot Now*. If it asks you to remove the installation medium, press Enter.

**Check VirtualBox is using VT-x:** look at the VM window's status bar. A **green turtle** means NEM (Hyper-V) mode. You can also check *Machine → Show Log…* and search for `NEM`: with the hypervisor off you should find **no** "NEM" lines, and you should find `HM: HMR3Init: … VT-x`.

### M0.7 The x86-64-v3 check (decides Rocky vs Alma)

Log in on the mon01 console and run:

```bash
mon01$ /lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v
```

**Expected:** `x86-64-v3 (supported, searched)`. Carry on with Rocky 10.
If v3 **isn't** "supported", the hypervisor is probably still on. Recheck M0.2. If you chose to keep it on, use AlmaLinux 10 x86_64_v2 for web01 and record the decision in ADR-001.
📸 **Evidence:** paste the output line into ADR-001.

### M0.8 Create web01 and install Rocky Linux 10 Minimal

**Create the VM:**
- Name `web01`, ISO = the Rocky ISO, OS Linux / **Red Hat (64-bit)**. **Tick Skip Unattended Installation.**
- **2048 MB** for the installer (cut to 1.5 GB afterwards), **1 CPU**, **20 GB** disk.
- Same *Network* settings as mon01 (adapter 1 `labnet`, adapter 2 host-only). Audio and USB off.
- **Don't add the data disk yet.** The installer might grab it; it comes in M2.

**Install (Anaconda):**
1. Language English → *Continue*.
2. **Installation Destination:** select the 20 GB disk, *Automatic* → *Done*. It creates LVM `rl-root` and `rl-swap` on XFS.
3. **Software Selection:** **Minimal Install**.
4. **Network & Host Name:**
   - Host name **`web01.lab.local`** → *Apply*.
   - `enp0s3`: switch **ON** (DHCP).
   - `enp0s8` → *Configure → IPv4 Settings*: Method **Manual**, Add `192.168.56.11`, netmask `24`, gateway **empty** → *Save*, then switch it **ON**.
5. **Root Account:** enable it and set a strong root password. **Don't** tick "Allow root SSH login with password". Root on the *console* is needed for emergency mode (INC-008), while SSH root stays blocked.
6. **User Creation:** `akadmin`, **tick "Add administrative privileges"** (adds wheel), and a password.
7. **Time & Date:** Asia/Kolkata, network time on.
8. *Begin Installation* → *Reboot System*.

**If the graphical installer shows a black screen:** at the ISO boot menu press **Tab** (BIOS) or **e** (UEFI), add ` inst.text` to the kernel line, and boot. The text installer has the same choices.
**If the installer kernel panics early** with a "CPU not supported" or x86-64-v3 message: go back to M0.7.

**After the install:** `sudo poweroff`, set *Settings → System → Base Memory* to **1536 MB**, then start it again.

### M0.9 Check the addressing (both VMs)

If you didn't set the static IP in an installer, set it now.

**web01 (NetworkManager):**
```bash
web01$ nmcli -t -f NAME,DEVICE con show
web01$ sudo nmcli con mod enp0s8 ipv4.method manual ipv4.addresses 192.168.56.11/24 \
         ipv4.gateway "" ipv4.never-default yes ipv6.method disabled connection.autoconnect yes
web01$ sudo nmcli con up enp0s8
```
If there's no connection named `enp0s8` (e.g. it's called *Wired connection 1*), use that name, or create one: `sudo nmcli con add type ethernet ifname enp0s8 con-name enp0s8 ipv4.method manual ipv4.addresses 192.168.56.11/24 ipv4.never-default yes ipv6.method disabled`.

**mon01 (netplan):** `cat /etc/netplan/*.yaml`. If `enp0s8` with `192.168.56.10/24` isn't there, create [configs/mon01/netplan/60-hostonly.yaml](../configs/mon01/netplan/60-hostonly.yaml) by hand, then:
```bash
mon01$ sudo chmod 600 /etc/netplan/60-hostonly.yaml && sudo netplan try
```
`netplan try` reverts after 120 s unless you press Enter, which makes it safe to test.

**Names and hostnames (both VMs):**
```bash
web01$ sudo hostnamectl set-hostname web01.lab.local        # mon01: mon01.lab.local
web01$ sudo tee -a /etc/hosts <<'EOF'
192.168.56.10   mon01.lab.local   mon01
192.168.56.11   web01.lab.local   web01
EOF
```

**Check:**
```bash
web01$ ip -br addr                   # enp0s3 10.0.10.x/24, enp0s8 192.168.56.11/24
web01$ ip route                      # ONE default route: "default via 10.0.10.1 dev enp0s3"
web01$ ping -c2 mon01 && ping -c2 1.1.1.1 && ping -c2 rockylinux.org
```
**Expected:** all pings answer and there's exactly one default route.

> Pinging the Windows host (192.168.56.1) from a VM may fail. The Windows firewall drops inbound ping, which is normal. What matters is Windows → VM and VM ↔ VM.

### M0.10 SSH from Windows with a key

**You already have a key** (`C:\Users\ATHUL KRISHNA\.ssh\id_ed25519`, found by preflight on 2026-09-29). Reuse it. **Don't run `ssh-keygen` with the default path**: answering "y" to "Overwrite?" destroys the key you use elsewhere, such as GitHub. Only if `id_ed25519.pub` doesn't exist:
```powershell
PS> ssh-keygen -t ed25519 -C "athul@laptop"                     # Enter = default path; set a passphrase
```
You don't have a `~/.ssh/config` yet, so copy the example in:
```powershell
PS> Copy-Item configs\windows\ssh_config.example "$env:USERPROFILE\.ssh\config"   # if a config file exists by then, append the two Host blocks instead
PS> ssh mon01                                                   # first time: type "yes" for the fingerprint, then your password
```

Windows has no `ssh-copy-id`, so copy the public key with `scp` and append it:

```powershell
PS> scp "$env:USERPROFILE\.ssh\id_ed25519.pub" mon01:/tmp/win.pub
PS> ssh mon01 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat /tmp/win.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm /tmp/win.pub"
PS> scp "$env:USERPROFILE\.ssh\id_ed25519.pub" web01:/tmp/win.pub
PS> ssh web01 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat /tmp/win.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && restorecon -R ~/.ssh && rm /tmp/win.pub"
PS> ssh web01 hostname; ssh mon01 hostname
```
**Expected:** the last line prints both hostnames **without asking for a password** (at most your key's passphrase).
`restorecon` on web01 makes sure `~/.ssh` has the `ssh_home_t` SELinux label, or sshd isn't allowed to read it.

### M0.11 Headless running and snapshots

From now on, start VMs with *Start ▸ Headless Start* (no window, less RAM) and work from Windows Terminal. The console window is only for emergencies (*Show*).

Shut both VMs down cleanly (`sudo poweroff`), then take a snapshot of each: *VM → Snapshots → Take* → **`clean-install`**.

### M0.12 Put the project under Git

```powershell
PS> cd "D:\AA_Projects For new resume\Claude complete portofolio\Networking projects\Project 2"
PS> git init -b main
PS> git add .
PS> git status                        # _working/ must NOT be listed (it's gitignored)
PS> git commit -m "Scaffold: plan, build guide, configs, scripts, tests"
```
Create an **empty private** repo `ak-infra-lab` on github.com (no README), then:
```powershell
PS> git remote add origin https://github.com/Athulkrishna04/ak-infra-lab.git
PS> git push -u origin main
```
Commit at every gate from now on.

### 🚦 Gate G0
- [ ] `tools\preflight.ps1`: hypervisor off (or your fallback recorded), VirtualBox 7.2, machine folder on D:
- [ ] `ssh mon01` and `ssh web01` from Windows log in with the key
- [ ] Each VM has exactly one default route (via labnet) and reaches the internet
- [ ] Snapshots `clean-install` exist on both VMs
- [ ] The repo is on GitHub (private for now)

---

## M1: Baseline administration

### M1.1 Copy the repo to both VMs

```powershell
PS> powershell -ExecutionPolicy Bypass -File tools\sync-to-lab.ps1
```
**Expected:** each folder is listed under `== mon01 ==` and `== web01 ==`. On the VMs: `ls ~/ak-infra-lab`. Re-run the sync whenever you change a file on Windows.

### M1.2 Update and install the base tools

```bash
web01$ sudo dnf -y upgrade
web01$ sudo dnf -y install vim-enhanced bash-completion policycoreutils-python-utils setroubleshoot-server \
         sysstat rsync tar chrony lsof dnf-plugins-core
web01$ sudo dnf needs-restarting -r || sudo systemctl reboot

mon01$ sudo apt update && sudo apt -y full-upgrade
mon01$ sudo apt -y install chrony vim bash-completion rsync sysstat lsof     # chrony replaces systemd-timesyncd
mon01$ [ -f /var/run/reboot-required ] && sudo systemctl reboot
```

### M1.3 Time zone and time sync (T18)

**Why:** logs, backups, cron and Zabbix graphs all depend on correct time.

```bash
web01$ sudo timedatectl set-timezone Asia/Kolkata
web01$ sudo systemctl enable --now chronyd                  # on mon01 the unit is "chrony"
web01$ chronyc sources -v
web01$ chronyc tracking | grep -E 'Reference|Leap'
web01$ timedatectl
```
**Expected:** `Leap status : Normal` and `System clock synchronized: yes` on both VMs.

### M1.4 Groups and users

**Why:** role-based access. Admins are in `ops`, developers in `devs`, and nobody shares an account.

```bash
# both VMs
$ sudo groupadd ops
$ sudo groupadd devs
$ sudo usermod -aG ops akadmin

# web01 only: the developer
web01$ sudo useradd -m -s /bin/bash -G devs akdev
web01$ sudo passwd akdev
web01$ sudo chage -M 90 -W 7 akdev              # password must change every 90 days, 7 days' warning
web01$ sudo chage -l akdev
```
Log out and back in, then run `id`. **Expected:** `ops` appears in akadmin's groups.

### M1.5 sudo policy (T03, T19)

**Why:** admins get full sudo **with** a password, and developers get exactly two jobs. The drop-in file is checked **before** it's installed, because a broken sudoers file can lock everyone out of root.

```bash
web01$ cd ~/ak-infra-lab
web01$ sudo visudo -cf configs/web01/sudoers.d/ak                      # "parsed OK"
web01$ sudo install -m 0440 -o root -g root configs/web01/sudoers.d/ak /etc/sudoers.d/ak
web01$ sudo visudo -c                                                  # whole config still OK
```
Do the same on mon01 (the `%devs` line is harmless there).

**Test in a second session before changing anything else:**
```powershell
PS> ssh web01
```
```bash
web01$ sudo -k; sudo -v && echo "sudo via ops works"
```
Now take akadmin out of the distro admin group, so `ops` is the only route to root and matches the design:
```bash
web01$ sudo gpasswd -d akadmin wheel          # on mon01: sudo gpasswd -d akadmin sudo
```
Open **another new** session and run `sudo -v` again. It must still work, because `%ops` grants it now.

```bash
web01$ sudo -l -U akdev                                   # T03
web01$ sudo -l -U akdev /usr/bin/systemctl stop nginx; echo "exit=$?"     # T19: exit=1
```
**Expected:** T03 lists only `systemctl restart nginx` and the two `journalctl -u nginx … --no-pager` lines. T19 prints `exit=1`.

> **Interview point:** why is `--no-pager` pinned? `journalctl` normally opens `less`, and `less` can run a shell with `!sh`. Run as root through sudo, that would be a root shell. Modern systemd starts the pager in "secure mode" under sudo (`SYSTEMD_PAGERSECURE`), but the sudoers rule shouldn't depend on that. Exact arguments and no wildcards: a `*` in sudoers also matches any extra arguments.

### M1.6 Keys first, then hardening

**Why:** once password authentication is off, every account needs a key already in place.

**a) akdev's key** (a separate identity on Windows):
```powershell
PS> ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\akdev_ed25519" -C "akdev"
PS> scp "$env:USERPROFILE\.ssh\akdev_ed25519.pub" web01:/tmp/akdev.pub
```
```bash
web01$ sudo install -d -m 700 -o akdev -g akdev /home/akdev/.ssh
web01$ sudo install -m 600 -o akdev -g akdev /tmp/akdev.pub /home/akdev/.ssh/authorized_keys
web01$ sudo restorecon -Rv /home/akdev/.ssh && rm /tmp/akdev.pub
```
```powershell
PS> ssh -i "$env:USERPROFILE\.ssh\akdev_ed25519" akdev@192.168.56.11 id      # logs in, prints uid/gid
```

**b) mon01 → web01** (needed by `verify.sh` and, in E3, Ansible):
```bash
mon01$ ssh-keygen -t ed25519 -N '' -C "akadmin@mon01"
mon01$ ssh-copy-id akadmin@web01                  # passwords still work at this point
mon01$ ssh web01 hostname                         # no password prompt
```
The mon01 key has no passphrase so scripts can use it. That's acceptable in a lab. In production you'd use ssh-agent or a dedicated, restricted automation key.

### M1.7 SSH hardening (T01, T02)

**Snapshot first** (`pre-patch-latest` on both VMs), and **keep your current session open** the whole time.

```bash
web01$ ls /etc/ssh/sshd_config.d/
```
If you see **`01-permitrootlogin.conf`**, the installer wrote `PermitRootLogin yes`. Because `01-` is read before our `10-`, it would win. Remove it: `sudo rm /etc/ssh/sshd_config.d/01-permitrootlogin.conf`.

```bash
web01$ sudo install -m 0644 ~/ak-infra-lab/configs/common/sshd_config.d/10-hardening.conf /etc/ssh/sshd_config.d/
web01$ sudo sshd -t && echo "syntax OK"
web01$ sudo systemctl reload sshd                 # mon01: sudo systemctl reload ssh
web01$ sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|gssapiauthentication|allowgroups|maxauthtries) '
```
**Expected** (the effective values):
```
permitrootlogin no
passwordauthentication no
kbdinteractiveauthentication no
gssapiauthentication no
allowgroups ops
allowgroups devs
allowgroups akbackup
maxauthtries 3
```
`sshd -T` may print the groups on one line or several. What matters is that all three are there. On Ubuntu, `50-cloud-init.conf` may say `PasswordAuthentication yes`. Our `10-` file is read first, so `sshd -T` must still show `no`.

**Test from a NEW Windows session** (keep the old one open):
```powershell
PS> ssh web01 hostname                                        # works (key)
PS> ssh root@192.168.56.11                                    # T01
PS> ssh -o PubkeyAuthentication=no akadmin@192.168.56.11      # T02
```
**Expected:** T01 and T02 both end with `Permission denied (publickey).`
📸 **Evidence:** paste both lines into the test plan. Repeat the whole step on mon01.

### M1.8 firewalld zones on web01 (T06, T16)

**Why:** a management zone for admin traffic and a public zone that serves only the website. firewalld picks the zone by **source address first**. Every lab client (Windows, mon01) is in 192.168.56.0/24, so `mgmt` must allow ssh, http and the Zabbix port. The public zone is what the labnet side (10.0.10.x) sees.

Work through [configs/web01/firewalld.sh](../configs/web01/firewalld.sh) **one block at a time** and read the comments. Don't run it as a script.

```bash
web01$ sudo firewall-cmd --get-active-zones
web01$ sudo firewall-cmd --zone=mgmt --list-all
web01$ sudo firewall-cmd --zone=public --list-services      # T06: http
```
**Expected:** `mgmt` is active with source `192.168.56.0/24` and services `http ssh`, port `10050/tcp`. `public` lists `http` only.

**T16 (negative): SSH from the public side must fail.** Find web01's labnet address, then try it from mon01:
```bash
web01$ ip -4 -br addr show enp0s3                             # e.g. 10.0.10.5/24
mon01$ timeout 5 bash -c 'exec 3<>/dev/tcp/10.0.10.5/22' && echo OPEN || echo "CLOSED (good)"
```
📸 **Evidence:** the `--list-all` output for both zones, pasted into the test plan.

### M1.9 ufw on mon01

Work through [configs/mon01/ufw.sh](../configs/mon01/ufw.sh) line by line. SSH is allowed **before** `ufw enable`.
```bash
mon01$ sudo ufw status verbose
```
**Expected:** `Status: active`, default deny incoming, and 22/80/10051/20514 allowed from 192.168.56.0/24. `ssh mon01` from a new Windows session still works.

### M1.10 Snapshot and commit

Power off both VMs, take snapshot **`baseline-M1`**, and delete the temporary `pre-patch-latest`.
```powershell
PS> git add -A; git commit -m "M1: users, sudo, SSH keys + hardening, firewalld/ufw, chrony"
```

### 🚦 Gate G1
- [ ] T01, T02: `Permission denied (publickey)` on both VMs
- [ ] T03, T19: sudo scope correct; `sudo -v` works through `ops` only
- [ ] T06, T16: public zone = http, SSH closed from labnet
- [ ] T18: chrony synchronised on both
- [ ] Snapshot `baseline-M1`, commit pushed

---

## M2: Storage and the service (web01)

### M2.1 Add the data disk

`sudo poweroff` web01. Then *Settings → Storage → Controller: SATA →* **Adds hard disk** (the disk icon with +) → *Create* → VDI, dynamic, **5 GB**, name `web01-data1`, in `D:\VirtualBox VMs\web01\` → *Choose*. Boot it.

```bash
web01$ lsblk
```
**Expected:** a new 5 G disk `sdb` with no partitions.

### M2.2 LVM → XFS → fstab by UUID (T07)

**Why:** LVM lets the volume grow later without downtime. The fstab entry uses the UUID, because `sdX` names can change when disks are added.

```bash
web01$ sudo pvcreate /dev/sdb
web01$ sudo vgcreate vg_data /dev/sdb
web01$ sudo lvcreate -n lv_app -L 3G vg_data
web01$ sudo mkfs.xfs /dev/vg_data/lv_app
web01$ sudo mkdir -p /srv/app
web01$ echo "UUID=$(sudo blkid -s UUID -o value /dev/vg_data/lv_app) /srv/app xfs defaults 0 0" | sudo tee -a /etc/fstab
web01$ sudo systemctl daemon-reload
web01$ sudo mount -a && sudo findmnt --verify
web01$ findmnt /srv/app; sudo pvs; sudo vgs; sudo lvs
```
**Expected:** `mount -a` prints nothing, `findmnt --verify` reports `0 parse errors, 0 errors`, and `/srv/app` is mounted from `/dev/mapper/vg_data-lv_app` as xfs.
📸 **Evidence:** the `pvs`/`vgs`/`lvs` and `findmnt` output (text).

### M2.3 App user, content and a developer ACL

```bash
web01$ sudo useradd -r -s /sbin/nologin akapp
web01$ sudo mkdir -p /srv/app/public
web01$ echo "ak-app OK" | sudo tee /srv/app/public/index.html
web01$ sudo setfacl -m g:devs:rwx /srv/app/public            # devs can deploy content
web01$ sudo setfacl -d -m g:devs:rwx /srv/app/public         # ...and new files inherit it (default ACL)
web01$ getfacl /srv/app/public
```
**Expected:** `group:devs:rwx` and `default:group:devs:rwx` are listed. In `ls -ld /srv/app/public`, the `+` after the mode bits means an ACL is present.

### M2.4 ak-app as a limited systemd service (T08)

```bash
web01$ sudo install -m 0644 ~/ak-infra-lab/systemd/ak-app.service /etc/systemd/system/
web01$ sudo systemctl daemon-reload
web01$ sudo systemctl enable --now ak-app
web01$ systemctl status ak-app --no-pager
web01$ curl -s http://127.0.0.1:8080/                                       # ak-app OK
web01$ systemctl show ak-app -p MemoryMax -p CPUQuotaPerSecUSec -p TasksMax   # T08
web01$ cat /sys/fs/cgroup/system.slice/ak-app.service/memory.max              # 134217728
web01$ cat /sys/fs/cgroup/system.slice/ak-app.service/cpu.max                 # 25000 100000
web01$ systemd-analyze security ak-app --no-pager | tail -1
```
**Expected:** active (running), `MemoryMax=134217728`, `CPUQuotaPerSecUSec=250ms`, `TasksMax=50`.
**Why the `/sys/fs/cgroup` files matter:** systemd's settings are just a friendly layer over cgroup v2 files in the kernel. `cpu.max` = 25 ms of CPU per 100 ms, which is 25%.
📸 **Evidence:** the `systemd-analyze security` overall exposure line. Optionally, comment the sandboxing lines out, check the score again, and put them back, to get a before/after number.

### M2.5 nginx and the static site

```bash
web01$ sudo dnf -y install nginx
web01$ sudo mkdir -p /srv/www && echo "web01 up" | sudo tee /srv/www/index.html
web01$ ls -Zd /srv/www                                               # var_t: nginx may NOT read this
web01$ sudo semanage fcontext -a -t httpd_sys_content_t "/srv/www(/.*)?"
web01$ sudo restorecon -Rv /srv/www
web01$ ls -Z /srv/www                                                # httpd_sys_content_t
web01$ sudo install -m 0644 ~/ak-infra-lab/configs/web01/nginx/conf.d/app.conf /etc/nginx/conf.d/
web01$ sudo nginx -t && sudo systemctl enable --now nginx
web01$ curl -s http://127.0.0.1/                                     # web01 up
```
**Why `semanage fcontext` *and* `restorecon`:** `semanage` writes the rule into the policy, so it survives relabels. `restorecon` applies it to the files that exist now. `chcon` alone would be undone by the next relabel.

### M2.6 The 502, a real incident (INC-001)

```bash
web01$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/app/
```
**Expected:** most likely `502`. **Stop here.** Copy [incidents/TEMPLATE.md](incidents/TEMPLATE.md) to `docs/incidents/INC-001-nginx-502-selinux.md` and write the **Symptom** section now, before you diagnose anything.

Then diagnose, pasting real output into the report as you go:
```bash
web01$ systemctl is-active ak-app; curl -s http://127.0.0.1:8080/        # the backend itself is fine
web01$ sudo tail -n 5 /var/log/nginx/error.log                            # "connect() ... failed (13: Permission denied)"
web01$ getenforce
web01$ sudo ausearch -m AVC -ts recent -i
web01$ sudo ausearch -m AVC -ts recent | audit2why
web01$ sudo semanage port -l | grep -w 8080
web01$ getsebool -a | grep httpd_can_network
```
Read the denial: `httpd_t` (nginx) was denied `name_connect` to a port labelled `http_cache_port_t` (8080). `audit2why` names the boolean(s) that allow it. **Prefer the narrowest one it lists:** `httpd_can_network_relay` if it's offered, otherwise `httpd_can_network_connect`. Record which one it suggested.

```bash
web01$ sudo setsebool -P httpd_can_network_relay on        # or the boolean audit2why named; -P = persistent
web01$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/app/     # 200
web01$ getenforce                                                        # still Enforcing
```
Finish the report: root cause, fix, verification and prevention.

> **Interview gold:** "nginx returned 502 while the backend was healthy. The nginx error log showed permission denied on the upstream connect, and `ausearch`/`audit2why` showed SELinux blocking `httpd_t` from connecting to port 8080. I set the narrowest boolean persistently instead of disabling SELinux."

### M2.7 Test from outside (T05, T17)

```bash
mon01$ curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: web01.lab.local' http://192.168.56.11/        # 200
mon01$ curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: web01.lab.local' http://192.168.56.11/app/    # 200 (T05)
mon01$ curl -s -o /dev/null -w '%{http_code}\n' http://10.0.10.5/            # web01's labnet IP: 200 (T17)
```
Also open `http://192.168.56.11/` and `http://192.168.56.11/app/` in the Windows browser.
📸 **Evidence:** `M2-browser-app.png`.

### M2.8 Grow the volume while it serves traffic

**Why:** "extend LVM online" is a classic interview question. Doing it while a request loop runs proves there was no downtime.

1. `sudo poweroff` web01. Add a second disk as in M2.1: **2 GB**, `web01-data2`. Boot it.
2. On **mon01**, start a request loop and leave it running:
   ```bash
   mon01$ while true; do printf '%s ' "$(curl -s -o /dev/null -w '%{http_code}' http://192.168.56.11/app/)"; sleep 1; done
   ```
3. On **web01**, grow the volume live:
   ```bash
   web01$ lsblk                                           # new 2 G disk: sdc
   web01$ df -h /srv/app                                  # before: ~3.0G
   web01$ sudo pvcreate /dev/sdc
   web01$ sudo vgextend vg_data /dev/sdc
   web01$ sudo lvextend -r -L +2G /dev/vg_data/lv_app      # -r also grows XFS (xfs_growfs) while mounted
   web01$ df -h /srv/app                                  # after: ~5.0G
   web01$ sudo vgs; sudo lvs
   ```
4. Stop the loop with Ctrl+C.

**Expected:** the loop printed only `200`s, and `df` shows about 5.0G.
📸 **Evidence:** the before/after `df -h` and `lvs` output, plus the loop output.
**Remember:** XFS can grow but **cannot shrink**. ext4 can shrink, but only while unmounted.

### M2.9 Reboot test

```bash
web01$ sudo systemctl reboot
# a minute later:
web01$ findmnt /srv/app; systemctl is-active nginx ak-app; getenforce
mon01$ curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11/app/
```
**Expected:** everything comes back with no manual step (T07), and the app returns 200.
```powershell
PS> git add -A; git commit -m "M2: LVM + online extend, ak-app with cgroup limits, nginx + SELinux, INC-001"
```

### 🚦 Gate G2
- [ ] T04 Enforcing · T05 200/200 · T07 mount after reboot · T08 limits · T17 public http 200
- [ ] Online extend evidence saved (only `200`s during `lvextend -r`)
- [ ] INC-001 written from real output

---

## M3: Monitoring and backup

### M3.1 (mon01) Room for backups

The Ubuntu installer usually leaves half the volume group empty.
```bash
mon01$ sudo vgs                                        # VFree?
```
If there are **6 GB or more free**, give backups their own ext4 volume (it's also a nice XFS vs ext4 contrast):
```bash
mon01$ sudo lvcreate -n lv_backups -L 5G ubuntu-vg
mon01$ sudo mkfs.ext4 /dev/ubuntu-vg/lv_backups
mon01$ sudo mkdir -p /srv/backups
mon01$ echo "UUID=$(sudo blkid -s UUID -o value /dev/ubuntu-vg/lv_backups) /srv/backups ext4 defaults 0 2" | sudo tee -a /etc/fstab
mon01$ sudo systemctl daemon-reload && sudo mount -a && sudo findmnt --verify
mon01$ sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv      # give the rest to / (Zabbix DB grows)
mon01$ df -h / /srv/backups
```
Otherwise just `sudo mkdir -p /srv/backups`.

### M3.2 (mon01) Install Zabbix 7.0 LTS

**Why 7.0:** see [ADR-002](decisions/ADR-002-zabbix-7.0-lts.md).

1. In the Windows browser, open **zabbix.com/download** and select **Zabbix 7.0 LTS → Ubuntu → 24.04 (Noble) → Server, Frontend, Agent 2 → MySQL → Nginx**. **Use the commands that page shows.** They're authoritative. The shape is:
   ```bash
   mon01$ wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
   mon01$ sudo dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
   mon01$ sudo apt update
   mon01$ sudo apt -y install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 zabbix-get
   mon01$ sudo apt -y install mariadb-server
   ```
2. **Tune MariaDB for 2 GB** before loading data:
   ```bash
   mon01$ sudo install -m 0644 ~/ak-infra-lab/configs/mon01/mariadb/90-ak.cnf /etc/mysql/mariadb.conf.d/
   mon01$ sudo systemctl restart mariadb
   ```
3. **Create the database.** Pick a strong password and keep it in your password manager, **never in the repo**:
   ```bash
   mon01$ sudo mysql
   ```
   ```sql
   create database zabbix character set utf8mb4 collate utf8mb4_bin;
   create user zabbix@localhost identified by '<ZBX_DB_PASSWORD>';
   grant all privileges on zabbix.* to zabbix@localhost;
   set global log_bin_trust_function_creators = 1;
   quit;
   ```
4. **Import the schema**, using the path the download page shows. It takes a few minutes and asks for the DB password:
   ```bash
   mon01$ zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p zabbix
   mon01$ sudo mysql -e "set global log_bin_trust_function_creators = 0;"
   ```
5. **Configure the server:** `sudoedit /etc/zabbix/zabbix_server.conf` and set `DBPassword=<ZBX_DB_PASSWORD>`. `sudoedit` keeps the password out of your shell history.
6. **Web front end on port 80:** `sudoedit /etc/zabbix/nginx.conf`. Uncomment and set `listen 80;` and `server_name mon01.lab.local 192.168.56.10;`. Then remove Ubuntu's default site, which also wants port 80:
   ```bash
   mon01$ sudo rm /etc/nginx/sites-enabled/default
   mon01$ sudo nginx -t
   mon01$ sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.3-fpm
   mon01$ sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.3-fpm
   mon01$ systemctl is-active zabbix-server zabbix-agent2 nginx php8.3-fpm mariadb
   ```
7. **Setup wizard:** open `http://192.168.56.10/` in the Windows browser.
   - Pre-requisites: all OK.
   - DB: MySQL, `localhost`, database `zabbix`, user `zabbix`, your password. Credentials stored in plain text.
   - Zabbix server name `ak-infra-lab`, time zone Asia/Kolkata. Finish.
8. Log in as `Admin` / `zabbix` and **change the Admin password straight away** (*User settings → Profile → Change password*).

```bash
mon01$ free -m                  # note how much RAM is left
mon01$ sudo tail -n 20 /var/log/zabbix/zabbix_server.log
```
**Expected:** the dashboard loads, *Reports → System information* shows "Zabbix server is running: Yes", and the pre-created host *Zabbix server* turns green (ZBX) within a couple of minutes.
📸 **Evidence:** `M3-zabbix-sysinfo.png`.

### M3.3 Health check and procstat on both nodes (T15)

```bash
$ cd ~/ak-infra-lab
$ sudo install -m 0755 scripts/healthcheck.sh scripts/procstat.py /usr/local/bin/
$ sudo install -m 0644 systemd/ak-health.service systemd/ak-health.timer /etc/systemd/system/
$ sudo systemctl daemon-reload && sudo systemctl enable --now ak-health.timer
$ /usr/local/bin/healthcheck.sh; echo "exit=$?"            # T15
$ /usr/local/bin/procstat.py                                # JSON report straight from /proc
$ /usr/local/bin/procstat.py mem_avail_pct
$ systemctl list-timers ak-health.timer
```
**Expected:** `OK: <host> healthy` and `exit=0` on both nodes. If you get a WARN or CRIT, the message tells you what to fix. That's the script working, not failing.

### M3.4 (web01) Zabbix agent 2

1. On **zabbix.com/download** select **7.0 LTS → Rocky Linux → 10 → Agent 2**. If Rocky 10 isn't listed for 7.0, pick *Red Hat Enterprise Linux 10* or *AlmaLinux 10*: same packages. Use the page's commands. The shape is:
   ```bash
   web01$ sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/rocky/10/x86_64/zabbix-release-latest-7.0.el10.noarch.rpm
   web01$ sudo dnf clean all
   web01$ sudo dnf -y install zabbix-agent2
   ```
   If EPEL is enabled (`dnf repolist | grep -i epel`), first add `excludepkgs=zabbix*` to the `[epel]` section of `/etc/yum.repos.d/epel.repo`, so EPEL's Zabbix packages can't replace the official ones.
2. Point the agent at mon01:
   ```bash
   web01$ sudo sed -i -e 's/^Server=.*/Server=192.168.56.10/' \
                      -e 's/^ServerActive=.*/ServerActive=192.168.56.10/' \
                      -e 's/^Hostname=.*/Hostname=web01/' /etc/zabbix/zabbix_agent2.conf
   web01$ grep -E '^(Server|ServerActive|Hostname)=' /etc/zabbix/zabbix_agent2.conf
   ```
3. Custom checks:
   ```bash
   web01$ cd ~/ak-infra-lab
   web01$ sudo install -m 0755 scripts/ak-backup-age.sh /usr/local/bin/
   web01$ sudo install -m 0644 zabbix/zabbix_agent2.d/ak.conf /etc/zabbix/zabbix_agent2.d/
   web01$ sudo install -d -m 0755 /var/lib/ak-backup
   web01$ sudo systemctl enable --now zabbix-agent2
   web01$ sudo ss -tlnp | grep 10050
   ```
4. Test it from mon01 (**T09**):
   ```bash
   mon01$ zabbix_get -s 192.168.56.11 -k agent.ping                  # 1
   mon01$ zabbix_get -s 192.168.56.11 -k ak.health.status            # 0
   mon01$ zabbix_get -s 192.168.56.11 -k ak.mem.avail_pct            # e.g. 41.3
   mon01$ zabbix_get -s 192.168.56.11 -k ak.backup.age               # 999999 (no backup yet)
   mon01$ zabbix_get -s 192.168.56.11 -k 'net.tcp.service[http,,80]' # 1
   ```
5. **SELinux check:** the agent runs your scripts. Look for denials:
   ```bash
   web01$ ps -eZ | grep zabbix_agent2
   web01$ sudo ausearch -m AVC -ts recent -i | grep -i zabbix
   ```
   If a UserParameter returns an error or a denial shows up, follow the [SELinux runbook](runbooks/selinux-denial.md) and write it up as the next INC. That's a real incident, worth more than an injected one.

### M3.5 Add web01 in the Zabbix UI

*Data collection → Hosts → Create host*:
- **Host name** `web01` (must equal `Hostname=` in the agent config)
- Templates: **Linux by Zabbix agent**
- Host groups: *Linux servers*
- Interfaces: *Add → Agent*, IP `192.168.56.11`, port `10050`

Click *Add*. **Expected:** after a minute or two the **ZBX** availability badge turns green, and *Monitoring → Latest data* (filter host web01) fills with CPU, memory and filesystem items.

### M3.6 The "AK Linux Lab" template

Build it exactly as specified in [zabbix/README.md](../zabbix/README.md): 4 items and 5 triggers. Link it to web01 (*host → Templates → Link new*). Check that *Latest data* shows the four AK items with values.

Export it: *Data collection → Templates →* tick *AK Linux Lab* → *Export → YAML*, and save it on Windows as `zabbix/templates/ak-linux-lab.yaml`.

### M3.7 Prove the alert works (T10, manual)

```bash
web01$ sudo systemctl stop nginx
```
Watch *Monitoring → Problems*. **Expected:** "nginx is down on web01" (High) appears within about a minute.
📸 **Evidence:** `T10-problem.png`.

```bash
web01$ sudo systemctl start nginx
```
**Expected:** the problem moves to RESOLVED within about a minute.
📸 **Evidence:** `T10-resolved.png`. Record both times in the test plan.

*(Optional: real notifications. Zabbix ships a Telegram media type. You'd create a bot and enter its token in the UI. Never commit the token.)*

### M3.8 Backups to mon01 (T11)

**a) mon01: the receiving account.** It's called `akbackup`, because Ubuntu already has a system user named `backup` ([ADR-003](decisions/ADR-003-tar-rsync-backups.md)).
```bash
mon01$ sudo useradd -m -s /bin/bash akbackup
mon01$ sudo install -d -o akbackup -g akbackup -m 0700 /srv/backups/web01
mon01$ sudo install -d -o akbackup -g akbackup -m 0700 /home/akbackup/.ssh
```
`akbackup` has no password, so it can only log in with a key. `AllowGroups` in the hardening file already includes `akbackup`.

**b) web01: root's backup key.** Password SSH is off by now, so copy the public key over through the akadmin sessions instead of `ssh-copy-id`:
```bash
web01$ sudo ssh-keygen -t ed25519 -N '' -C "root@web01-backup" -f /root/.ssh/backup_ed25519
web01$ sudo install -m 0644 /root/.ssh/backup_ed25519.pub /tmp/backup_ed25519.pub
mon01$ scp web01:/tmp/backup_ed25519.pub /tmp/
mon01$ sudo install -m 0600 -o akbackup -g akbackup /tmp/backup_ed25519.pub /home/akbackup/.ssh/authorized_keys
mon01$ rm /tmp/backup_ed25519.pub; ssh web01 rm /tmp/backup_ed25519.pub
web01$ sudo ssh -i /root/.ssh/backup_ed25519 akbackup@192.168.56.10 true && echo "key works"   # type "yes" once: stores mon01's host key for root
```
The last line also records mon01's host key in `/root/.ssh/known_hosts`. The script runs with `BatchMode=yes` and can't answer that question itself.

**c) Install the job and run it once:**
```bash
web01$ cd ~/ak-infra-lab
web01$ sudo install -m 0700 scripts/ak-backup.sh /usr/local/sbin/
web01$ sudo install -m 0644 systemd/ak-backup.service systemd/ak-backup.timer /etc/systemd/system/
web01$ sudo systemctl daemon-reload && sudo systemctl enable --now ak-backup.timer
web01$ sudo systemctl start ak-backup.service
web01$ journalctl -u ak-backup -n 20 --no-pager                       # "OK web01_<date>.tar.gz"
web01$ systemctl list-timers ak-backup.timer                          # next run tonight
web01$ ls -l /var/lib/ak-backup/ /var/backups/ak/
mon01$ sudo ls -l /srv/backups/web01/
mon01$ zabbix_get -s 192.168.56.11 -k ak.backup.age                   # small number of seconds now
```
**Expected:** the archive and its `.sha256` exist on both sides, the archive is mode `-rw-------` (it contains `/etc/shadow`), and the backup age is now seconds, not 999999.

**d) Retention on mon01 (14 days) with cron:**
```bash
mon01$ sudo crontab -u akbackup -e
```
Add this line:
```
15 3 * * * find /srv/backups -type f -name '*.tar.gz*' -mtime +14 -delete
```
Then check it with `sudo crontab -u akbackup -l`.
> **cron vs timer (interview point):** the backup uses a systemd timer, because `Persistent=true` catches up after downtime and the output lands in the journal. The prune uses cron, a simple per-user job where a missed run doesn't matter. Be ready to explain both.

If `akbackup` can't log in (`journalctl -u ssh` on mon01 says the account is locked): `sudo usermod -p '*' akbackup`. That means "no password", not "locked".

### M3.9 Prove the restore (T12a, T12b)

Follow [runbooks/restore-from-backup.md](runbooks/restore-from-backup.md) once, for real, restoring `etc/nginx/conf.d/app.conf` into `/root/restore`. Then:
```bash
mon01$ sudo bash -c 'cd /srv/backups/web01 && f=$(ls -1t *.tar.gz | head -1) && sha256sum -c "$f.sha256"'   # T12a: OK
web01$ sudo diff -u /root/restore/etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf && echo identical
web01$ sudo ls -Z /root/restore/etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf           # same label (T12b)
```
📸 **Evidence:** the `sha256sum -c` line, and the time the restore took (your measured RTO).
```powershell
PS> git add -A; git commit -m "M3: Zabbix 7.0 + custom template, health checks, backups with tested restore"
```

### 🚦 Gate G3
- [ ] T09 `agent.ping` = 1; the web01 ZBX badge is green
- [ ] T10 problem and resolved screenshots
- [ ] T11 timer scheduled, T12a checksum OK, T12b restore matches content and label
- [ ] T15 `healthcheck.sh` exit 0 on both
- [ ] Template exported to `zabbix/templates/`

---

## M4: Document and publish v1.0

### M4.1 Run the full test suite

```powershell
PS> powershell -ExecutionPolicy Bypass -File tools\sync-to-lab.ps1 -Hosts mon01
```
```bash
mon01$ cd ~/ak-infra-lab && bash tests/verify.sh
```
**Expected:** `== SUMMARY: N PASS, 0 FAIL, 3 SKIP ==`. The three SKIPs are T13, T14 and T20, which arrive in E1. You're asked for akadmin's sudo password on web01 and then on mon01.
Fix every FAIL, and write it up as an incident if it was a real bug. Then run the suite again.
📸 **Evidence:** paste the full output into `tests/test-plan.md` and fill in the Result column.

### M4.2 Screenshots

These go in `docs/screenshots/`:
- `M0-networks.png`: VirtualBox NAT Network and host-only settings
- `M3-zabbix-sysinfo.png`: Zabbix system information
- `M4-zabbix-hosts.png`: host list with green ZBX badges
- `M4-zabbix-latest-ak.png`: latest data for the AK items
- `T10-problem.png`, `T10-resolved.png`
- `M2-browser-app.png`

CLI output belongs in text blocks in the docs, not in screenshots.

### M4.3 Finish the docs

- README: status 🟢, exact versions (`cat /etc/rocky-release`, `lsb_release -d`, `zabbix_server -V`, `VBoxManage --version`), verification summary line, INC-001 link.
- `docs/ip-plan.md`: matches reality, including web01's actual labnet IP.
- INC-001 complete, and the incident index updated.

### M4.4 Push, tag, publish

```powershell
PS> git grep -n -i -E "password *=|BEGIN OPENSSH|ZBX_DB_PASSWORD=[^<]"     # must find nothing secret
PS> git add -A
PS> git commit -m "v1.0: 2-node lab built, verified (verify.sh 0 FAIL), INC-001"
PS> git tag v1.0
PS> git push origin main --tags
```
On GitHub: set the repo to **Public**, add the topics `linux rocky-linux ubuntu zabbix selinux lvm systemd bash sysadmin homelab`, and pin it on your profile.

### M4.5 Resume line (v1.0)

> Built and operated a 2-node Linux lab (Rocky Linux 10, Ubuntu 24.04) in VirtualBox: role-based users and sudo, LVM storage with online extension, systemd services with cgroup limits, SSH/firewalld/SELinux hardening, and systemd-timer backups with verified restores; monitored it with Zabbix 7.0 using custom Bash/Python checks and alert triggers.

### 🚦 Gate G4 (v1.0 definition of done)
- [ ] `verify.sh`: 0 FAIL (SKIP only T13/T14/T20), T10 recorded
- [ ] Every success criterion in `docs/requirements.md` (SC1–SC5) is met
- [ ] Repo public, tag `v1.0`, no secrets
- [ ] The resume line matches what was built, word for word

---

## E1: Hardening and central logging (week 2)

### E1.1 auditd (T13)

```bash
web01$ sudo install -m 0640 ~/ak-infra-lab/configs/common/audit/rules.d/50-ak.rules /etc/audit/rules.d/
web01$ sudo augenrules --load
web01$ sudo auditctl -l
web01$ sudo useradd -M t13 && sudo userdel t13
web01$ sudo ausearch -k identity -i -ts recent | tail -20
web01$ sudo aureport -au --summary
```
**Expected:** the useradd/userdel events show **`auid=akadmin`**. The audit trail keeps your login identity even through sudo.
Don't use `systemctl restart auditd`: the unit refuses manual restarts. Use `augenrules --load`.
Optional on mon01: `sudo apt install auditd` and the same rules.

### E1.2 sysctl hardening (T20)

```bash
$ sudo install -m 0644 ~/ak-infra-lab/configs/common/sysctl.d/90-ak.conf /etc/sysctl.d/
$ sudo sysctl --system | tail -12
$ sysctl -n kernel.dmesg_restrict vm.swappiness
$ cat /proc/sys/vm/swappiness                       # same value: sysctl is a view of /proc/sys
$ dmesg | head -2                                   # as akadmin, without sudo: "Operation not permitted"
```

### E1.3 Central logging (T14)

**mon01 (the receiver):**
```bash
mon01$ sudo install -d -o syslog -g adm -m 0750 /var/log/remote
mon01$ sudo install -m 0644 ~/ak-infra-lab/configs/mon01/rsyslog.d/10-remote.conf /etc/rsyslog.d/
mon01$ sudo install -m 0644 ~/ak-infra-lab/configs/mon01/logrotate.d/remote /etc/logrotate.d/
mon01$ sudo rsyslogd -N1 && sudo systemctl restart rsyslog
mon01$ sudo ss -tlnp | grep 20514
mon01$ sudo logrotate -d /etc/logrotate.d/remote 2>&1 | tail -5     # dry run, no errors
```

**web01 (the sender):**
```bash
web01$ sudo semanage port -l | grep syslogd_port_t                  # is 20514 listed for tcp?
web01$ sudo semanage port -a -t syslogd_port_t -p tcp 20514          # only if it is NOT listed
web01$ sudo install -m 0644 ~/ak-infra-lab/configs/common/rsyslog.d/90-forward.conf /etc/rsyslog.d/
web01$ sudo rsyslogd -N1 && sudo systemctl restart rsyslog
web01$ logger -t t14 hello-from-web01
mon01$ sudo tail -n 3 /var/log/remote/web01/t14.log
```
**Expected:** the line arrives within a second or two.
**Test the queue:** `sudo systemctl stop rsyslog` on mon01, run `logger -t t14 queued-while-down` on web01, then start rsyslog on mon01 again. The queued line must arrive.
If nothing arrives, check `sudo ausearch -m AVC -ts recent` on web01 (the port label) and `sudo ufw status` on mon01.

### E1.4 Password aging and a login banner

```bash
web01$ sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/; s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' /etc/login.defs   # new users only
web01$ grep -E '^PASS_(MAX_DAYS|WARN_AGE)' /etc/login.defs
web01$ printf 'Authorized use only. Activity on this system is logged and audited.\n' | sudo tee /etc/issue.net
web01$ printf 'Banner /etc/issue.net\n' | sudo tee /etc/ssh/sshd_config.d/11-banner.conf
web01$ sudo sshd -t && sudo systemctl reload sshd
```
Existing users keep their own aging settings (`chage -l akdev`). `login.defs` only applies to accounts created later. Save `11-banner.conf` in the repo too, under `configs/common/sshd_config.d/`, so E3 can deploy it.

### E1.5 Review the listening ports

```bash
$ sudo ss -tulpn
```
Add a "listening ports" table to [ip-plan.md](ip-plan.md) that explains every port. Disable anything you can't explain (`systemctl disable --now <unit>`) and re-run `verify.sh`.

### E1.6 Lock the backup key down

On mon01, edit `/home/akbackup/.ssh/authorized_keys` so that the one line starts with a restriction:
```
restrict,command="/usr/bin/rrsync -wo /srv/backups/web01" ssh-ed25519 AAAA...rest-of-key... root@web01-backup
```
`restrict` turns off port forwarding, PTYs and agent forwarding. `rrsync -wo` allows rsync writes into that one directory and nothing else. Check that rrsync exists: `dpkg -L rsync | grep rrsync`.

Then on web01, change `DEST=` in `/usr/local/sbin/ak-backup.sh` (and in the repo copy) to `akbackup@192.168.56.10:./`. The path is now relative to the directory rrsync allows.
```bash
web01$ sudo systemctl start ak-backup.service && journalctl -u ak-backup -n 5 --no-pager    # still OK
web01$ sudo ssh -i /root/.ssh/backup_ed25519 akbackup@192.168.56.10 id                      # refused by rrsync
```
📸 **Evidence:** both outputs. The key can now only deliver backups.

### 🚦 E1 gate
- [ ] T13, T14, T20 PASS; `verify.sh` shows 0 FAIL and **0 SKIP**
- [ ] Listening-ports table in ip-plan.md
- [ ] rrsync restriction proven

---

## E2: Patching and break/fix (week 3)

### E2.1 CHG-001: security patching on web01

Copy [changes/TEMPLATE.md](changes/TEMPLATE.md) to `docs/changes/CHG-001-security-patching-web01.md`. Fill in the plan and rollback plan **first**, then follow [runbooks/patching.md](runbooks/patching.md) and paste the real output. If no security updates are pending, record that too. "Nothing to do, verified" is a valid change outcome. Do a full `dnf upgrade` as a separate change later.

### E2.2 CHG-002: patching mon01 (apt)

Same process on Ubuntu. Check that Zabbix still works afterwards.

### E2.3 Six blind incidents with ak-chaos

```bash
web01$ sudo install -m 0700 ~/ak-infra-lab/tools/ak-chaos.sh /usr/local/sbin/ak-chaos.sh
```
For each incident:
1. Take a snapshot `pre-patch-latest`.
2. Run `sudo ak-chaos.sh inject` and copy the **ticket** it prints into a new `docs/incidents/INC-0NN-<slug>.md`.
3. Write the Symptom section. Then diagnose from the ticket, Zabbix and the runbooks, pasting real output (dead ends included).
4. Fix it, run `bash tests/verify.sh` on mon01, and do T10 by hand if the web side was affected.
5. Write the root cause, **then** run `sudo ak-chaos.sh reveal` and compare. Then `sudo ak-chaos.sh restore` (safe even though you already fixed it; it marks the fault done).
6. Commit.

Space them out, one or two per evening, so you don't remember what's left. `ak-chaos.sh list` shows what's done.

### E2.4 Two boot-level incidents by hand

- **INC-008, fstab typo → emergency mode:** snapshot, then follow the "Inject" column in [incidents/README.md](incidents/README.md) and recover with [runbooks/emergency-mode-fstab.md](runbooks/emergency-mode-fstab.md).
- **INC-009, forgotten root password:** snapshot, then follow [runbooks/root-password-reset.md](runbooks/root-password-reset.md). This is also RHCSA practice.

### E2.5 Update and publish

Update the README incident table, then commit, tag `v1.1` and push. The resume line becomes:

> …with Zabbix 7.0 (custom Bash/Python checks, alert triggers), auditd and centralized rsyslog; resolved 8 injected incidents with written root-cause analyses and runbooks, and ran patching through change records with rollback plans.

---

## E3: Ansible rebuild (week 4)

### E3.1 Install on mon01 (the control node)

```bash
mon01$ sudo apt -y install ansible        # the full package: includes community.general and ansible.posix
mon01$ ansible --version
mon01$ ansible-galaxy collection list 2>/dev/null | grep -E 'community.general|ansible.posix'
mon01$ cd ~/ak-infra-lab/ansible && ansible all -m ping -K
```
**Expected:** `pong` from mon01 (local) and web01 (over SSH with the mon01 key).

### E3.2 The worked example: role `common`

```bash
mon01$ ansible-playbook site.yml --check --diff       # dry run: read every "changed"
mon01$ ansible-playbook site.yml                      # apply
mon01$ ansible-playbook site.yml                      # again: PLAY RECAP must show changed=0
```
**Why `changed=0` matters:** idempotency. A playbook that changes something on every run isn't describing a state. It's just a script.

### E3.3 Write the other four roles

`hardening`, `web`, `zabbix_agent` and `backup` are stubs. Each one lists what it must do and which modules to use. Write one role at a time, then run `--check --diff`, apply, and apply again (`changed=0`). Copy files from the repo. Don't paste config into YAML.

### E3.4 The real gate: rebuild from scratch

1. Take a snapshot of web01 as `pre-ansible` (your way back).
2. Restore web01's `clean-install` snapshot. VirtualBox detaches the data disks that were added after it.
3. Attach **two new, empty** disks (5 GB + 2 GB).
4. From the web01 console, put the mon01 key and the Windows key back in akadmin's `authorized_keys` (the snapshot predates them), or copy them as in M0.10.
5. `ansible-playbook site.yml`, then `bash tests/verify.sh`.

**Expected:** one run converges, `verify.sh` shows 0 FAIL, and a second run reports `changed=0`. Anything you still had to do by hand goes in the README as a known gap. Tag `v2.0`, and the resume line gains: *"…and automated the rebuild with Ansible (idempotent roles, verified by a test suite)."*

---

## E4 (optional): cgroups, namespaces, performance, NFS

- **CPU cap demo:** run `sudo systemd-run --unit=burn -p CPUQuota=20% /usr/bin/sha256sum /dev/zero`, watch it with `systemd-cgtop`, then `sudo systemctl stop burn`. Record a before/after table.
- **OOM demo:** `sudo systemd-run --unit=hog -p MemoryMax=64M /usr/bin/python3 -c "b=bytearray(200*1024*1024)"`, then `journalctl -k | grep -i oom` and `systemctl status hog`.
- **Namespaces:** `sudo dnf install podman`, run a rootless container as akdev, then `lsns` and `podman top`.
- **Performance baseline:** `sar -u 1 10`, `vmstat 1 10` and `iostat -x 1 5`, idle vs under load. Keep a table.
- **NFS + autofs:** on the 8 GB laptop, export from **mon01** (not a third VM). `apt install nfs-kernel-server` on mon01, `dnf install nfs-utils autofs` on web01, and web01 automounts `/net/share`. Open 2049/tcp in ufw from web01 only.

## E5 (optional): Zabbix 7.0 → 8.0

Only after 8.0 is GA and a few minor releases in. Read the 8.0 upgrade notes (DB and PHP minimums), then snapshot mon01, `mysqldump` the zabbix DB, upgrade the repo package, `apt upgrade`, and verify the dashboards and triggers. Write it all as a change record with a rollback step.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| VM won't start: "VT-x is not available" / `VERR_VMX_NO_VMX` | Virtualization off in BIOS, or the hypervisor still owns it | Check that Intel VT-x is enabled in the BIOS/UEFI; re-check M0.2 with preflight |
| Green turtle in the VM status bar | VirtualBox is on the Hyper-V backend | M0.2 (hypervisor off, reboot) |
| Rocky installer kernel panic / "CPU not supported" | x86-64-v3 not exposed | M0.7; hypervisor off, or AlmaLinux 10 v2 |
| Rocky graphical installer black screen | Display driver | Add `inst.text` at the boot menu |
| VM has no internet | Adapter 1 not on `labnet`, or a gateway on enp0s8 | `ip route` must show one default route via enp0s3 |
| New VM boots straight into an automatic install, logs in as `vboxuser`, no LVM | The wizard's **"Proceed with Unattended Installation"** was ticked | Delete the VM (*Remove → Delete all files*), re-create it with that box **unticked**, and clean leftover `Unattended-*` folders in `D:\VirtualBox VMs` |
| Adapter 2 shows Name "Not selected" | The host-only adapter is missing (`VBoxManage list hostonlyifs` is empty) | In Terminal (Admin): `VBoxManage hostonlyif create`, then `VBoxManage hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0` |
| Windows can't reach 192.168.56.x | Adapter 2 not host-only, or a wrong IP | `ip -br addr` on the VM; the Windows `ipconfig` has 192.168.56.1 |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` on Windows | The key file's ACL is too open | `icacls "$env:USERPROFILE\.ssh\id_ed25519" /inheritance:r /grant:r "$($env:USERNAME):R"` |
| A path with a space breaks a command | Your Windows user folder is `C:\Users\ATHUL KRISHNA` | Always quote paths: `"$env:USERPROFILE\.ssh\…"` |
| `$'\r': command not found` | CRLF line endings from a Windows editor | `sed -i 's/\r$//' <file>` on the VM; keep `.gitattributes`; set VS Code to LF |
| Zabbix UI: "Zabbix server is not running" | Wrong `DBPassword`, or the server crashed on low memory | `sudo tail /var/log/zabbix/zabbix_server.log`; `free -m` |
| web01 ZBX badge red | Firewall, `Server=` IP, or `Hostname` mismatch | `ss -tlnp \| grep 10050`; `firewall-cmd --zone=mgmt --list-ports`; `zabbix_get` from mon01 |
| Everything is slow | RAM pressure on the 8 GB host | Close the browser, run the VMs headless, `free -m` in each VM |

## Where each interview question is answered in this lab

| Question | Step |
|---|---|
| Boot process, root password reset | E2.4 / INC-009 |
| Disk full: diagnosis (`df`, `du`, `lsof +L1`, `df -i`) | INC-002, INC-003 |
| Extend LVM online; can XFS shrink? | M2.8 |
| nginx 502 with the backend up (SELinux) | M2.6 / INC-001 |
| SELinux contexts, booleans, `semanage`, `restorecon` | M2.5, M2.6, INC-005 |
| firewalld zones; SSH only from a management subnet | M1.8, INC-006 |
| SSH hardening without locking yourself out | M1.6, M1.7, ssh-lockout runbook |
| sudo vs su, least privilege for developers | M1.5 |
| Permissions, ACLs, default ACLs | M2.3 |
| Slow server: top / vmstat / iostat / sar | E4 |
| OOM killer and `MemoryMax` | E4 |
| cron vs systemd timers | M3.8 |
| Is a backup restorable? RPO/RTO | M3.9, ADR-003 |
| Patching process with rollback | E2.1, patching runbook |
| Passive vs active Zabbix checks; custom checks | M3.4–M3.6, zabbix/README.md |
| Why did a service fail (`systemctl status`, `journalctl -u … -b`) | service-down runbook, INC-004 |
| Central logging, Rocky vs Ubuntu log locations | E1.3 |
| RHEL vs Ubuntu (dnf/apt, SELinux/AppArmor, firewalld/ufw, nmcli/netplan) | M0–M1 on both nodes |
| Tell me about an incident you handled (STAR) | any `docs/incidents/INC-*` |
