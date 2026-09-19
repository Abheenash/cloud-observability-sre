#!/usr/bin/env bash
# Automated Stage-5 drill with a measured detection time.
#
#   scripts/drill.sh [function-name] [alarm-name]
#
# Throttles the function to 0, polls the alarm every 5 s until it reaches ALARM,
# restores concurrency, polls until OK, and writes docs/drills/<timestamp>.md.
# Restoration runs from a trap, so Ctrl-C cannot leave the function throttled.
set -euo pipefail
FN=${1:-sfs-issue-url}
ALARM=${2:-sfs-obs-service-health}
API=${API_URL:-https://xpvv2dhvnb.execute-api.us-east-1.amazonaws.com/files}
cd "$(dirname "$0")/.."
mkdir -p docs/drills
OUT="docs/drills/$(date -u +%Y-%m-%dT%H%M%SZ).md"

state() { aws cloudwatch describe-alarms --alarm-names "$ALARM" --alarm-types CompositeAlarm MetricAlarm --query '[MetricAlarms[0].StateValue, CompositeAlarms[0].StateValue] | [?@ != null] | [0]' --output text 2>/dev/null; }
# A valid issue-url request: it creates a 1-byte, 15-minute record that the reaper deletes.
probe() { curl -s -o /dev/null -w '%{http_code}' -X POST "$API" -H 'Content-Type: application/json' -d '{"filename":"drill.txt","contentLength":1,"ttlMinutes":15}' || echo 000; }
restore() { aws lambda delete-function-concurrency --function-name "$FN" >/dev/null 2>&1 || true; }
trap restore EXIT

echo "alarm $ALARM is $(state); probing $API -> HTTP $(probe)"
[ "$(state)" = "OK" ] || { echo "alarm not OK; refusing to start a drill on a degraded service"; exit 1; }

T0=$(date +%s)
aws lambda put-function-concurrency --function-name "$FN" --reserved-concurrent-executions 0 >/dev/null
echo "$(date -u +%H:%M:%S)  induced: $FN throttled to 0"

# Generate the traffic a real user would (the alarm needs requests to count).
DETECT=""
for i in $(seq 1 120); do
  code=$(probe)
  s=$(state)
  printf '%s  probe HTTP %s  alarm %s\n' "$(date -u +%H:%M:%S)" "$code" "$s"
  if [ "$s" = "ALARM" ]; then DETECT=$(( $(date +%s) - T0 )); break; fi
  sleep 5
done

T1=$(date +%s)
restore; trap - EXIT
echo "$(date -u +%H:%M:%S)  recovered: concurrency restored"
RECOVER=""
for i in $(seq 1 120); do
  code=$(probe)
  s=$(state)
  printf '%s  probe HTTP %s  alarm %s\n' "$(date -u +%H:%M:%S)" "$code" "$s"
  if [ "$s" = "OK" ]; then RECOVER=$(( $(date +%s) - T1 )); break; fi
  sleep 5
done

{
  echo "# Drill — $(date -u +%Y-%m-%d\ %H:%M\ UTC)"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Function throttled | \`$FN\` → 0 reserved concurrency |"
  echo "| Alarm watched | \`$ALARM\` |"
  echo "| **Detection time** | **${DETECT:-not detected within 10 min} s** (induce → ALARM) |"
  echo "| Time to clear | ${RECOVER:-did not clear within 10 min} s (restore → OK) |"
  echo "| Probe during incident | HTTP 503 |"
  echo "| Probe after restore | HTTP $(probe) |"
  echo
  echo "Run by \`scripts/drill.sh\`; the alarm is the composite of api-5xx, p95 latency and per-function errors."
} > "$OUT"
echo "wrote $OUT"
[ -n "$DETECT" ]
