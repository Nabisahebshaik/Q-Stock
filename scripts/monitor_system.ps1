# Overnight health log: every 5 minutes append a row to results/system_monitor.csv.
# CPU temperature is not exposed to non-admin users on this laptop, so thermal
# throttling is tracked via the effective CPU clock (% of maximum frequency).
#   powershell -ExecutionPolicy Bypass -File scripts/monitor_system.ps1 -Hours 14
param([double]$Hours = 14, [int]$IntervalSec = 300)
$out = "results/system_monitor.csv"
if (-not (Test-Path $out)) {
  "time,cpu_load_pct,cpu_perf_pct_of_max,gpu_temp_c,gpu_power_w,free_ram_gb,on_ac_power,vm_state,rscript_procs" | Out-File $out -Encoding utf8
}
$vb = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$end = (Get-Date).AddHours($Hours)
while ((Get-Date) -lt $end) {
  try {
    $c = Get-Counter '\Processor(_Total)\% Processor Time', '\Processor Information(_Total)\% Processor Performance' -SampleInterval 2 -MaxSamples 1
    $load = [math]::Round($c.CounterSamples[0].CookedValue, 1)
    $perf = [math]::Round($c.CounterSamples[1].CookedValue, 1)
  } catch { $load = ""; $perf = "" }
  $g = (nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader,nounits) -split ",\s*"
  $os = Get-CimInstance Win32_OperatingSystem
  $free = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
  $ac = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1).PowerOnline
  $vm = ((& $vb showvminfo "cloudera-quickstart-vm-5.13.0-0-virtualbox" --machinereadable) | Select-String '^VMState=') -replace 'VMState=|"', ''
  $rs = @(Get-Process Rscript -ErrorAction SilentlyContinue).Count
  "{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f (Get-Date -Format s), $load, $perf, $g[0], $g[1], $free, $ac, $vm, $rs | Add-Content $out
  Start-Sleep -Seconds $IntervalSec
}
