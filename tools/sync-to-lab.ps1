<#
.SYNOPSIS
  Copy the deployable parts of this repo to the lab VMs as ~/ak-infra-lab/.
  The Windows copy of the repo is the source of truth: edit here, sync, then install on the VM.
      powershell -ExecutionPolicy Bypass -File tools\sync-to-lab.ps1              # both VMs
      powershell -ExecutionPolicy Bypass -File tools\sync-to-lab.ps1 -Hosts web01 # one VM
  Needs the ~/.ssh/config entries from configs/windows/ssh_config.example.
  It only adds and overwrites files; it never deletes on the VM.
#>
param([string[]]$Hosts = @('mon01', 'web01'))

$root  = Split-Path -Parent $PSScriptRoot
$items = 'configs', 'scripts', 'systemd', 'zabbix', 'tests', 'tools', 'ansible'

foreach ($h in $Hosts) {
    Write-Host "== $h ==" -ForegroundColor Cyan
    ssh $h 'mkdir -p ~/ak-infra-lab'
    if ($LASTEXITCODE -ne 0) { Write-Host "cannot reach $h, skipped" -ForegroundColor Red; continue }
    foreach ($i in $items) {
        scp -r -q (Join-Path $root $i) "${h}:ak-infra-lab/"
        if ($LASTEXITCODE -eq 0) { Write-Host "  $i" } else { Write-Host "  $i FAILED" -ForegroundColor Red }
    }
    # Scripts lose nothing in transit, but make sure they are executable on the VM
    ssh $h 'chmod +x ~/ak-infra-lab/scripts/* ~/ak-infra-lab/tests/*.sh ~/ak-infra-lab/tools/*.sh 2>/dev/null; true'
}
