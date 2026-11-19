[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ControlFile,
    [Parameter(Mandatory)][string]$Prefix,
    [ValidateRange(2, 60)][int]$Seconds = 15,
    [ValidateRange(1, 30)][int]$Warmup = 6,
    [int]$Width = 0,
    [int]$Height = 0
)

$ErrorActionPreference = 'Stop'
$control = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ControlFile)
$directory = Split-Path -Parent $control

# Bracket the quality changes with the same baseline to expose drift in the scene.
$cases = @(
    @{ Name = 'base-a' },
    @{ Name = 'msaa-4'; Msaa = 4 },
    @{ Name = 'msaa-2'; Msaa = 2 },
    @{ Name = 'msaa-1'; Msaa = 1 },
    @{ Name = 'scale-85'; Scale = 0.85; Fsr = $true },
    @{ Name = 'scale-75'; Scale = 0.75; Fsr = $true },
    @{ Name = 'no-fsr'; DisableFsr = $true },
    @{ Name = 'shadow-atlas-2048'; MainShadowResolution = 2048 },
    @{ Name = 'shadow-distance-100'; ShadowDistance = 100 },
    @{ Name = 'shadow-cascades-2'; ShadowCascades = 2 },
    @{ Name = 'no-camera-shadows'; DisableShadows = $true },
    @{ Name = 'no-camera-post'; DisablePost = $true },
    @{ Name = 'no-beautify'; DisableFeatures = @('Beautify') },
    @{ Name = 'no-ssao'; DisableFeatures = @('ScreenSpaceAmbientOcclusion') },
    @{ Name = 'base-b' }
)

try {
    foreach ($case in $cases) {
        $id = "$Prefix-$($case.Name)"
        $result = Join-Path $directory "$id.json"
        if (Test-Path -LiteralPath $result) { throw "Benchmark already exists: $result" }
        $request = @{ Id = $id; Seconds = $Seconds; Warmup = $Warmup; Uncap = $true }
        if ($Width -gt 0 -and $Height -gt 0) {
            $request.OutputWidth = $Width
            $request.OutputHeight = $Height
        }
        foreach ($key in $case.Keys) {
            if ($key -ne 'Name') { $request[$key] = $case[$key] }
        }

        $request | ConvertTo-Json -Compress | Set-Content -LiteralPath $control -Encoding utf8
        $deadline = (Get-Date).AddSeconds($Seconds + $Warmup + 12)
        while (!(Test-Path -LiteralPath $result)) {
            if ((Get-Date) -gt $deadline) { throw "Timed out waiting for $id" }
            Start-Sleep -Milliseconds 250
        }
        Write-Output $id
    }
}
finally {
    @{ Id = "$Prefix-reset" } | ConvertTo-Json -Compress | Set-Content -LiteralPath $control -Encoding utf8
}
