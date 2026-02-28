#!/bin/bash
# ============================================================
# record_traces.sh — Record strace for all ts-* services
# PIDs are discovered via the kind control-plane container
# using nsenter + crictl to find the real host PIDs of
# Java processes running inside Kubernetes pods.
# ============================================================
set -euo pipefail

SCENARIO="${1:-normal}"
BASE_DIR="/home/sehgaluv17/lttng-final-traces"
OUT_DIR="$BASE_DIR/$SCENARIO"
LOG_FILE="$OUT_DIR/strace.log"
META_FILE="$OUT_DIR/meta.json"
LOAD_DIR="/home/sehgaluv17/train-ticket-auto-query"
LOAD_VENV="$LOAD_DIR/venv/bin/activate"
NAMESPACE="${TS_NAMESPACE:-ts}"

# The kind control-plane container name
KIND_CONTAINER="train-ticket-control-plane"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

mkdir -p "$OUT_DIR"

# ── Discover ts-* service PIDs via the kind container ────────────────────────
# Services run inside containers inside the kind node, not directly on the host.
# We use `docker exec` into the kind node, then use `crictl` to list containers
# and `cat /proc/<pid>/cmdline` to find Java ts-*.jar processes.
# The PIDs reported by `crictl inspect` are the HOST-visible PIDs (shared
# pid namespace between kind node and host on Linux), so strace can attach.
log "▶ Discovering ts-* service PIDs via kind container..."

mapfile -t SERVICE_PIDS < <(
    docker exec "$KIND_CONTAINER" bash -c '
        crictl ps --output json 2>/dev/null \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get(\"containers\", []):
    name = c.get(\"metadata\", {}).get(\"name\", \"\")
    if name.startswith(\"ts-\"):
        cid = c[\"id\"]
        print(cid)
"
    ' | while read -r cid; do
        docker exec "$KIND_CONTAINER" bash -c \
            "crictl inspect --output json $cid 2>/dev/null \
             | python3 -c \"import json,sys; d=json.load(sys.stdin); print(d.get('info',{}).get('pid',''))\"" \
        2>/dev/null
    done | grep -E '^[0-9]+$' | sort -u
)

if [ ${#SERVICE_PIDS[@]} -eq 0 ]; then
    # Fallback: scan /proc directly on the host for java ts-*.jar processes
    log "   crictl method found 0 PIDs — falling back to /proc scan..."
    mapfile -t SERVICE_PIDS < <(
        for pid in /proc/[0-9]*/cmdline; do
            pid_num=$(echo "$pid" | grep -oP '\d+')
            cmdline=$(tr '\0' ' ' < "$pid" 2>/dev/null || true)
            if echo "$cmdline" | grep -qP 'ts-[a-z-]+\.jar'; then
                echo "$pid_num"
            fi
        done | sort -u
    )
fi

if [ ${#SERVICE_PIDS[@]} -eq 0 ]; then
    log "❌ ERROR: No ts-* service processes found."
    log "   Check: kubectl get pods -n $NAMESPACE"
    log "   Check: docker exec $KIND_CONTAINER crictl ps"
    exit 1
fi

# ── Build PID → service name map ─────────────────────────────────────────────
declare -A PID_TO_SERVICE
for pid in "${SERVICE_PIDS[@]}"; do
    svc=$(cat "/proc/$pid/cmdline" 2>/dev/null \
          | tr '\0' ' ' \
          | grep -oP 'ts-[a-z0-9-]+(?=\.jar)' \
          | head -1 || true)
    [ -n "$svc" ] && PID_TO_SERVICE[$pid]="$svc" || PID_TO_SERVICE[$pid]="unknown"
done

log "============================================"
log " SCENARIO : $SCENARIO"
log " OUTPUT   : $OUT_DIR"
log " SERVICES : ${#SERVICE_PIDS[@]}"
log "============================================"
for pid in "${SERVICE_PIDS[@]}"; do
    printf "   %6s  %s\n" "$pid" "${PID_TO_SERVICE[$pid]}"
done
log "============================================"

# ── Build strace -p args ──────────────────────────────────────────────────────
P_ARGS=$(printf -- '-p %s ' "${SERVICE_PIDS[@]}")

# ── Write initial metadata ────────────────────────────────────────────────────
START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PID_JSON=$(printf '"%s",' "${SERVICE_PIDS[@]}" | sed 's/,$//')
PID_MAP_PY=""
for pid in "${!PID_TO_SERVICE[@]}"; do
    PID_MAP_PY+="d['$pid']='${PID_TO_SERVICE[$pid]}'; "
done

python3 - <<PYEOF
import json
d = {}
${PID_MAP_PY}
m = {
    'scenario':      '$SCENARIO',
    'start_time':    '$START_TS',
    'log_file':      '$LOG_FILE',
    'service_count': ${#SERVICE_PIDS[@]},
    'pids':          [${PID_JSON}],
    'pid_map':       d,
}
with open('$META_FILE', 'w') as f:
    json.dump(m, f, indent=2)
PYEOF

# ── Start strace ──────────────────────────────────────────────────────────────
log "▶ Starting strace on ${#SERVICE_PIDS[@]} services..."
sudo strace $P_ARGS \
    -f \
    -tt \
    -T \
    -e trace=network,read,write,futex,clone,execve \
    -o "$LOG_FILE" &
STRACE_PID=$!
log "   strace PID: $STRACE_PID"
sleep 2   # let strace attach before traffic starts

# ── Run load ──────────────────────────────────────────────────────────────────
# normal scenario  → minimal mode (read-only, low pressure)
# anomaly scenario → minimal mode still (we want load but not overwhelming)
# Use the updated generateload.sh from train-ticket-auto-query
LOAD_MODE="minimal"
log "▶ Running load: generateload.sh $LOAD_MODE"
cd "$LOAD_DIR"
# shellcheck disable=SC1090
source "$LOAD_VENV"
bash generateload.sh "$LOAD_MODE"
LOAD_EXIT=$?

# ── Stop strace ───────────────────────────────────────────────────────────────
log "▶ Stopping strace..."
sudo kill "$STRACE_PID" 2>/dev/null || true
wait "$STRACE_PID" 2>/dev/null || true

# ── Update metadata with final stats ─────────────────────────────────────────
END_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LINE_COUNT=$(wc -l < "$LOG_FILE")
FILE_SIZE=$(du -sh "$LOG_FILE" | cut -f1)

python3 - <<PYEOF
import json
with open('$META_FILE') as f:
    m = json.load(f)
m['end_time']   = '$END_TS'
m['line_count'] = $LINE_COUNT
m['file_size']  = '$FILE_SIZE'
m['load_exit']  = $LOAD_EXIT
with open('$META_FILE', 'w') as f:
    json.dump(m, f, indent=2)
PYEOF

log ""
log "============================================"
log " ✅ Done — $SCENARIO"
log "    Lines : $LINE_COUNT"
log "    Size  : $FILE_SIZE"
log "    File  : $LOG_FILE"
log "============================================"
