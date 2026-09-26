<#
    instalar-agente.ps1
    Instala el agente de Wazuh 4.14.7 en Windows 11, copia el script de telemetria
    y añade el wodle + localfile al ossec.conf.

    Ejecutar en PowerShell como administrador, desde la raiz del repositorio:
      .\agente\instalar-agente.ps1 -ManagerIP 192.168.1.10 -Password "<password-enrolamiento>"

    La contraseña de enrolamiento se obtiene en el manager con:
      sudo grep "Random password" /var/ossec/logs/ossec.log
    (cambia cada vez que se reinicia wazuh-manager)
#>
param(
    [Parameter(Mandatory = $true)][string]$ManagerIP,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$AgentName = $env:COMPUTERNAME,
    [string]$AgentVersion = "4.14.7-1"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # la barra de progreso ralentiza mucho Invoke-WebRequest

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Ejecuta este script en una consola de PowerShell como administrador."
}

$repoDir  = Split-Path -Parent $PSScriptRoot
$agentDir = "C:\Program Files (x86)\ossec-agent"
$msi      = Join-Path $env:TEMP "wazuh-agent-$AgentVersion.msi"

Write-Host "[1/5] Descargando el agente $AgentVersion..."
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$AgentVersion.msi" -OutFile $msi -UseBasicParsing

Write-Host "[2/5] Instalando y registrando el agente contra $ManagerIP..."
$msiArgs = @(
    "/i", "`"$msi`"", "/q",
    "WAZUH_MANAGER=`"$ManagerIP`"",
    "WAZUH_REGISTRATION_SERVER=`"$ManagerIP`"",
    "WAZUH_REGISTRATION_PASSWORD=`"$Password`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "/l*v", "`"$env:TEMP\wazuh-installer.log`""
)
$p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "msiexec termino con codigo $($p.ExitCode). Revisa $env:TEMP\wazuh-installer.log" }

Write-Host "[3/5] Copiando perf-monitor.ps1..."
Copy-Item (Join-Path $repoDir "agente\perf-monitor.ps1") $agentDir -Force

Write-Host "[4/5] Añadiendo el wodle y el localfile a ossec.conf..."
$conf = Join-Path $agentDir "ossec.conf"
if (Select-String -Path $conf -Pattern "<tag>perf-monitor</tag>" -Quiet) {
    Write-Host "    ossec.conf ya contiene el bloque perf-monitor; no se modifica."
} else {
    Copy-Item $conf "$conf.bak" -Force
    $bloque = Get-Content (Join-Path $repoDir "agente\ossec-conf-perf-monitor.xml") -Raw
    # Se quita el comentario inicial y se añade como bloque <ossec_config> adicional
    $bloque = $bloque -replace '(?s)<!--.*?-->\s*', ''
    Add-Content -Path $conf -Value "`r`n$bloque" -Encoding ASCII
}

Write-Host "[5/5] Reiniciando el servicio..."
Restart-Service WazuhSvc
Start-Sleep -Seconds 70

$log = Join-Path $agentDir "perf-monitor.log"
if (Test-Path $log) {
    Write-Host "Ultima muestra de telemetria:"
    Get-Content $log -Tail 1
} else {
    Write-Warning "Todavia no existe perf-monitor.log. Revisa ossec.log del agente (buscar 'perf-monitor')."
}
Write-Host "Listo. Comprueba en el dashboard (Endpoints) que el agente aparece como Active."
