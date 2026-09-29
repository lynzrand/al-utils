[CmdletBinding()]
param([string]$GamePath = 'H:\Programs\amanatsu-location')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$game = (Resolve-Path -LiteralPath $GamePath).Path
if (!(Test-Path -LiteralPath (Join-Path $game 'AmanatsuLocation.exe'))) {
    throw 'GamePath must point to an Amanatsu Location installation.'
}
if (Get-Process AmanatsuLocation -ErrorAction SilentlyContinue) {
    throw 'Exit Amanatsu Location before installing the plugin.'
}
dotnet build (Join-Path $project 'AL_PovX.csproj') -c Release "-p:GamePath=$game"
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
$source = Join-Path $project 'bin\Release\net6.0\AL_PovX.dll'
$destination = Join-Path $game 'BepInEx\plugins\AL_PovX'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$dll = Join-Path $destination 'AL_PovX.dll'
if (Test-Path -LiteralPath $dll) {
    $backup = Join-Path $project ('artifacts\backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-ffff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $dll -Destination (Join-Path $backup 'AL_PovX.dll')
    Write-Output "Previous plugin backed up to $backup"
}
Copy-Item -LiteralPath $source -Destination $dll
if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dll).Hash) {
    throw 'Installed DLL hash does not match the build.'
}
Write-Output "Installed and verified: $dll"
