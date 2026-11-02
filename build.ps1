<#
  Builds dist\awake.exe with the C# compiler that ships with Windows
  (.NET Framework 4.x), so no SDK or extra tools are needed.

    powershell -ExecutionPolicy Bypass -File .\build.ps1
#>

$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc (.NET Framework 4.x is required)." }

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

& $csc /nologo /target:exe /platform:anycpu /optimize+ `
    "/out:$(Join-Path $dist 'awake.exe')" (Join-Path $PSScriptRoot 'src\awake.cs')
if ($LASTEXITCODE) { throw "Build failed (csc exit code $LASTEXITCODE)." }

Write-Host "Built $(Join-Path $dist 'awake.exe')" -ForegroundColor Green
