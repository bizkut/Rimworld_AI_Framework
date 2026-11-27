using System;
using RimWorld;
using Verse;

namespace RimAI.Agent.TestBed
{
    /// <summary>
    /// T0 test bed (docs/plan/07): heartbeat every in-game hour, telemetry every in-game day,
    /// and unattended-run control from command-line flags:
    ///   -rimai-autorun                 unpause when a game starts and keep the run speed
    ///   -rimai-speed=normal|fast|superfast|ultrafast   run speed (default: ultrafast in dev mode, else superfast)
    ///   -rimai-days=N                  log "RUN COMPLETE" and quit once N in-game days have passed
    ///   -rimai-rimmind-full            set every RimMind autonomy domain to FullAutonomous (trial runs)
    /// All log lines start with "[RimAI.Agent]" so scripts/run-colony.sh can grep them.
    /// </summary>
    public static class RunControl
    {
        private const string Prefix = "[RimAI.Agent]";
        private static int _startTick = -1;
        private static int _maxDays = -1;
        private static bool _autorun;
        private static bool _rimMindFull;
        private static bool _finished;
        private static TimeSpeed _speed;

        /// <summary>Reads flags and starts the run. Called from AgentGameComponent.FinalizeInit (new or loaded game).</summary>
        public static void OnGameStarted()
        {
            _startTick = Find.TickManager.TicksGame;
            _finished = false;
            _autorun = GenCommandLine.CommandLineArgPassed("rimai-autorun");
            _rimMindFull = GenCommandLine.CommandLineArgPassed("rimai-rimmind-full");
            _maxDays = GenCommandLine.TryGetCommandLineArg("rimai-days", out string days) && int.TryParse(days, out int n) && n > 0 ? n : -1;
            _speed = ParseSpeed();

            Log.Message($"{Prefix} game started tick={_startTick} autorun={_autorun} speed={_speed} maxDays={_maxDays} rimmindFull={_rimMindFull}");
            if (_autorun)
            {
                // Unattended runs only: hostiles on the map would otherwise force 1x speed (TimeSlower),
                // and an unfocused window would otherwise throttle Unity's frame loop (runtime only; Prefs untouched).
                DebugViewSettings.neverForceNormalSpeed = true;
                UnityEngine.Application.runInBackground = true;
                EnforceSpeed();
            }
            if (_rimMindFull) RimMindTrial.ApplyFullAutonomy();
            Log.Message(Telemetry.Line(0));
        }

        /// <summary>Called every frame (also while paused): re-applies the autorun speed after auto-pauses.</summary>
        public static void Update()
        {
            if (_autorun && !_finished && _startTick >= 0) EnforceSpeed();
        }

        private static TimeSpeed ParseSpeed()
        {
            // Ultrafast is only selectable in dev mode.
            var fallback = Prefs.DevMode ? TimeSpeed.Ultrafast : TimeSpeed.Superfast;
            if (!GenCommandLine.TryGetCommandLineArg("rimai-speed", out string s)) return fallback;
            if (!Enum.TryParse(s, ignoreCase: true, out TimeSpeed speed) || speed == TimeSpeed.Paused)
            {
                Log.Warning($"{Prefix} unknown -rimai-speed={s}; using {fallback}");
                return fallback;
            }
            return speed == TimeSpeed.Ultrafast && !Prefs.DevMode ? TimeSpeed.Superfast : speed;
        }

        private static void EnforceSpeed()
        {
            if (Find.TickManager.CurTimeSpeed != _speed) Find.TickManager.CurTimeSpeed = _speed;
        }

        /// <summary>Called every game tick (only while unpaused).</summary>
        public static void Tick(int ticksGame)
        {
            if (_startTick < 0 || _finished) return;
            int elapsed = ticksGame - _startTick;
            if (elapsed <= 0) return;

            if (elapsed % GenDate.TicksPerDay == 0)
            {
                int day = elapsed / GenDate.TicksPerDay;
                Log.Message(Telemetry.Line(day));
                if (_maxDays > 0 && day >= _maxDays)
                {
                    _finished = true;
                    Log.Message($"{Prefix} RUN COMPLETE days={day}");
                    Root.Shutdown();
                }
            }
            else if (elapsed % GenDate.TicksPerHour == 0)
            {
                Log.Message($"{Prefix} heartbeat hour={elapsed / GenDate.TicksPerHour}");
                // New colonists (wanderers, rescues) get the trial policy too.
                if (_rimMindFull) RimMindTrial.ApplyFullAutonomy();
            }
        }
    }
}
