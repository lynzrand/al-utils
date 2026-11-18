# Install into the selected game's existing NPR plugin, preserving its previous files.
param(
    [Parameter(Mandatory)][string]$GamePath,
    [Parameter(Mandatory)][string]$Bundle,
    [Parameter(Mandatory)][string]$Backup,
    [string]$Loader="$PSScriptRoot/../bin/Release/net6.0/AL_NPR.dll"
)
$ErrorActionPreference='Stop'
$game=(Resolve-Path -LiteralPath $GamePath).Path
$plugin=(Resolve-Path -LiteralPath (Join-Path $game 'BepInEx/plugins/AL_NPR')).Path
$assets=[ordered]@{
    'AL_NPR.dll'=(Resolve-Path -LiteralPath $Loader).Path
    'al-skin-lighting.unity3d'=(Resolve-Path -LiteralPath $Bundle).Path
}
if (!(Test-Path -LiteralPath (Join-Path $game 'AmanatsuLocation.exe'))) { throw 'Expected an Amanatsu game directory' }
$backupPath=[IO.Path]::GetFullPath($Backup)
if ($backupPath.StartsWith($game+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Keep rollback files outside the game'}
[IO.Directory]::CreateDirectory($backupPath) | Out-Null
$done=@()
try {
    foreach ($k in $assets.Keys) {
        $dest=Join-Path $plugin $k
        $old=Join-Path $backupPath $k
        $next="$dest.new"
        if((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $assets[$k]).Hash) {continue}
        if(!(Test-Path -LiteralPath $old)){[IO.File]::Copy($dest,$old,$false)}
        if((Get-FileHash -LiteralPath $old).Hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw "Backup already contains a different $k"}
        if(!(Test-Path -LiteralPath $next)){[IO.File]::Copy($assets[$k],$next,$false)}
        if((Get-FileHash -LiteralPath $next).Hash -ne (Get-FileHash -LiteralPath $assets[$k]).Hash){throw "Unexpected staging file: $next"}
        # Windows allows renaming some mapped DLLs even when overwriting the
        # mapped file is forbidden. BepInEx will not scan the renamed file.
        $retired="$dest.$([guid]::NewGuid().ToString('N')).previous"
        [IO.File]::Move($dest,$retired)
        try {[IO.File]::Move($next,$dest)} catch {[IO.File]::Move($retired,$dest);throw}
        $done+=@{Name=$k;Retired=$retired}
        if((Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $assets[$k]).Hash){throw "Verification failed: $k"}
    }
} catch {
    foreach ($file in $done) {[IO.File]::Move($file.Retired,(Join-Path $plugin $file.Name),$true)}
    throw
}
foreach($k in $assets.Keys){Get-FileHash -LiteralPath (Join-Path $plugin $k) | Select-Object Path,Hash}
