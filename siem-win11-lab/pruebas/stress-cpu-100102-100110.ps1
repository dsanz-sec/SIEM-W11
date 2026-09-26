<#
    stress-cpu-100102-100110.ps1
    Carga de CPU sostenida para disparar la regla de correlacion 100110
    (y la 100101/100102 segun lo que llegue a marcar la CPU).

    Clave: UN SOLO proceso de PowerShell con varios hilos (runspaces) internos.
    Si se lanzan varios powershell.exe sueltos, Windows los numera
    (powershell, powershell#1, ...), top_proc cambia entre muestras y
    same_field nunca acumula las 5 coincidencias.

    Uso (consola normal de PowerShell, mejor que ISE):
      .\stress-cpu-100102-100110.ps1 -DurationMinutes 8
#>
param(
    [int]$DurationMinutes = 8,
    [int]$ThreadsPerCore = 2
)

$cores   = [Environment]::ProcessorCount
$threads = $cores * $ThreadsPerCore

Write-Host "Núcleos: $cores | Hilos de carga: $threads | PID: $PID"

$pool = [runspacefactory]::CreateRunspacePool(1, $threads)
$pool.Open()

$jobs = @()
for ($i = 0; $i -lt $threads; $i++) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript({
        param($minutes)
        $endTime = (Get-Date).AddMinutes($minutes)
        while ((Get-Date) -lt $endTime) { $x = 1 }
    }).AddArgument($DurationMinutes)
    $jobs += [PSCustomObject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}

foreach ($j in $jobs) {
    $j.Pipe.EndInvoke($j.Handle) | Out-Null
    $j.Pipe.Dispose()
}
$pool.Close()
Write-Host "Prueba terminada."
