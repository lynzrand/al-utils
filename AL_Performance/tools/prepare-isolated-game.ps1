[CmdletBinding()]
param(
    [string]$GamePath = 'H:\Programs\gal\amanatsu-location',
    [Parameter(Mandatory)][string]$Destination,
    [switch]$RenderDoc
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
$game = (Resolve-Path -LiteralPath $GamePath).ProviderPath
$clone = [IO.Path]::GetFullPath($Destination)
$prefix = (Join-Path $repo 'artifacts') + [IO.Path]::DirectorySeparatorChar
if (!$clone.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $clone)) {
    throw 'The isolated game must use a fresh subdirectory below workspace artifacts.'
}

New-Item -ItemType Directory -Path $clone | Out-Null
foreach ($file in @('AmanatsuLocation.exe', 'GameAssembly.dll', 'UnityPlayer.dll', 'UnityCrashHandler64.exe',
        'baselib.dll', 'winhttp.dll', 'doorstop_config.ini', 'version', '.doorstop_version')) {
    Copy-Item -LiteralPath (Join-Path $game $file) -Destination $clone -Force
}
foreach ($dir in @('lib', 'DefaultData', 'dotnet')) {
    New-Item -ItemType Junction -Path (Join-Path $clone $dir) -Target (Join-Path $game $dir) | Out-Null
}
$sourceData = Join-Path $game 'AmanatsuLocation_Data'
$cloneData = Join-Path $clone 'AmanatsuLocation_Data'
New-Item -ItemType Directory -Path $cloneData | Out-Null
foreach ($entry in Get-ChildItem -LiteralPath $sourceData) {
    if ($entry.PSIsContainer) {
        New-Item -ItemType Junction -Path (Join-Path $cloneData $entry.Name) -Target $entry.FullName | Out-Null
    } elseif ($entry.Name -eq 'globalgamemanagers') {
        # Frame timing changes a flag in this file. Give the clone its own copy.
        Copy-Item -LiteralPath $entry.FullName -Destination $cloneData
    } else {
        New-Item -ItemType HardLink -Path (Join-Path $cloneData $entry.Name) -Target $entry.FullName | Out-Null
    }
}

$sourceBep = Join-Path $game 'BepInEx'
$cloneBep = Join-Path $clone 'BepInEx'
New-Item -ItemType Directory -Path $cloneBep | Out-Null
foreach ($dir in @('core', 'config', 'interop-AmanatsuLocation')) {
    Copy-Item -LiteralPath (Join-Path $sourceBep $dir) -Destination $cloneBep -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $cloneBep 'plugins') | Out-Null
$plugin = Join-Path $repo 'AL_Performance\bin\Release\net6.0\AL_Performance.dll'
Copy-Item -LiteralPath $plugin -Destination (Join-Path $cloneBep 'plugins')
if ($RenderDoc) {
    $preloader = Join-Path $repo 'AL_Performance\RenderDocPreloader\bin\Release\net6.0\AL_RenderDocPreloader.dll'
    New-Item -ItemType Directory -Path (Join-Path $cloneBep 'patchers') | Out-Null
    Copy-Item -LiteralPath $preloader -Destination (Join-Path $cloneBep 'patchers')
}

# Capture files, user settings, and logs are written in the isolated game.
& (Join-Path $repo 'artifacts\static\set-frame-timing.ps1') -GamePath $clone
Write-Output $clone
