# Builds the desktop 8051 emulator: mcs51_desktop.exe (the window) and
# mcs51_console.exe (the same program with a console, for --test / --bench).
param(
    [string]$Compiler = 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe',
    # The Neon Arcade Display Engine checkout: NEON_ENGINE_DIR, or one beside this repository.
    [string]$Engine = $(if ($env:NEON_ENGINE_DIR) { $env:NEON_ENGINE_DIR } else { ((Join-Path $PSScriptRoot '..\..\Neon-Arcade-Dispay-Engine') -replace '\\', '/') + '/' })
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src = Join-Path $here 'mcs51_desktop.pb'
foreach ($b in @(@('mcs51_desktop.exe', @()), @('mcs51_console.exe', @('/CONSOLE')))) {
    $exe = Join-Path $here $b[0]
    $args = @($src, '/EXE', $exe, '/THREAD', '/DPIAWARE', '/OPTIMIZER', '/CONSTANT', "GL_ENGINE_DIR$=$Engine") + $b[1]
    & $Compiler @args
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $exe)) { throw "Build failed: $($b[0])" }
}
Get-FileHash -Algorithm SHA256 (Join-Path $here 'mcs51_desktop.exe'), (Join-Path $here 'mcs51_console.exe') | Format-Table -AutoSize
