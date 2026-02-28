#!/bin/bash
# ============================================================
# inject_anomaly.sh — Inject various anomaly conditions
# Usage:
#   bash inject_anomaly.sh start <scenario>
#   bash inject_anomaly.sh stop
#
# Scenarios: cpu-stress, memory-stress, io-stress,
#            bandwidth, db-load, pod-restart, verbose-log
# ============================================================

set -euo pipefail

CMD="${1:-start}"
SCENARIO="${2:-}"
CLEANUP_FILE="/tmp/anomaly_cleanup_pids"
NAMESPACE="${TS_NAMESPACE:-ts}"

# MySQL pod and credentials matching the Train Ticket kind deployment
MYSQL_POD="tsdb-mysql-leader-0"
MYSQL_USER="root"
MYSQL_PASS="${MYSQL_ROOT_PASSWORD:-Abcd1234#}"
MYSQL_DB="ts"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

start_cpu_stress() {
    log "🔥 Starting CPU stress (all cores, 85% load)..."
    CPU_COUNT=$(nproc)
    stress-ng --cpu "$CPU_COUNT" --cpu-load 85 --timeout 0 &
    echo $! >> "$CLEANUP_FILE"
    log "   stress-ng CPU PID: $!"
}

start_memory_stress() {
    log "🧠 Starting memory pressure (6GB across 4 workers)..."
    stress-ng --vm 4 --vm-bytes 1500m --timeout 0 &
    echo $! >> "$CLEANUP_FILE"
    log "   stress-ng MEM PID: $!"
}

start_io_stress() {
    log "💾 Starting IO stress (8 io workers, 4 hdd workers)..."
    stress-ng --io 8 --hdd 4 --timeout 0 &
    echo $! >> "$CLEANUP_FILE"
    log "   stress-ng IO PID: $!"
}

start_bandwidth_throttle() {
    log "🌐 Throttling network bandwidth to 10Mbit..."
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$IFACE" ]; then
        log "   ❌ Could not detect default interface. Skipping."
        return 1
    fi
    # Remove any existing qdisc first to avoid 'file exists' error
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
    sudo tc qdisc add dev "$IFACE" root tbf rate 10mbit burst 32kbit latency 400ms
    echo "tc:$IFACE" >> "$CLEANUP_FILE"
    log "   Throttled: $IFACE → 10Mbit"
}

start_db_load() {
    log "🗄 Starting DB overload (heavy MySQL queries on $MYSQL_POD)..."
    # Run in background — the kubectl exec loop runs inside the pod
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- bash -c \
        "while true; do \
            mysql -u${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_DB} \
              -e 'SELECT * FROM orders LIMIT 100000;' \
              2>/dev/null; \
         done" &
    echo $! >> "$CLEANUP_FILE"
    log "   DB load PID: $!"
}

start_pod_restart() {
    log "🔄 Scheduling pod restarts every 30s (order + payment)..."
    (
        while true; do
            kubectl delete pod -n "$NAMESPACE" -l app=ts-order-service \
                --grace-period=0 2>/dev/null || true
            sleep 30
            kubectl delete pod -n "$NAMESPACE" -l app=ts-payment-service \
                --grace-period=0 2>/dev/null || true
            sleep 30
        done
    ) &
    echo $! >> "$CLEANUP_FILE"
    log "   Restart loop PID: $!"
}

start_verbose_log() {
    log "📝 Enabling TRACE logging on ts-order-service..."
    kubectl exec -n "$NAMESPACE" deploy/ts-order-service -- \
        curl -s -X POST "http://localhost:8080/actuator/loggers/ROOT" \
        -H "Content-Type: application/json" \
        -d '{"configuredLevel":"TRACE"}' 2>/dev/null || {
            log "   ⚠️  actuator endpoint not reachable — skipping"
            return 0
        }
    echo "verbose_log" >> "$CLEANUP_FILE"
    log "   Logging set to TRACE on ts-order-service"
}

stop_all() {
    log "🛑 Stopping all anomaly injectors..."
    if [ ! -f "$CLEANUP_FILE" ]; then
        log "   No cleanup file found — nothing to stop"
        return 0
    fi
    while IFS= read -r entry; do
        if [[ "$entry" == tc:* ]]; then
            IFACE="${entry#tc:}"
            sudo tc qdisc del dev "$IFACE" root 2>/dev/null && \
                log "   Removed tc qdisc on $IFACE" || true
        elif [[ "$entry" == "verbose_log" ]]; then
            kubectl exec -n "$NAMESPACE" deploy/ts-order-service -- \
                curl -s -X POST "http://localhost:8080/actuator/loggers/ROOT" \
                -H "Content-Type: application/json" \
                -d '{"configuredLevel":"INFO"}' 2>/dev/null || true
            log "   Restored logging level to INFO on ts-order-service"
        else
            kill "$entry" 2>/dev/null && log "   Killed PID $entry" || true
        fi
    done < "$CLEANUP_FILE"
    rm -f "$CLEANUP_FILE"
    log "✅ All anomaly processes stopped"
}

case "$CMD" in
    start)
        rm -f "$CLEANUP_FILE"   # clear stale state from previous run
        case "$SCENARIO" in
            cpu-stress)     start_cpu_stress         ;;
            memory-stress)  start_memory_stress      ;;
            io-stress)      start_io_stress          ;;
            bandwidth)      start_bandwidth_throttle ;;
            db-load)        start_db_load            ;;
            pod-restart)    start_pod_restart        ;;
            verbose-log)    start_verbose_log        ;;
            *)
                echo "❌ Unknown scenario: '$SCENARIO'"
                echo "   Valid: cpu-stress | memory-stress | io-stress | bandwidth | db-load | pod-restart | verbose-log"
                exit 1
                ;;
        esac
        ;;
    stop)
        stop_all
        ;;
    *)
        echo "Usage: $0 start <scenario> | stop"
        exit 1
        ;;
esac
