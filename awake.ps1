<#
  awake - keep Windows (and the display) awake.

    awake               toggle: turn on indefinitely, or turn off if already on
    awake 2h            stay awake for a duration (90, 45m, 2h, 1h30m, 1d)
    awake 17:30         stay awake until a clock time (17:30, 5pm, 5:30pm)
    awake off           turn off
    awake status        show current state
    awake help          show help

  The work is done by a hidden background PowerShell process that holds a
  SetThreadExecutionState request, so closing the terminal does not stop it.
#>

$ErrorActionPreference = 'Stop'
$Version   = '1.0.0'
$StateDir  = Join-Path $env:LOCALAPPDATA 'awake'
$StateFile = Join-Path $StateDir 'state.json'

function Show-Help {
    @"
awake $Version - keep this PC and its display awake

Usage:
  awake               toggle on (indefinitely) / off
  awake <duration>    stay awake for a while:   90  45m  2h  1h30m  1d
  awake <time>        stay awake until a time:  17:30  5pm  5:30pm
  awake off           turn off
  awake status        show whether awake is on, and until when
  awake help          show this help

Giving a duration or time while awake is already on replaces the old timer.
"@
}

function Format-Span([TimeSpan]$span) {
    if ($span.TotalSeconds -lt 1) { return '<1m' }
    # Round up to the minute so "awake 2h" reports 2h, not 1h 59m.
    $span = [TimeSpan]::FromMinutes([Math]::Ceiling($span.TotalMinutes))
    $parts = @()
    if ($span.Days)    { $parts += "$($span.Days)d" }
    if ($span.Hours)   { $parts += "$($span.Hours)h" }
    if ($span.Minutes) { $parts += "$($span.Minutes)m" }
    $parts -join ' '
}

function Format-When([DateTime]$when) {
    if ($when.Date -eq (Get-Date).Date) { return $when.ToString('HH:mm') }
    $when.ToString('ddd HH:mm')
}

# Returns the local DateTime to stay awake until, or $null if $text isn't a valid spec.
function ConvertTo-Deadline([string]$text) {
    $t = $text.Trim().ToLowerInvariant() -replace '\s+', ''
    $now = Get-Date

    # Plain number = minutes
    if ($t -match '^\d+$') { return $now.AddMinutes([int]$t) }

    # Duration: 1d2h30m15s, any subset, in that order
    if ($t -match '^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m(?:in)?)?(?:(\d+)s)?$' -and $t -ne '') {
        $span = New-Object TimeSpan ([int]('0' + $Matches[1])), ([int]('0' + $Matches[2])), ([int]('0' + $Matches[3])), ([int]('0' + $Matches[4]))
        if ($span.TotalSeconds -gt 0) { return $now.Add($span) }
        return $null
    }

    # Clock time: 17:30, 5pm, 5:30pm, 12am
    if ($t -match '^(\d{1,2})(?::(\d{2}))?(am|pm)?$' -and ($Matches[2] -or $Matches[3])) {
        $hour = [int]$Matches[1]
        $min  = [int]('0' + $Matches[2])
        $ampm = $Matches[3]
        if ($ampm) {
            if ($hour -lt 1 -or $hour -gt 12) { return $null }
            if ($hour -eq 12) { $hour = 0 }
            if ($ampm -eq 'pm') { $hour += 12 }
        }
        if ($hour -gt 23 -or $min -gt 59) { return $null }
        $when = $now.Date.AddHours($hour).AddMinutes($min)
        if ($when -le $now) { $when = $when.AddDays(1) }
        return $when
    }

    return $null
}

# Returns the state of the running keeper, or $null (cleaning up stale state).
function Get-Keeper {
    if (-not (Test-Path $StateFile)) { return $null }
    try {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json
        $proc = Get-Process -Id $state.pid -ErrorAction Stop
        # Guard against PID reuse by comparing process start times.
        if ($proc.StartTime.ToUniversalTime().Ticks -eq [long]$state.startTicks) { return $state }
    } catch { }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Stop-Keeper {
    $state = Get-Keeper
    if (-not $state) { return $false }
    Stop-Process -Id $state.pid -Force -ErrorAction SilentlyContinue
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    return $true
}

function Start-Keeper($until) {
    [void](Stop-Keeper)
    New-Item -ItemType Directory -Force $StateDir | Out-Null

    $untilTicks = if ($until) { $until.ToUniversalTime().Ticks } else { 0 }
    $hostExe = (Get-Process -Id $PID).Path
    $argLine = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" __keep $untilTicks"
    $proc = Start-Process -FilePath $hostExe -ArgumentList $argLine -WindowStyle Hidden -PassThru

    [pscustomobject]@{
        pid        = $proc.Id
        startTicks = $proc.StartTime.ToUniversalTime().Ticks
        since      = (Get-Date).ToString('o')
        until      = if ($until) { $until.ToString('o') } else { $null }
    } | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8

    if ($until) {
        "awake: on until $(Format-When $until) ($(Format-Span ($until - (Get-Date)))). Run 'awake' again to turn off."
    } else {
        "awake: on indefinitely. Run 'awake' again to turn off."
    }
}

function Show-Status {
    $state = Get-Keeper
    if (-not $state) { 'awake: off'; return }
    $since = [DateTime]::Parse($state.since)
    if ($state.until) {
        $until = [DateTime]::Parse($state.until)
        "awake: on until $(Format-When $until) ($(Format-Span ($until - (Get-Date))) left)"
    } else {
        "awake: on indefinitely (since $(Format-When $since))"
    }
}

# Runs inside the hidden background process.
function Invoke-Keeper([long]$untilTicks) {
    Add-Type -Namespace Awake -Name Power -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
    $ES_CONTINUOUS        = [uint32]2147483648  # 0x80000000
    $ES_SYSTEM_REQUIRED   = [uint32]1
    $ES_DISPLAY_REQUIRED  = [uint32]2
    $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

    try {
        while ($true) {
            [void][Awake.Power]::SetThreadExecutionState($flags)
            if ($untilTicks -eq 0) { Start-Sleep -Seconds 30; continue }
            $left = $untilTicks - [DateTime]::UtcNow.Ticks
            if ($left -le 0) { break }
            Start-Sleep -Milliseconds ([Math]::Min(30000, [Math]::Ceiling($left / 10000)))
        }
    } finally {
        [void][Awake.Power]::SetThreadExecutionState($ES_CONTINUOUS)
        # Only clear the state file if it still belongs to this process.
        try {
            $state = Get-Content $StateFile -Raw | ConvertFrom-Json
            if ($state.pid -eq $PID) { Remove-Item $StateFile -Force }
        } catch { }
    }
}

$cmd  = if ($args.Count) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { ($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) -join ' ' } else { '' }

switch -Regex ($cmd.ToLowerInvariant()) {
    '^__keep$'                         { Invoke-Keeper ([long]$rest); exit 0 }
    '^$'                               { if (Stop-Keeper) { 'awake: off' } else { Start-Keeper $null }; exit 0 }
    '^(off|stop)$'                     { if (Stop-Keeper) { 'awake: off' } else { 'awake: already off' }; exit 0 }
    '^(status|st)$'                    { Show-Status; exit 0 }
    '^(on|start)$' {
        if (-not $rest) { Start-Keeper $null; exit 0 }
        $until = ConvertTo-Deadline $rest
        if (-not $until) { Write-Host "awake: can't understand '$rest'" -ForegroundColor Red; Show-Help; exit 1 }
        Start-Keeper $until; exit 0
    }
    '^(help|-h|--help|-help|/\?|\?)$'  { Show-Help; exit 0 }
    '^(version|-v|--version)$'         { "awake $Version"; exit 0 }
    default {
        $spec = (@($cmd) + @($rest) | Where-Object { $_ }) -join ' '
        $until = ConvertTo-Deadline $spec
        if (-not $until) { Write-Host "awake: can't understand '$spec'" -ForegroundColor Red; Show-Help; exit 1 }
        Start-Keeper $until; exit 0
    }
}
