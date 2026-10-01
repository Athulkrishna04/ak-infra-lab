<#
.SYNOPSIS
  Read-only check of the Windows host before and during M0 (build guide M0.1 / M0.3).
  Changes nothing. Run from the repo root:
      powershell -ExecutionPolicy Bypass -File tools\preflight.ps1
  Output: PASS / WARN / FAIL / INFO lines. Re-run it after every M0 step.
#>
$ErrorActionPreference = 'Continue'

function Say([string]$level, [string]$msg) {
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$level]
    Write-Host ("{0,-4} {1}" -f $level, $msg) -ForegroundColor $color
}

Write-Host "== ak-infra-lab host preflight ==" -ForegroundColor Cyan

# --- Memory -----------------------------------------------------------------------------
$cs  = Get-CimInstance Win32_ComputerSystem
$os  = Get-CimInstance Win32_OperatingSystem
$ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
if ($ram -ge 15) { Say PASS "RAM $ram GB: the 16 GB layout (4 VMs) is possible" }
elseif ($ram -ge 7) { Say PASS "RAM $ram GB: use the 8 GB layout (mon01 2 GB + web01 1.5 GB)" }
else { Say FAIL "RAM $ram GB: below the 8 GB layout" }
if ($free -lt 4) { Say WARN "Only $free GB RAM free right now: close the browser and other apps before starting VMs" }
else { Say INFO "$free GB RAM free right now" }

# --- CPU --------------------------------------------------------------------------------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Say INFO ("CPU {0} ({1} cores / {2} threads)" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
Say INFO "x86-64-v3 (needed by Rocky 10) is confirmed inside a VM in M0.7, not here"

# --- Disk -------------------------------------------------------------------------------
foreach ($d in 'C', 'D') {
    $drive = Get-PSDrive -Name $d -PSProvider FileSystem -ErrorAction SilentlyContinue
    if ($null -eq $drive) { continue }
    $gb = [math]::Round($drive.Free / 1GB, 1)
    if ($d -eq 'D') {
        if ($gb -ge 60) { Say PASS "D: has $gb GB free (VMs + ISOs need about 60 GB)" }
        else { Say WARN "D: has only $gb GB free (VMs + ISOs need about 60 GB)" }
    } else {
        if ($gb -lt 25) { Say WARN "C: has only $gb GB free: keep VMs and ISOs OFF C: (machine folder on D:)" }
        else { Say INFO "C: has $gb GB free" }
    }
}
$isoDir = 'D:\ISO'
if (Test-Path $isoDir) {
    $isos = Get-ChildItem $isoDir -Filter *.iso -ErrorAction SilentlyContinue
    if ($isos) { foreach ($i in $isos) { Say INFO ("ISO found: {0} ({1} GB)" -f $i.Name, [math]::Round($i.Length / 1GB, 1)) } }
    else { Say WARN "$isoDir exists but holds no .iso yet (M0.5)" }
} else { Say WARN "$isoDir not created yet (M0.5)" }

# --- Hypervisor / VBS -------------------------------------------------------------------
if ($cs.HypervisorPresent) {
    Say WARN "Windows hypervisor is RUNNING: VirtualBox will use the slow Hyper-V backend (green turtle) and may hide AVX2 (M0.2)"
} else {
    Say PASS "Windows hypervisor is off: VirtualBox can use VT-x directly"
}
try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    if ($dg.VirtualizationBasedSecurityStatus -eq 2) {
        if ($dg.SecurityServicesRunning -contains 2) { Say WARN "Memory Integrity (HVCI) is running: it keeps the hypervisor on (M0.2)" }
        else { Say WARN "Virtualization-based security is running" }
    } else { Say PASS "Virtualization-based security is not running" }
} catch { Say INFO "Could not read Device Guard status" }

# --- WSL --------------------------------------------------------------------------------
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $env:WSL_UTF8 = '1'
    $running = (wsl.exe -l --running 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $running -and $running -notmatch 'no running') {
        Say WARN "WSL distros are running: run 'wsl --shutdown' before lab work"
    } else { Say PASS "No WSL distro running" }
} else { Say INFO "WSL not installed" }

# --- VirtualBox -------------------------------------------------------------------------
$vbm = $null
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue
if ($reg -and $reg.InstallDir) { $vbm = Join-Path $reg.InstallDir 'VBoxManage.exe' }
if (-not $vbm -or -not (Test-Path $vbm)) { $vbm = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' }
if (Test-Path $vbm) {
    $ver = (& $vbm --version).Trim()
    if ($ver -like '7.2*') { Say PASS "VirtualBox $ver installed" } else { Say WARN "VirtualBox $ver installed: 7.2.x is the supported branch" }
    $props = & $vbm list systemproperties
    $folder = ($props | Select-String '^Default machine folder:\s+(.*)$').Matches.Groups[1].Value
    if ($folder -like 'D:*') { Say PASS "Default machine folder: $folder" }
    else { Say FAIL "Default machine folder is '$folder': set it to D:\VirtualBox VMs before creating VMs (M0.4)" }
    $natnets = (& $vbm natnetwork list) -join "`n"
    if ($natnets -match 'labnet') { Say PASS "NAT network 'labnet' exists" } else { Say WARN "NAT network 'labnet' not created yet (M0.4)" }
    $vms = & $vbm list vms
    foreach ($n in 'mon01', 'web01') {
        if ($vms -match "`"$n`"") { Say PASS "VM $n exists" } else { Say INFO "VM $n not created yet" }
    }
} else { Say WARN "VirtualBox not installed yet (M0.3)" }

$hostOnly = Get-NetIPAddress -IPAddress 192.168.56.1 -ErrorAction SilentlyContinue
if ($hostOnly) { Say PASS ("Host-only adapter has 192.168.56.1 ({0})" -f $hostOnly.InterfaceAlias) }
else { Say INFO "No host-only adapter with 192.168.56.1 yet (created by VirtualBox)" }

# --- SSH --------------------------------------------------------------------------------
if (Get-Command ssh.exe -ErrorAction SilentlyContinue) { Say PASS "Windows OpenSSH client present" }
else { Say FAIL "ssh.exe not found: add the Windows 'OpenSSH Client' optional feature" }
$key = Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'
if (Test-Path $key) { Say PASS "SSH key $key exists" } else { Say INFO "No ~/.ssh/id_ed25519 yet (M0.10)" }
$cfg = Join-Path $env:USERPROFILE '.ssh\config'
if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'Host web01' -Quiet)) { Say PASS "~/.ssh/config has web01/mon01 entries" }
else { Say INFO "~/.ssh/config has no lab entries yet (M0.10)" }

Write-Host "== done ==" -ForegroundColor Cyan
