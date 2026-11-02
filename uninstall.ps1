<#
  Removes awake for the current user.

  From a clone:   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
  From the web:   irm https://raw.githubusercontent.com/gautamkhera/awake/main/uninstall.ps1 | iex
#>

$ErrorActionPreference = 'Stop'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\awake'
$BinDir     = Join-Path $InstallDir 'bin'
$StateDir   = Join-Path $env:LOCALAPPDATA 'awake'

# Turn awake off first so no background process is left behind.
$script = Join-Path $InstallDir 'awake.ps1'
if (Test-Path $script) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script off | Out-Null }

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$entries = $userPath -split ';' | Where-Object { $_ }
if ($entries -contains $BinDir) {
    $key.SetValue('Path', (($entries | Where-Object { $_ -ne $BinDir }) -join ';'), 'ExpandString')
}
$key.Close()
$env:Path = (($env:Path -split ';') | Where-Object { $_ -and $_ -ne $BinDir }) -join ';'

Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $StateDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'awake uninstalled.' -ForegroundColor Green
