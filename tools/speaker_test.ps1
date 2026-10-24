# A short speaker test of the PM51 board firmware, then the silent firmware back
# (the vault's rule for audio tests: short, and a silent program flashed back
# every time). Holds the SPEAKER and board leases only for that.
#   .\tools\speaker_test.ps1 -Private machine/my-pm51-picow.picow -Seconds 40
param(
    [string]$Port = 'COM7',
    [Parameter(Mandatory)][string]$Private,
    [string]$Public = 'machine/pm51_picow.picow',
    [int]$Seconds = 40,
    [string]$Owner = 'cg-8051'
)
$ErrorActionPreference = 'Stop'
$build = Join-Path $PSScriptRoot 'build.ps1'
$privOut = 'firmware/my-pm51-speaker-test.uf2'
$pubOut = 'firmware/pm51-picow.uf2'
& $build -Source $Private -Output $privOut | Out-Null
& $build -Source $Public -Output $pubOut | Out-Null
. C:\PMFBuild\board-leases\lease.ps1
$speaker = Get-BoardLease -Port SPEAKER -Owner $Owner -Minutes 4
try {
    $board = Get-BoardLease -Port $Port -Owner $Owner -Minutes 4
    try {
        "leases taken $(Get-Date -Format o)"
        try { & $build -Source $Private -Output $privOut -Port $Port -Seconds $Seconds | Out-Null; 'speaker run captured' }
        catch { "speaker run FAILED: $_" }
        try { & $build -Source $Public -Output $pubOut -Port $Port -Seconds 8 | Out-Null; 'silent firmware back on the board' }
        catch { "silent firmware upload FAILED: $_" }
    } finally { Release-BoardLease $board }
} finally {
    Release-BoardLease $speaker
    "leases released $(Get-Date -Format o)"
}
