#!/bin/bash
# ============================================================
# record_all.sh — Record ALL scenarios sequentially
# Runs: normal, cpu-stress, memory-stress, io-stress,
#       bandwidth, db-load, pod-restart, verbose-log
#
# Usage: ./record_all.sh [--force]
#   --force  Re-record even if a trace already exists
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
BASE_DIR="/home/sehgaluv17/lttng-final-traces"
COOLDOWN=30   # seconds between scenarios to let JVMs recover
FORCE=false

if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

SCENARIOS=(
    normal
    cpu-stress
    memory-stress
    io-stress
    bandwidth
    db-load
    pod-restart
    verbose-log
)
TOTAL=${#SCENARIOS[@]}

# ── Pre-flight skip check ─────────────────────────────────────────────────────
SKIP=()
for s in "${SCENARIOS[@]}"; do
    if [ -f "$BASE_DIR/$s/strace.log" ] && [ "$FORCE" = false ]; then
        SKIP+=("$s")
    fi
done

if [ ${#SKIP[@]} -gt 0 ]; then
    log "⚠️  The following scenarios already have traces (use --force to re-record):"
    for s in "${SKIP[@]}"; do
        SIZE=$(du -sh "$BASE_DIR/$s/strace.log" 2>/dev/null | cut -f1 || echo '?')
        log "      $s  ($SIZE)"
    done
fi

# ── Helper: run one scenario ──────────────────────────────────────────────────
run_scenario() {
    local SCENARIO="$1"
    local N="$2"
    local IS_ANOMALY="${3:-false}"

    # Skip if trace exists and not forcing
    if [ -f "$BASE_DIR/$SCENARIO/strace.log" ] && [ "$FORCE" = false ]; then
        log "⏭  Skipping '$SCENARIO' — trace exists (delete or use --force to re-record)"
        return 0
    fi

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "SCENARIO $N/$TOTAL — $SCENARIO"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$IS_ANOMALY" = true ]; then
        log "  Injecting anomaly: $SCENARIO"
        bash "$SCRIPT_DIR/inject_anomaly.sh" start "$SCENARIO"
        sleep 5   # let anomaly stabilise before strace starts
    fi

    # Record — do not abort the whole run if one scenario fails
    bash "$SCRIPT_DIR/record_traces.sh" "$SCENARIO" || {
        log "  ⚠️  record_traces.sh exited non-zero for '$SCENARIO' — continuing"
    }

    if [ "$IS_ANOMALY" = true ]; then
        log "  Stopping anomaly..."
        bash "$SCRIPT_DIR/inject_anomaly.sh" stop
    fi

    log "  Cooldown ${COOLDOWN}s (letting JVMs recover)..."
    sleep "$COOLDOWN"
}

# ── Run all scenarios ─────────────────────────────────────────────────────────
run_scenario "normal"        1 false
run_scenario "cpu-stress"    2 true
run_scenario "memory-stress" 3 true
run_scenario "io-stress"     4 true
run_scenario "bandwidth"     5 true
run_scenario "db-load"       6 true
run_scenario "pod-restart"   7 true
run_scenario "verbose-log"   8 true

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           RECORDING COMPLETE                 ║"
echo "╠══════════════════════════════════════════════╣"
for s in "${SCENARIOS[@]}"; do
    LOG="$BASE_DIR/$s/strace.log"
    if [ -f "$LOG" ]; then
        SIZE=$(du -sh "$LOG" | cut -f1)
        LINES=$(wc -l < "$LOG")
        printf "║  %-22s  %6s  %8d lines  ║\n" "$s" "$SIZE" "$LINES"
    else
        printf "║  %-22s  %-20s  ║\n" "$s" "MISSING"
    fi
done
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Next step: python3 $SCRIPT_DIR/parse_strace.py --scenario <name>"
