// awake - keep Windows (and the display) awake from the terminal.
//
//   awake               toggle: turn on indefinitely, or turn off if already on
//   awake 2h            stay awake for a duration (90, 45m, 2h, 1h30m, 1d)
//   awake 17:30         stay awake until a clock time (17:30, 5pm, 5:30pm)
//   awake off           turn off
//   awake status        show current state
//
// The work is done by a hidden copy of this exe ("awake __keep <ticks>") that
// holds a SetThreadExecutionState request, so closing the terminal does not
// stop it. Written for the C# 5 compiler that ships with Windows (see build.ps1).

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;

[assembly: AssemblyTitle("awake")]
[assembly: AssemblyDescription("Keep Windows awake from the terminal")]
[assembly: AssemblyCompany("Gautam Khera")]
[assembly: AssemblyProduct("awake")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Gautam Khera. MIT License.")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

static class Awake
{
    const string Version = "1.1.0";

    const uint ES_CONTINUOUS = 0x80000000;
    const uint ES_SYSTEM_REQUIRED = 0x00000001;
    const uint ES_DISPLAY_REQUIRED = 0x00000002;

    [DllImport("kernel32.dll")]
    static extern uint SetThreadExecutionState(uint esFlags);

    static readonly string StateDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "awake");
    static readonly string StateFile = Path.Combine(StateDir, "state.txt");

    class State
    {
        public int Pid;
        public long StartTicks;
        public DateTime Since;
        public DateTime? Until;
    }

    static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0].ToLowerInvariant() : "";
        string rest = args.Length > 1 ? string.Join(" ", args, 1, args.Length - 1) : "";

        switch (cmd)
        {
            case "__keep":
                Keep(long.Parse(rest));
                return 0;
            case "":
                if (StopKeeper()) Console.WriteLine("awake: off");
                else StartKeeper(null);
                return 0;
            case "off":
            case "stop":
                Console.WriteLine(StopKeeper() ? "awake: off" : "awake: already off");
                return 0;
            case "status":
            case "st":
                ShowStatus();
                return 0;
            case "on":
            case "start":
                if (rest == "") { StartKeeper(null); return 0; }
                return StartFromSpec(rest);
            case "help":
            case "-h":
            case "--help":
            case "-help":
            case "/?":
            case "?":
                Console.WriteLine(HelpText());
                return 0;
            case "version":
            case "-v":
            case "--version":
                Console.WriteLine("awake " + Version);
                return 0;
            default:
                return StartFromSpec(string.Join(" ", args));
        }
    }

    static string HelpText()
    {
        return "awake " + Version + " - keep this PC and its display awake\n" +
            "\n" +
            "Usage:\n" +
            "  awake               toggle on (indefinitely) / off\n" +
            "  awake <duration>    stay awake for a while:   90  45m  2h  1h30m  1d\n" +
            "  awake <time>        stay awake until a time:  17:30  5pm  5:30pm\n" +
            "  awake off           turn off\n" +
            "  awake status        show whether awake is on, and until when\n" +
            "  awake help          show this help\n" +
            "\n" +
            "Giving a duration or time while awake is already on replaces the old timer.";
    }

    static int StartFromSpec(string spec)
    {
        DateTime? until = ParseDeadline(spec);
        if (until == null)
        {
            Console.Error.WriteLine("awake: can't understand '" + spec + "'\n");
            Console.Error.WriteLine(HelpText());
            return 1;
        }
        StartKeeper(until);
        return 0;
    }

    // Returns the local time to stay awake until, or null if the text isn't a valid spec.
    static DateTime? ParseDeadline(string text)
    {
        string t = Regex.Replace(text.Trim().ToLowerInvariant(), @"\s+", "");
        DateTime now = DateTime.Now;
        Match m;

        // Plain number = minutes
        if (Regex.IsMatch(t, @"^\d{1,6}$")) return now.AddMinutes(int.Parse(t));

        // Duration: 1d2h30m15s, any subset, in that order
        m = Regex.Match(t, @"^(?:(\d{1,4})d)?(?:(\d{1,4})h)?(?:(\d{1,6})m(?:in)?)?(?:(\d{1,6})s)?$");
        if (m.Success && t != "")
        {
            TimeSpan span = new TimeSpan(Num(m, 1), Num(m, 2), Num(m, 3), Num(m, 4));
            return span.TotalSeconds > 0 ? now.Add(span) : (DateTime?)null;
        }

        // Clock time: 17:30, 5pm, 5:30pm, 12am
        m = Regex.Match(t, @"^(\d{1,2})(?::(\d{2}))?(am|pm)?$");
        if (m.Success && (m.Groups[2].Success || m.Groups[3].Success))
        {
            int hour = Num(m, 1), min = Num(m, 2);
            string ampm = m.Groups[3].Value;
            if (ampm != "")
            {
                if (hour < 1 || hour > 12) return null;
                if (hour == 12) hour = 0;
                if (ampm == "pm") hour += 12;
            }
            if (hour > 23 || min > 59) return null;
            DateTime when = now.Date.AddHours(hour).AddMinutes(min);
            if (when <= now) when = when.AddDays(1);
            return when;
        }

        return null;
    }

    static int Num(Match m, int group)
    {
        return m.Groups[group].Success ? int.Parse(m.Groups[group].Value) : 0;
    }

    static string FormatSpan(TimeSpan span)
    {
        if (span.TotalSeconds < 1) return "<1m";
        // Round up to the minute so "awake 2h" reports 2h, not 1h 59m.
        span = TimeSpan.FromMinutes(Math.Ceiling(span.TotalMinutes));
        string s = "";
        if (span.Days > 0) s += span.Days + "d ";
        if (span.Hours > 0) s += span.Hours + "h ";
        if (span.Minutes > 0) s += span.Minutes + "m ";
        return s.TrimEnd();
    }

    static string FormatWhen(DateTime when)
    {
        return when.ToString(when.Date == DateTime.Today ? "HH:mm" : "ddd HH:mm");
    }

    // Returns the running keeper's state, or null (cleaning up stale state).
    static State GetKeeper()
    {
        if (!File.Exists(StateFile)) return null;
        try
        {
            State s = new State();
            foreach (string line in File.ReadAllLines(StateFile))
            {
                int eq = line.IndexOf('=');
                if (eq < 0) continue;
                string key = line.Substring(0, eq), val = line.Substring(eq + 1);
                if (key == "pid") s.Pid = int.Parse(val);
                else if (key == "startTicks") s.StartTicks = long.Parse(val);
                else if (key == "since") s.Since = new DateTime(long.Parse(val), DateTimeKind.Utc).ToLocalTime();
                else if (key == "until" && val != "") s.Until = new DateTime(long.Parse(val), DateTimeKind.Utc).ToLocalTime();
            }
            using (Process p = Process.GetProcessById(s.Pid))
            {
                // Guard against PID reuse by comparing process start times.
                if (p.StartTime.ToUniversalTime().Ticks == s.StartTicks) return s;
            }
        }
        catch (Exception) { }
        TryDelete(StateFile);
        return null;
    }

    static bool StopKeeper()
    {
        State s = GetKeeper();
        if (s == null) return false;
        try
        {
            using (Process p = Process.GetProcessById(s.Pid)) { p.Kill(); p.WaitForExit(5000); }
        }
        catch (Exception) { }
        TryDelete(StateFile);
        return true;
    }

    static void StartKeeper(DateTime? until)
    {
        StopKeeper();
        Directory.CreateDirectory(StateDir);

        long untilTicks = until.HasValue ? until.Value.ToUniversalTime().Ticks : 0;
        string exe = Process.GetCurrentProcess().MainModule.FileName;
        ProcessStartInfo psi = new ProcessStartInfo(exe, "__keep " + untilTicks);
        // ShellExecute doesn't hand our console handles to the child, so it
        // outlives this terminal and never holds a caller's output pipe open.
        psi.UseShellExecute = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        using (Process p = Process.Start(psi))
        {
            File.WriteAllLines(StateFile, new string[] {
                "pid=" + p.Id,
                "startTicks=" + p.StartTime.ToUniversalTime().Ticks,
                "since=" + DateTime.UtcNow.Ticks,
                "until=" + (until.HasValue ? untilTicks.ToString() : ""),
            });
        }

        if (until.HasValue)
            Console.WriteLine("awake: on until " + FormatWhen(until.Value) + " (" +
                FormatSpan(until.Value - DateTime.Now) + "). Run 'awake' again to turn off.");
        else
            Console.WriteLine("awake: on indefinitely. Run 'awake' again to turn off.");
    }

    static void ShowStatus()
    {
        State s = GetKeeper();
        if (s == null)
            Console.WriteLine("awake: off");
        else if (s.Until.HasValue)
            Console.WriteLine("awake: on until " + FormatWhen(s.Until.Value) + " (" +
                FormatSpan(s.Until.Value - DateTime.Now) + " left)");
        else
            Console.WriteLine("awake: on indefinitely (since " + FormatWhen(s.Since) + ")");
    }

    // Runs inside the hidden background process.
    static void Keep(long untilTicks)
    {
        try
        {
            while (true)
            {
                SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
                if (untilTicks == 0) { Thread.Sleep(30000); continue; }
                long left = untilTicks - DateTime.UtcNow.Ticks;
                if (left <= 0) break;
                Thread.Sleep((int)Math.Min(30000, (left + 9999) / 10000));
            }
        }
        finally
        {
            SetThreadExecutionState(ES_CONTINUOUS);
            // Only clear the state file if it still belongs to this process.
            State s = GetKeeper();
            if (s != null && s.Pid == Process.GetCurrentProcess().Id) TryDelete(StateFile);
        }
    }

    static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (Exception) { }
    }
}
