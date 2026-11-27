#!/usr/bin/env bash
# M7 evaluation: can the RimMind suite play a fresh colony unattended? Builds RimMind-Core/Actions/Advisor from
# ../RimMind (staged copies; the source checkouts are not modified), installs them, points them at the local
# OpenAI-compatible proxy with full autonomy, then runs the same quick-test colony twice through run-colony.sh:
# a no-AI baseline and the RimMind trial. Compare the [RimAI.Agent] telemetry lines of the two logs. macOS.
#
# usage: scripts/rimmind-trial.sh [DAYS=3] [TIMEOUT_MIN=60] [SPEED=fast]
# env:   RIMWORLD_DIR, RIMMIND_SRC (default ../RimMind), RIMMIND_ENDPOINT (default http://127.0.0.1:8787/v1),
#        RIMMIND_MODEL (default beam-free), SKIP_BASELINE=1 to run only the trial
set -euo pipefail

DAYS=${1:-3}
TIMEOUT_MIN=${2:-60}
SPEED=${3:-fast}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RW=${RIMWORLD_DIR:-/Applications/RimWorld.app}
SRC=${RIMMIND_SRC:-$ROOT/../RimMind}
ENDPOINT=${RIMMIND_ENDPOINT:-http://127.0.0.1:8787/v1}
MODEL=${RIMMIND_MODEL:-beam-free}
CFG="$HOME/Library/Application Support/RimWorld/Config"
STAGE="$ROOT/.runs/rimmind-build"
MODULES="Core Actions Advisor"
PACKAGES="mcocdaa.RimMindCore mcocdaa.RimMindActions mcocdaa.RimMindAdvisor"

say() { echo "[rimmind-trial] $*"; }

# 1. Proxy must answer before we spend a run on it.
curl -sf -m 10 "$ENDPOINT/models" >/dev/null || { say "endpoint $ENDPOINT not reachable"; exit 1; }

# 2. Stage + build. Submodules reference Core via ../../RimMind-Core/1.6/Assemblies, so staged folders use those names.
mkdir -p "$STAGE"
for m in $MODULES; do
    rsync -a --delete --exclude .git --exclude bin --exclude obj --exclude 1.6 --exclude 1.7 \
        "$SRC/RimWorld-RimMind-Mod-$m/" "$STAGE/RimMind-$m/"
done
for m in $MODULES; do
    proj=$(ls "$STAGE/RimMind-$m/Source/"*.csproj | grep -v -E "Domain|Application" | head -1)
    say "building RimMind-$m ($(basename "$proj"))"
    if ! dotnet build "$proj" -c Release -nologo -v q -p:GameVersion=1.6 > "$STAGE/build-$m.log" 2>&1; then
        grep -E "error" "$STAGE/build-$m.log" | sort -u | head -20; say "build failed: RimMind-$m"; exit 1
    fi
    [ -d "$STAGE/RimMind-$m/1.6/Assemblies" ] || { say "no 1.6/Assemblies for RimMind-$m"; exit 1; }
done

# 3. Install mod content (no sources/tests) into Mods/RimMind-*.
for m in $MODULES; do
    dst="$RW/Mods/RimMind-$m"
    mkdir -p "$dst"
    rsync -a --delete --include "/About/***" --include "/Defs/***" --include "/Languages/***" --include "/Textures/***" \
        --include "/1.6/***" --include "/LoadFolders.xml" --exclude "*" "$STAGE/RimMind-$m/" "$dst/"
done
say "installed: $(ls -d "$RW"/Mods/RimMind-* | xargs -n1 basename | tr '\n' ' ')"

# 4. Preset settings (file = Mod_<ModFolder>_<ModClass>.xml). The key is a placeholder for the keyless proxy,
#    stored the way RimMind does (UTF-8 XOR 0x5A, base64). maxTokens 4096: reasoning models spend small budgets thinking.
KEY=$(python3 -c 'import base64;print(base64.b64encode(bytes(b^0x5A for b in b"sk-local")).decode())')
cat > "$CFG/Mod_RimMind-Core_RimMindCoreMod.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<SettingsBlock>
  <ModSettings Class="RimMind.Presentation.Settings.RimMindCoreSettings">
    <provider>openai</provider>
    <apiKey>$KEY</apiKey>
    <apiEndpoint>$ENDPOINT</apiEndpoint>
    <modelName>$MODEL</modelName>
    <maxTokens>4096</maxTokens>
    <requestTimeoutMs>120000</requestTimeoutMs>
    <autoActivateColonistAgents>True</autoActivateColonistAgents>
    <autonomyLevel>Full</autonomyLevel>
    <debugLogging>True</debugLogging>
  </ModSettings>
</SettingsBlock>
XML
cat > "$CFG/Mod_RimMind-Advisor_RimMindAdvisorMod.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<SettingsBlock>
  <ModSettings Class="RimMind.Advisor.Settings.RimMindAdvisorSettings">
    <enableAdvisor>True</enableAdvisor>
    <enableRiskApproval>False</enableRiskApproval>
  </ModSettings>
</SettingsBlock>
XML

# 5. Baseline (no AI) then trial, same days and speed.
if [ "${SKIP_BASELINE:-0}" != 1 ]; then
    say "baseline run (vanilla colonists, no AI)"
    RUN_LABEL=baseline RUN_ARGS="-rimai-speed=$SPEED" "$ROOT/scripts/run-colony.sh" "$DAYS" "$TIMEOUT_MIN" || say "baseline run did not complete cleanly"
fi
say "RimMind trial run ($MODEL via $ENDPOINT)"
EXTRA_MODS="$PACKAGES" RUN_LABEL=rimmind RUN_ARGS="-rimai-speed=$SPEED -rimai-rimmind-full" \
    "$ROOT/scripts/run-colony.sh" "$DAYS" "$TIMEOUT_MIN" || say "trial run did not complete cleanly"

# 6. Summary: RimMind activity in the trial log.
LOG=$(ls -t "$ROOT"/.runs/*-rimmind.log | head -1)
say "trial log: $LOG"
say "RimMind log lines: $(grep -c "RimMind" "$LOG" || true); autonomy hook: $(grep "rimmind autonomy" "$LOG" | tail -1)"
