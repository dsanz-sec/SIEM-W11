<#
    stress-disco-100104.ps1
    Escritura continua de 1 MB forzada a disco (no solo a cache) para
    superar el 90 % de tiempo de disco activo (regla 100104).

    Uso: .\stress-disco-100104.ps1 -DurationSeconds 180
#>
param(
    [int]$DurationSeconds = 180,
    [string]$TestFile = "$env:TEMP\wazuh_disk_stress.tmp"
)

$buffer = New-Object byte[] (1MB)
(New-Object Random).NextBytes($buffer)

Write-Host "Escribiendo en $TestFile durante $DurationSeconds s..."

$fs = [System.IO.File]::Open($TestFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$endTime = (Get-Date).AddSeconds($DurationSeconds)

try {
    while ((Get-Date) -lt $endTime) {
        $fs.Write($buffer, 0, $buffer.Length)
        $fs.Flush($true)
        $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    }
} finally {
    $fs.Close()
    Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
}
Write-Host "Prueba terminada."
