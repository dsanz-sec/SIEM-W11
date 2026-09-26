<#
    perf-monitor.ps1
    Telemetria de rendimiento para Wazuh (proyecto siem-win11-lab).

    Cada ejecucion toma una muestra de CPU, memoria, disco, red y del proceso
    que mas CPU consume, y la escribe como una linea JSON en perf-monitor.log.
    El agente de Wazuh lee ese log (localfile) y lo envia al manager.

    Lo lanza el wodle "command" del agente cada 60 s (ver ossec-conf-perf-monitor.xml).
    Ubicacion: C:\Program Files (x86)\ossec-agent\perf-monitor.ps1

    Decisiones (detalle en docs/documentacion-wazuh.docx):
      - Clases CIM en vez de Get-Counter: los nombres no dependen del idioma de Windows.
      - Log en ASCII: con UTF-8, PowerShell 5.1 escribe un BOM que rompe el parseo JSON.
      - FileShare.ReadWrite: el agente mantiene el log abierto; Add-Content falla en silencio.
#>

$ErrorActionPreference = "SilentlyContinue"

$logFile = "C:\Program Files (x86)\ossec-agent\perf-monitor.log"

# Rotacion simple: si supera 5 MB, se vacia
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 5MB)) {
    Clear-Content $logFile
}

# CPU total
$cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime

# Memoria
$os         = Get-CimInstance Win32_OperatingSystem
$memFreeMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
$memTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
$memUsedPct = [math]::Round((($memTotalMB - $memFreeMB) / $memTotalMB) * 100, 0)

# Disco
$disk    = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
$diskPct = [int]$disk.PercentDiskTime
$diskKBs = [math]::Round($disk.DiskBytesPersec / 1KB, 0)

# Red (excluye loopback y tuneles virtuales)
$net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface |
       Where-Object { $_.Name -notmatch 'Loopback|isatap|Teredo' }
$netKBs = [math]::Round((($net | Measure-Object -Property BytesTotalPersec -Sum).Sum) / 1KB, 0)

# Proceso que mas CPU consume
# Nota: PercentProcessorTime por proceso suma todos los nucleos logicos,
# por eso top_proc_cpu puede superar el 100 % (maximo = 100 x nucleos).
$top = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
       Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
       Sort-Object PercentProcessorTime -Descending | Select-Object -First 1

$sample = [ordered]@{
    integration  = "perf_monitor"
    cpu_pct      = [int]$cpu
    mem_used_pct = [int]$memUsedPct
    mem_free_mb  = [int]$memFreeMB
    disk_pct     = $diskPct
    disk_kbps    = [int]$diskKBs
    net_kbps     = [int]$netKBs
    top_proc     = $top.Name
    top_proc_cpu = [int]$top.PercentProcessorTime
}

$json = $sample | ConvertTo-Json -Compress

# Escritura con FileShare.ReadWrite: el agente tiene el fichero abierto para leerlo
# y Add-Content/Set-Content fallan con "el archivo esta siendo utilizado por otro proceso".
$fs = $null
$sw = $null
try {
    $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $sw = New-Object System.IO.StreamWriter($fs, [System.Text.Encoding]::ASCII)
    $sw.WriteLine($json)
    $sw.Flush()
} finally {
    if ($sw) { $sw.Close() }
    if ($fs) { $fs.Close() }
}
