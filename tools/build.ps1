param(
    # PureMetal Forge: PMF_COMPILER, or PureMetalForge.exe on PATH.
    [string]$Compiler = $(if ($env:PMF_COMPILER) { $env:PMF_COMPILER } else { 'PureMetalForge.exe' }),
    [string]$Source = 'src/demo.picow',
    [string]$Output = 'firmware/8051-picow.uf2',
    [string]$Port = '',
    [int]$Seconds = 12,
    [string[]]$Require = @()
)
# Builds a PureMetal source; with -Port, also uploads and captures serial
# output through the compiler (the compiler is the uploader).
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Source))
$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
[IO.Directory]::CreateDirectory((Split-Path $outputPath -Parent)) | Out-Null
$stdoutPath = $outputPath + '.build.log'
$stderrPath = $outputPath + '.stderr.log'

function Invoke-Compiler([string]$arguments) {
    $process = Start-Process -FilePath $Compiler -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    Get-Content $stdoutPath
    Get-Content $stderrPath
    if ($process.ExitCode -ne 0) { throw "Compiler exit $($process.ExitCode): $stdoutPath" }
}

# Compile first, without the board, so a compile error never holds the lease.
Invoke-Compiler ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '"')
if ($outputPath.EndsWith('.uf2')) {
    # The NES ROM store starts at flash $10050000: no image may reach it.
    $uf2 = [IO.File]::ReadAllBytes($outputPath); $imageEnd = 0
    for ($o = 0; $o -lt $uf2.Length; $o += 512) {
        $blockEnd = [BitConverter]::ToUInt32($uf2, $o + 12) + [BitConverter]::ToUInt32($uf2, $o + 16)
        if ($blockEnd -gt $imageEnd) { $imageEnd = $blockEnd }
    }
    if ($imageEnd -gt 0x10050000) { throw ('Image reaches 0x{0:X8}, past the NES ROM store at 0x10050000; not uploaded.' -f $imageEnd) }
    'Image end 0x{0:X8}' -f $imageEnd
}
if ($Port) {
    # The board is shared: run this through tools/board.ps1, which holds the lease.
    Invoke-Compiler ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '" --port ' + $Port + ' --seconds ' + $Seconds)
    $transcript = Get-Content -Raw $stdoutPath
    foreach ($required in $Require) {
        if (!$transcript.Contains($required)) { throw "Missing board verdict: $required" }
    }
    if ($Require.Count -gt 0 -and $transcript -cmatch '\bFAIL\b') { throw "Board reported FAIL: $stdoutPath" }
}
Get-FileHash -Algorithm SHA256 -LiteralPath $Compiler, $sourcePath, $outputPath | Format-Table -AutoSize
