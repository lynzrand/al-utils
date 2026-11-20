param(
    [Parameter(Mandatory)] [string] $RenderDocDirectory,
    [Parameter(Mandatory)] [string] $RenderDocSourceDirectory
)

$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath $RenderDocDirectory).Path
$source = (Resolve-Path -LiteralPath $RenderDocSourceDirectory).Path
$headers = Join-Path $source 'renderdoc/api/replay'
$dll = Join-Path $runtime 'renderdoc.dll'

# Use an x64 Visual Studio Developer PowerShell. Match the source tag to the DLL version.
Get-Command dumpbin.exe, lib.exe, cl.exe | Out-Null
Get-Item -LiteralPath $dll, (Join-Path $headers 'renderdoc_replay.h') | Out-Null

# The portable RenderDoc distribution contains the DLL without its MSVC import library.
$definition = Join-Path $runtime 'renderdoc-import.def'
$library = Join-Path $runtime 'renderdoc-import.lib'
$exports = & dumpbin.exe /nologo /exports $dll | ForEach-Object {
    if ($_ -match '^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(RENDERDOC_\w+)(\s|$)') { $Matches[1] }
}
if ($LASTEXITCODE -ne 0 -or !$exports) { throw 'Could not read RenderDoc DLL exports.' }
@('LIBRARY renderdoc.dll', 'EXPORTS') + $exports | Set-Content -LiteralPath $definition -Encoding ascii

& lib.exe /nologo /machine:x64 "/def:$definition" "/out:$library"
if ($LASTEXITCODE -ne 0) { throw 'Could not build the RenderDoc import library.' }

$object = Join-Path $runtime 'renderdoc-timings.obj'
$output = Join-Path $runtime 'renderdoc-timings.exe'
$compilerArgs = @(
    '/nologo', '/W4', '/external:W0', '/std:c++17', '/EHsc', '/MD', '/DRENDERDOC_PLATFORM_WIN32',
    "/external:I$headers", "/Fo$object", "/Fe$output", "$PSScriptRoot/renderdoc-timings.cpp", $library
)
& cl.exe @compilerArgs
if ($LASTEXITCODE -ne 0) { throw 'Could not build renderdoc-timings.exe.' }

Write-Output $output
