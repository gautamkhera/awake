# awake

A tiny Windows command that keeps your PC **and its display** from sleeping, either until you turn it off, for a set time, or until a clock time.

```
awake            # on, indefinitely. Run it again to turn it off.
awake 2h         # on for 2 hours
awake 17:30      # on until 5:30 PM
awake off        # off
awake status     # is it on? until when?
```

No dependencies, no admin rights, nothing to keep open: it runs as a hidden background process, so you can close the terminal.

## Install

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/gautamkhera/awake/main/install.ps1 | iex
```

Or from a clone:

```powershell
git clone https://github.com/gautamkhera/awake.git
cd awake
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then open a new terminal. `awake` works in PowerShell, Command Prompt, Windows Terminal and Git Bash.

The installer puts the script in `%LOCALAPPDATA%\Programs\awake` and adds its `bin` folder to your user `PATH`. Re-run it to upgrade.

## Usage

| Command | What it does |
| --- | --- |
| `awake` | Toggle: turn on indefinitely, or turn off if already on |
| `awake <duration>` | Stay awake for a while: `90` (minutes), `45m`, `2h`, `1h30m`, `1d` |
| `awake <time>` | Stay awake until a time today (or tomorrow if it has passed): `17:30`, `5pm`, `5:30pm` |
| `awake on [duration\|time]` | Turn on (without toggling off) |
| `awake off` | Turn off |
| `awake status` | Show whether it is on, and until when |
| `awake help` | Show help |

Giving a new duration or time while awake is already on replaces the old timer.

## How it works

`awake` starts a hidden PowerShell process that calls the Windows [`SetThreadExecutionState`](https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) API with `ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED`, the same mechanism video players use. When the timer ends or you run `awake` again, the process exits and Windows goes back to your normal power settings. Nothing about your power plan is changed.

State lives in `%LOCALAPPDATA%\awake\state.json`.

Note: this stops *idle* sleep. Closing a laptop lid or pressing the power button still does whatever your power settings say.

## Uninstall

```powershell
irm https://raw.githubusercontent.com/gautamkhera/awake/main/uninstall.ps1 | iex
```

or `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1` from a clone.

## License

MIT
