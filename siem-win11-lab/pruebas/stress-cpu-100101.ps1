<#
    stress-cpu-100101.ps1
    Carga de CPU en la banda 80-94 % durante poco tiempo (regla 100101),
    sin llegar a sostenerla lo suficiente para la 100110.
    Usa todos los nucleos menos uno, dentro de un unico proceso.

    Uso: .\stress-cpu-100101.ps1 -DurationMinutes 3
#>
param(
    [int]$DurationMinutes = 3
)

$cores     = [Environment]::ProcessorCount
$busyCores = [Math]::Max(1, $cores - 1)

Write-Host "Núcleos: $cores | Hilos de carga: $busyCores | PID: $PID"

$pool = [runspacefactory]::CreateRunspacePool(1, $busyCores)
$pool.Open()

$jobs = @()
for ($i = 0; $i -lt $busyCores; $i++) {
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
