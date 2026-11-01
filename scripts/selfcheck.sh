#!/usr/bin/env bash
# Compares NetDog's sampling against netstat over the same window.
# Traffic is bursty, so a >30% gap only warns; a hard failure means NetDog
# reported nothing while netstat saw real traffic.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/NetDog.app/Contents/MacOS/NetDog"
SECONDS_TO_SAMPLE="${1:-5}"

if [[ ! -x "$BIN" ]]; then
    echo "missing binary: $BIN (run make app first)" >&2
    exit 1
fi

IFACE="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')"
if [[ -z "$IFACE" ]]; then
    echo "no default route" >&2
    exit 1
fi

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

read_counters() {
    netstat -ibn | awk -v iface="$IFACE" '$1 == iface && $3 ~ /^<Link/ {print $7, $10; exit}'
}

read -r base_in base_out <<<"$(read_counters)"
start_ts="$(now)"
output="$("$BIN" --sample "$SECONDS_TO_SAMPLE")"
end_ts="$(now)"
read -r end_in end_out <<<"$(read_counters)"

if [[ -z "${base_in:-}" || -z "${end_in:-}" ]]; then
    echo "cannot read netstat counters for $IFACE" >&2
    exit 1
fi

net_elapsed="$(awk -v a="$start_ts" -v b="$end_ts" 'BEGIN { printf "%.3f", b - a }')"

awk -v iface="$IFACE" \
    -v bi="$base_in" -v bo="$base_out" \
    -v ei="$end_in" -v eo="$end_out" \
    -v dt="$net_elapsed" \
    -v app="$output" '
function human(bps) {
    if (bps >= 1e9) return sprintf("%.1f GB/s", bps / 1e9)
    if (bps >= 1e6) return sprintf("%.1f MB/s", bps / 1e6)
    if (bps >= 1e3) return sprintf("%.0f KB/s", bps / 1e3)
    return "0 KB/s"
}
BEGIN {
    app_dl = 0
    app_ul = 0
    count = split(app, parts, " ")
    for (i = 1; i <= count; i++) {
        if (parts[i] ~ /^download=/) { sub(/^download=/, "", parts[i]); app_dl = parts[i] + 0 }
        if (parts[i] ~ /^upload=/) { sub(/^upload=/, "", parts[i]); app_ul = parts[i] + 0 }
    }

    net_dl = (ei - bi) / dt
    net_ul = (eo - bo) / dt

    printf "interface : %s\n", iface
    printf "netstat   : ↓%s  ↑%s  (%.2fs)\n", human(net_dl), human(net_ul), dt
    printf "netdog    : ↓%s  ↑%s\n", human(app_dl), human(app_ul)

    worst = 0
    if (net_dl > 0) { diff = (app_dl - net_dl) / net_dl; if (diff < 0) diff = -diff; if (diff > worst) worst = diff }
    if (net_ul > 0) { diff = (app_ul - net_ul) / net_ul; if (diff < 0) diff = -diff; if (diff > worst) worst = diff }

    if (app_dl == 0 && app_ul == 0 && (net_dl > 20000 || net_ul > 20000)) {
        print "FAIL: netdog reported 0 while netstat saw traffic"
        exit 2
    }
    if (worst > 0.3) {
        printf "WARN: %.0f%% deviation (bursty traffic or window alignment)\n", worst * 100
    } else {
        printf "OK: deviation %.0f%%\n", worst * 100
    }
}'
