[CmdletBinding()]
param(
    [string]$GamePath = 'H:\Programs\gal\amanatsu-location',
    [string]$InteropPath,
    [switch]$Smoke
)

$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$artifacts = New-Item -ItemType Directory -Force -Path (Join-Path $project 'artifacts')
$sdk = New-Item -ItemType Directory -Force -Path (Join-Path $artifacts.FullName 'openvr')
$header = Join-Path $sdk.FullName 'openvr_capi.h'
$license = Join-Path $sdk.FullName 'LICENSE'
$sdkUrl = 'https://raw.githubusercontent.com/ValveSoftware/openvr/v2.12.14'
if (!(Test-Path -LiteralPath $header)) {
    Invoke-WebRequest "$sdkUrl/headers/openvr_capi.h" -OutFile $header
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $header).Hash -ne 'D58A2B149E434B2B8EE25CB4253CA6157FEED8092F621E78ECFED6846D35D3E4') {
    throw "Unexpected OpenVR header at $header"
}
if (!(Test-Path -LiteralPath $license)) {
    Invoke-WebRequest "$sdkUrl/LICENSE" -OutFile $license
}

if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installation) {
        throw 'Install the Visual Studio C++ x64 tools and Windows SDK.'
    }
    $vsDevShell = Join-Path $installation 'Common7\Tools\Launch-VsDevShell.ps1'
    & $vsDevShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
}
if ($env:VSCMD_ARG_TGT_ARCH -ne 'x64') {
    throw 'Run from an x64 Visual Studio developer shell.'
}

$output = New-Item -ItemType Directory -Force -Path (Join-Path $artifacts.FullName 'plugin\AL_VR')
$buildArgs = @('build', (Join-Path $project 'AL_VR.csproj'), '-c', 'Release', '--nologo', '-warnaserror', "-p:GamePath=$GamePath")
if ($InteropPath) {
    $buildArgs += "-p:InteropPath=$InteropPath"
}
& dotnet @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Managed build failed ($LASTEXITCODE)."
}

$native = New-Item -ItemType Directory -Force -Path (Join-Path $artifacts.FullName 'native')
Push-Location $native.FullName
try {
    $flags = @('/nologo', '/std:c++17', '/EHsc', '/MT', '/O2', '/W4', '/WX',
        '/DNOMINMAX', '/DWIN32_LEAN_AND_MEAN', "/external:I$($sdk.FullName)", '/external:W0')
    & cl.exe @flags /LD (Join-Path $project 'native\OpenVrBridge.cpp') /link /OUT:AL_VR_Native.dll
    if ($LASTEXITCODE -ne 0) {
        throw "Native bridge build failed ($LASTEXITCODE)."
    }
    if ($Smoke) {
        & cl.exe @flags /LD (Join-Path $project 'tests\MockOpenVr.cpp') /link /OUT:MockOpenVr.dll
        if ($LASTEXITCODE -ne 0) {
            throw "Mock runtime build failed ($LASTEXITCODE)."
        }
        & cl.exe @flags (Join-Path $project 'tests\BridgeSmoke.cpp') /link d3d11.lib /OUT:BridgeSmoke.exe
        if ($LASTEXITCODE -ne 0) {
            throw "Native smoke build failed ($LASTEXITCODE)."
        }
        & .\BridgeSmoke.exe
        if ($LASTEXITCODE -ne 0) {
            throw "Native smoke failed ($LASTEXITCODE)."
        }
    }
}
finally {
    Pop-Location
}

Copy-Item -LiteralPath (Join-Path $project 'bin\Release\net6.0\AL_VR.dll'),
    (Join-Path $native.FullName 'AL_VR_Native.dll') -Destination $output.FullName
Copy-Item -LiteralPath $license -Destination (Join-Path $output.FullName 'OpenVR-LICENSE.txt')
Write-Host "Plugin package: $($output.FullName)"
