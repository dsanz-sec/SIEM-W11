<#
    stress-red-100105.ps1
    Descarga repetida de un fichero grande para superar 10 000 KB/s (regla 100105).
    Si no llega con una sola copia, lanzar 2-3 en paralelo.

    Alternativa recomendada, sin depender de internet (solo red interna del lab):
      Parrot:   sudo apt install iperf3 -y && iperf3 -s
      Windows:  iperf3.exe -c <IP-interna-de-Parrot> -t 180 -P 4

    Uso: .\stress-red-100105.ps1 -Url <url-de-un-fichero-grande> -DurationSeconds 180
#>
param(
    [int]$DurationSeconds = 180,
    [Parameter(Mandatory = $true)][string]$Url   # URL de un fichero grande (ej. un test de velocidad de tu proveedor)
)

# Sin esto, la barra de progreso de Invoke-WebRequest reduce mucho el throughput
$ProgressPreference = 'SilentlyContinue'

$endTime = (Get-Date).AddSeconds($DurationSeconds)
$dest    = "$env:TEMP\wazuh_net_stress.bin"

Write-Host "Descargando $Url en bucle durante $DurationSeconds s..."

while ((Get-Date) -lt $endTime) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    } catch {
        Write-Warning "Descarga fallida, reintentando: $_"
        Start-Sleep -Seconds 2
    }
}

Remove-Item $dest -Force -ErrorAction SilentlyContinue
Write-Host "Prueba terminada."
