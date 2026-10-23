# Thermal guard (user rule): if the device reaches 87 C, hold all project work,
# let it cool to 50-65 C, then resume exactly where it stopped.
#
# What can be measured without admin rights on this laptop:
#   * GPU temperature via nvidia-smi                      -> trip at >= 87 C, resume at <= 65 C
#   * CPU temperature is NOT exposed (no ACPI thermal zone for non-admin users).
#     Proxy: CPU thermal throttling = effective clock < 60% of maximum on two
#     consecutive checks while CPU load is high.
# Hold = suspend (freeze) Rscript/java processes with NtSuspendProcess and pause
# the Cloudera VM with VBoxManage. Resume = NtResumeProcess + VM resume. Nothing is
# killed or restarted, so every job continues from the exact point it was frozen.
#   powershell -ExecutionPolicy Bypass -File scripts/thermal_guard.ps1 -Hours 14
param([double]$Hours = 14, [int]$TripC = 87, [int]$ResumeC = 65, [int]$CheckSec = 30,
      [int]$MinCoolSec = 300, [double]$ThrottlePct = 60)

Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ProcCtl {
  [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);
  [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr h);
}
"@
$log = "results/thermal_guard.log"
$vb = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$vm = "cloudera-quickstart-vm-5.13.0-0-virtualbox"
function Log($m) { "{0}  {1}" -f (Get-Date -Format s), $m | Tee-Object -FilePath $log -Append }
function GpuTemp { [int]((nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits) | Select-Object -First 1) }
function CpuPerf {
  $c = Get-Counter '\Processor Information(_Total)\% Processor Performance', '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1
  @{ perf = $c.CounterSamples[0].CookedValue; load = $c.CounterSamples[1].CookedValue }
}
function Targets { @(Get-Process Rscript, R, Rterm, java -ErrorAction SilentlyContinue) }

Log "guard started: trip GPU>=$TripC C or CPU throttling (<$ThrottlePct% clock x2); resume at GPU<=$ResumeC C after >=$MinCoolSec s"
$end = (Get-Date).AddHours($Hours); $throttleHits = 0
while ((Get-Date) -lt $end) {
  $g = GpuTemp; $c = CpuPerf
  if ($c.load -gt 50 -and $c.perf -lt $ThrottlePct) { $throttleHits++ } else { $throttleHits = 0 }
  if ($g -ge $TripC -or $throttleHits -ge 2) {
    $why = if ($g -ge $TripC) { "GPU $g C" } else { "CPU throttling (clock {0:N0}% of max)" -f $c.perf }
    $procs = Targets
    foreach ($p in $procs) { [void][ProcCtl]::NtSuspendProcess($p.Handle) }
    $vmWasRunning = ((& $vb showvminfo $vm --machinereadable) -match '^VMState="running"').Count -gt 0
    if ($vmWasRunning) { & $vb controlvm $vm pause | Out-Null }
    Log "HOLD ($why): suspended $($procs.Count) processes [$(($procs | ForEach-Object { "$($_.Name):$($_.Id)" }) -join ' ')]; VM paused=$vmWasRunning"
    $t0 = Get-Date
    do { Start-Sleep -Seconds $CheckSec; $g = GpuTemp } while ($g -gt $ResumeC -or ((Get-Date) - $t0).TotalSeconds -lt $MinCoolSec)
    foreach ($p in $procs) { if (-not $p.HasExited) { [void][ProcCtl]::NtResumeProcess($p.Handle) } }
    if ($vmWasRunning) { & $vb controlvm $vm resume | Out-Null }
    Log ("RESUME after {0:N0} s cooling: GPU {1} C" -f ((Get-Date) - $t0).TotalSeconds, $g)
    $throttleHits = 0
  }
  Start-Sleep -Seconds $CheckSec
}
Log "guard stopped (time limit)"
