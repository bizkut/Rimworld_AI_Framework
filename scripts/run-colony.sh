#!/usr/bin/env bash
# T0 test bed (docs/plan/07): build + deploy, boot a fresh RimWorld quick-test colony unattended,
# run N in-game days at max speed, quit, and print the telemetry scoreboard. macOS.
#
# usage: scripts/run-colony.sh [DAYS=3] [TIMEOUT_MIN=30]
# env:   RIMWORLD_DIR (default /Applications/RimWorld.app), HARMONY_SRC (default ../HarmonyRimWorld)
#        EXTRA_MODS  space-separated packageIds loaded after official content, before RimAI (e.g. an AI suite under test)
#        RUN_ARGS    extra game arguments (e.g. "-rimai-speed=fast -rimai-rimmind-full")
#        RUN_LABEL   label used in the saved log name (default "run")
# exit:  0 when the run logged "RUN COMPLETE" with no exceptions, 1 otherwise.
set -euo pipefail

DAYS=${1:-3}
TIMEOUT_MIN=${2:-30}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RW=${RIMWORLD_DIR:-/Applications/RimWorld.app}
HARMONY_SRC=${HARMONY_SRC:-$ROOT/../HarmonyRimWorld}
CFG="$HOME/Library/Application Support/RimWorld/Config"
LOG="$HOME/Library/Logs/Ludeon Studios/RimWorld by Ludeon Studios/Player.log"
RUNS="$ROOT/.runs"

say() { echo "[run-colony] $*"; }

# 1. Stop any running game so the build can replace mod files.
pkill -f "$RW/Contents/MacOS/" 2>/dev/null && sleep 3 || true

# 2. Build + deploy Framework and Agent. A failed build is fatal (stale DLLs would fake a pass).
mkdir -p "$RUNS"
for proj in RimAI.Framework/RimAI.Framework.csproj RimAI.Agent/RimAI.Agent.csproj; do
    say "building $proj"
    if ! RIMWORLD_DIR="$RW" dotnet build "$ROOT/$proj" -c Release -nologo -v q > "$RUNS/build.log" 2>&1; then
        grep -E "error" "$RUNS/build.log" | sort -u | head -20; say "build failed: $proj"; exit 1
    fi
done
[ -f "$RW/Mods/RimAI_Framework/Assemblies/RimAI.Framework.dll" ] || { say "Framework not deployed"; exit 1; }
[ -f "$RW/Mods/RimAI_Agent/Assemblies/RimAI.Agent.dll" ] || { say "Agent not deployed"; exit 1; }

# 3. Install Harmony (brrainz.harmony) for RimWorld 1.6.
[ -f "$HARMONY_SRC/1.6/Assemblies/0Harmony.dll" ] || { say "Harmony build not found at $HARMONY_SRC/1.6"; exit 1; }
mkdir -p "$RW/Mods/Harmony"
rsync -a --delete "$HARMONY_SRC/About" "$HARMONY_SRC/1.6" "$HARMONY_SRC/LoadFolders.xml" "$RW/Mods/Harmony/"

# 4. Enable mods in load order: Harmony, official content, EXTRA_MODS, Framework, Agent. Nothing else stays
#    active, so a baseline run cannot inherit mods from a previous trial.
[ -f "$CFG/ModsConfig.xml.bak-rimai" ] || cp "$CFG/ModsConfig.xml" "$CFG/ModsConfig.xml.bak-rimai"
python3 - "$CFG/ModsConfig.xml" ${EXTRA_MODS:-} <<'PY'
import sys, xml.etree.ElementTree as ET
path, extra = sys.argv[1], [m.lower() for m in sys.argv[2:]]
tree = ET.parse(path)
active = tree.getroot().find("activeMods")
ids = [li.text.strip().lower() for li in active.findall("li")]
official = [i for i in ids if i.startswith("ludeon.")]
order = ["brrainz.harmony"] + official + extra + ["kilokio.rimai.framework", "kilokio.rimai.agent"]
for li in list(active):
    active.remove(li)
for i in order:
    ET.SubElement(active, "li").text = i
tree.write(path, encoding="utf-8", xml_declaration=True)
print("[run-colony] activeMods:", ", ".join(order))
PY

# 5. Launch a fresh quick-test colony, unattended.
mkdir -p "$RUNS"
STAMP=$(date +%Y%m%d-%H%M%S)-${RUN_LABEL:-run}
START=$(date +%s)
say "launching quick-test colony for $DAYS in-game day(s), timeout ${TIMEOUT_MIN}m, args: ${RUN_ARGS:-none}"
# shellcheck disable=SC2086  # RUN_ARGS is intentionally word-split into separate arguments
open -n -a "$RW" --args -quicktest -rimai-autorun "-rimai-days=$DAYS" ${RUN_ARGS:-}

# 6. Wait for RUN COMPLETE, game exit, or timeout (Player.log is rewritten on launch).
sleep 10
while :; do
    if [ -f "$LOG" ] && [ "$(stat -f %m "$LOG")" -ge "$START" ] && grep -q "\[RimAI.Agent\] RUN COMPLETE" "$LOG"; then
        break
    fi
    if ! pgrep -f "$RW/Contents/MacOS/" >/dev/null; then say "game exited"; break; fi
    if [ $(( $(date +%s) - START )) -ge $(( TIMEOUT_MIN * 60 )) ]; then
        say "timeout; stopping game"; pkill -f "$RW/Contents/MacOS/" || true; break
    fi
    sleep 5
done
sleep 2
cp "$LOG" "$RUNS/$STAMP.log"

# 7. Report.
say "log: $RUNS/$STAMP.log"
grep -E "\[RimAI.Agent\] (game started|telemetry|RUN COMPLETE)" "$RUNS/$STAMP.log" || true
EXC=$(grep -c "Exception" "$RUNS/$STAMP.log" || true)
say "exceptions: $EXC"
grep -q "\[RimAI.Agent\] RUN COMPLETE" "$RUNS/$STAMP.log" && [ "$EXC" -eq 0 ]
