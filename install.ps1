<#
  Installs awake for the current user (no admin needed).

  From a clone:   powershell -ExecutionPolicy Bypass -File .\install.ps1
  From the web:   irm https://raw.githubusercontent.com/gautamkhera/awake/main/install.ps1 | iex

  Puts awake.ps1 in %LOCALAPPDATA%\Programs\awake, writes small launchers for
  cmd/PowerShell (awake.cmd) and Git Bash (awake) into its bin folder, and adds
  that folder to your user PATH. Re-run it to upgrade.
#>

$ErrorActionPreference = 'Stop'
$RepoRaw    = 'https://raw.githubusercontent.com/gautamkhera/awake/main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\awake'
$BinDir     = Join-Path $InstallDir 'bin'

New-Item -ItemType Directory -Force $BinDir | Out-Null

# Copy awake.ps1 from next to this script, or download it when run via irm | iex.
$localScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'awake.ps1' }
if ($localScript -and (Test-Path $localScript)) {
    Copy-Item $localScript (Join-Path $InstallDir 'awake.ps1') -Force
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "$RepoRaw/awake.ps1" -OutFile (Join-Path $InstallDir 'awake.ps1') -UseBasicParsing
}

# Launchers. awake.ps1 stays out of PATH so PowerShell never runs it directly
# (which would be subject to the execution policy).
$cmdShim = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\awake.ps1`" %*`r`n"
[IO.File]::WriteAllText((Join-Path $BinDir 'awake.cmd'), $cmdShim)

$shShim = "#!/bin/sh`nexec powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`$(cd `"`$(dirname `"`$0`")/..`" && pwd -W)/awake.ps1`" `"`$@`"`n"
[IO.File]::WriteAllText((Join-Path $BinDir 'awake'), $shShim)

# Add bin to the user PATH, preserving any %VARIABLES% already in it.
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$entries = $userPath -split ';' | Where-Object { $_ }
if ($entries -notcontains $BinDir) {
    $key.SetValue('Path', (($entries + $BinDir) -join ';'), 'ExpandString')

    # Tell Explorer so newly opened terminals see the new PATH.
    Add-Type -Namespace AwakeInstall -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $result = [UIntPtr]::Zero
    [void][AwakeInstall.Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}
$key.Close()

if (($env:Path -split ';') -notcontains $BinDir) { $env:Path = "$env:Path;$BinDir" }

Write-Host "awake installed to $InstallDir" -ForegroundColor Green
Write-Host "Open a new terminal and run 'awake help' to get started."
