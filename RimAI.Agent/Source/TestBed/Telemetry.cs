using System.Linq;
using RimWorld;
using Verse;

namespace RimAI.Agent.TestBed
{
    /// <summary>
    /// One-line colony scoreboard for unattended runs (docs/plan/07 T0/M7). Main thread only.
    /// Format: [RimAI.Agent] telemetry day=D colonists=N downed=N foodDays=F mood=M wealth=W research=R fires=N threats=N
    /// </summary>
    public static class Telemetry
    {
        /// <summary>Nutrition one colonist eats per day (RimWorld baseline, ~1.6).</summary>
        private const float NutritionPerColonistDay = 1.6f;

        public static string Line(int day)
        {
            Map map = Find.AnyPlayerHomeMap;
            if (map == null) return $"[RimAI.Agent] telemetry day={day} map=none";

            var colonists = map.mapPawns.FreeColonistsSpawned;
            int alive = colonists.Count;
            int downed = colonists.Count(p => p.Downed);
            // All human-edible food on the map, forbidden included (drop-pod starting items arrive forbidden;
            // resourceCounter only counts stockpiled items).
            float nutrition = map.listerThings.ThingsInGroup(ThingRequestGroup.FoodSourceNotPlantOrTree)
                .Where(t => !(t is Corpse) && t.def.IsNutritionGivingIngestible && t.def.ingestible.HumanEdible)
                .Sum(t => t.GetStatValue(StatDefOf.Nutrition) * t.stackCount);
            float foodDays = alive > 0 ? nutrition / (alive * NutritionPerColonistDay) : 0f;
            var moods = colonists.Where(p => p.needs?.mood != null).Select(p => p.needs.mood.CurLevelPercentage).ToList();
            float mood = moods.Count > 0 ? moods.Average() : 0f;
            float wealth = map.wealthWatcher.WealthTotal;
            int research = DefDatabase<ResearchProjectDef>.AllDefsListForReading.Count(r => r.IsFinished);
            int fires = map.listerThings.ThingsOfDef(ThingDefOf.Fire).Count;
            int threats = map.mapPawns.AllPawnsSpawned.Count(p => !p.Dead && !p.Downed && p.HostileTo(Faction.OfPlayer));

            return $"[RimAI.Agent] telemetry day={day} colonists={alive} downed={downed} foodDays={foodDays:F1} mood={mood:F2} wealth={wealth:F0} research={research} fires={fires} threats={threats}";
        }
    }
}
