<#
    stress-memoria-100103.ps1
    Reserva memoria hasta dejar menos de 1000 MB libres (regla 100103).
    Toca cada pagina para que cuente como uso fisico real, no solo reserva virtual.

    Uso: .\stress-memoria-100103.ps1 -TargetFreeMB 700 -HoldSeconds 180
#>
param(
    [int]$TargetFreeMB = 700,
    [int]$HoldSeconds = 180
)

$os          = Get-CimInstance Win32_OperatingSystem
$freeMB      = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
$toConsumeMB = $freeMB - $TargetFreeMB

if ($toConsumeMB -le 0) {
    Write-Host "Ya hay menos de $TargetFreeMB MB libres."
    return
}

Write-Host "Memoria libre: $freeMB MB. Reservando $toConsumeMB MB durante $HoldSeconds s..."

$blockSizeMB  = 100
$blocksNeeded = [math]::Ceiling($toConsumeMB / $blockSizeMB)
$blocks       = New-Object System.Collections.ArrayList

for ($i = 0; $i -lt $blocksNeeded; $i++) {
    $buf = New-Object byte[] ($blockSizeMB * 1MB)
    for ($j = 0; $j -lt $buf.Length; $j += 4096) { $buf[$j] = 1 }
    [void]$blocks.Add($buf)
}

Start-Sleep -Seconds $HoldSeconds

$blocks.Clear()
[System.GC]::Collect()
Write-Host "Memoria liberada. Prueba terminada."
