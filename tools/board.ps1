# Uploads and captures on the shared board under ONE lease, taken and given
# back only through the shared C:\PMFBuild\board-leases\lease.ps1.
#   .\tools\board.ps1 -Port COM7 -Jobs 'tests/verify.picow:firmware/verify.uf2:45', 'src/demo.picow:firmware/8051-picow.uf2:25'
# Every image is compiled first, off the board, so a compile error never
# holds the lease. Each job's serial capture is in <output>.build.log.
param(
    [string]$Port = 'COM7',
    [Parameter(Mandatory)][string[]]$Jobs,
    [string]$Owner = 'cg-8051'
)
$ErrorActionPreference = 'Stop'
# From powershell.exe -File a comma list arrives as ONE string.
$Jobs = @($Jobs | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$build = Join-Path $PSScriptRoot 'build.ps1'
$minutes = 1
foreach ($job in $Jobs) {
    $src, $out, $secs = $job -split ':'
    & $build -Source $src -Output $out | Out-Null
    $minutes += [math]::Ceiling(([int]$secs + 40) / 60)
}
. C:\PMFBuild\board-leases\lease.ps1
$lease = Get-BoardLease -Port $Port -Owner $Owner -Minutes $minutes
"lease taken $(Get-Date -Format o)"
try {
    foreach ($job in $Jobs) {
        $src, $out, $secs = $job -split ':'
        try {
            & $build -Source $src -Output $out -Port $Port -Seconds ([int]$secs) | Out-Null
            "$src -> uploaded and captured"
        } catch {
            "$src -> FAILED: $_"
        }
    }
} finally {
    Release-BoardLease $lease
    "lease released $(Get-Date -Format o)"
}
