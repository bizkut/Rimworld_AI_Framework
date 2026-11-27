using System;
using System.Linq;
using System.Reflection;
using RimWorld;
using Verse;

namespace RimAI.Agent.TestBed
{
    /// <summary>
    /// Evaluation hook for comparing against the RimMind mod suite (docs/plan/07 M7). With -rimai-rimmind-full,
    /// sets every RimMind autonomy domain to FullAutonomous on every colonist so no action waits for a player
    /// approval that never comes in an unattended run. Bound by reflection: RimAI.Agent has no compile-time
    /// dependency on RimMind and this is a no-op when RimMind is not loaded.
    /// </summary>
    public static class RimMindTrial
    {
        private const string Prefix = "[RimAI.Agent]";
        private static int _lastPawnCount = -1;

        public static void ApplyFullAutonomy()
        {
            Type api = FindType("RimMind.Presentation.Api.RimMindAPI+Autonomy");
            Type domainType = FindType("RimMind.Domain.Agent.Policies.AutonomyDomain");
            Type levelType = FindType("RimMind.Domain.Agent.Policies.AutonomyLevel");
            MethodInfo setLevel = api?.GetMethod("SetLevel", new[] { typeof(Pawn), domainType, levelType });
            if (setLevel == null)
            {
                if (_lastPawnCount != 0) Log.Warning($"{Prefix} rimmind autonomy hook: RimMind API not found");
                _lastPawnCount = 0;
                return;
            }

            object full = Enum.Parse(levelType, "FullAutonomous");
            Array domains = Enum.GetValues(domainType);
            var colonists = PawnsFinder.AllMaps_FreeColonistsSpawned;
            foreach (Pawn pawn in colonists)
                foreach (object domain in domains)
                    setLevel.Invoke(null, new[] { pawn, domain, full });

            if (colonists.Count != _lastPawnCount)
            {
                _lastPawnCount = colonists.Count;
                Log.Message($"{Prefix} rimmind autonomy=FullAutonomous pawns={colonists.Count} domains={domains.Length}");
            }
        }

        private static Type FindType(string fullName) =>
            AppDomain.CurrentDomain.GetAssemblies()
                .Select(a => a.GetType(fullName, throwOnError: false))
                .FirstOrDefault(t => t != null);
    }
}
