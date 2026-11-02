<#
  Builds awake.exe from source and installs it for the current user (no admin
  needed). Most people should use `winget install GautamKhera.Awake` instead.

    git clone https://github.com/gautamkhera/awake.git
    cd awake
    powershell -ExecutionPolicy Bypass -File .\install.ps1

  Puts awake.exe in %LOCALAPPDATA%\Programs\awake and adds that folder to your
  user PATH. Re-run it to upgrade.
#>

$ErrorActionPreference = 'Stop'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\awake'
$OldBinDir  = Join-Path $InstallDir 'bin'

& (Join-Path $PSScriptRoot 'build.ps1')

# Clean up the 1.0 PowerShell-script install, turning it off first if it's running.
$oldScript = Join-Path $InstallDir 'awake.ps1'
if (Test-Path $oldScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oldScript off | Out-Null
    Remove-Item $oldScript, $OldBinDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Stop a running copy so the exe can be replaced.
$exe = Join-Path $InstallDir 'awake.exe'
if (Test-Path $exe) { & $exe off | Out-Null }

New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'dist\awake.exe') $exe -Force

# Add the install folder to the user PATH, preserving any %VARIABLES% in it.
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$entries = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $OldBinDir })
if ($entries -notcontains $InstallDir) { $entries += $InstallDir }
$newPath = $entries -join ';'
if ($newPath -ne $userPath) {
    $key.SetValue('Path', $newPath, 'ExpandString')

    # Tell Explorer so newly opened terminals see the new PATH.
    Add-Type -Namespace AwakeInstall -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $result = [UIntPtr]::Zero
    [void][AwakeInstall.Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}
$key.Close()

$env:Path = (@($env:Path -split ';' | Where-Object { $_ -and $_ -ne $OldBinDir }) + $InstallDir | Select-Object -Unique) -join ';'

Write-Host "awake installed to $InstallDir" -ForegroundColor Green
Write-Host "Open a new terminal and run 'awake help' to get started."
