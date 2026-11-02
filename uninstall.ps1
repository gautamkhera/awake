<#
  Removes an awake install made by install.ps1. (If you installed with winget,
  run `winget uninstall GautamKhera.Awake` instead.)

    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>

$ErrorActionPreference = 'Stop'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\awake'
$OldBinDir  = Join-Path $InstallDir 'bin'
$StateDir   = Join-Path $env:LOCALAPPDATA 'awake'

# Turn awake off first so no background process is left behind.
$exe = Join-Path $InstallDir 'awake.exe'
if (Test-Path $exe) { & $exe off | Out-Null }
$oldScript = Join-Path $InstallDir 'awake.ps1'
if (Test-Path $oldScript) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oldScript off | Out-Null }

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$newPath = ($userPath -split ';' | Where-Object { $_ -and $_ -ne $InstallDir -and $_ -ne $OldBinDir }) -join ';'
if ($newPath -ne $userPath) { $key.SetValue('Path', $newPath, 'ExpandString') }
$key.Close()
$env:Path = ($env:Path -split ';' | Where-Object { $_ -and $_ -ne $InstallDir -and $_ -ne $OldBinDir }) -join ';'

Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $StateDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'awake uninstalled.' -ForegroundColor Green
