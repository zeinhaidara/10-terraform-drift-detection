#!/usr/bin/env bash
# Exercises scripts/drift.sh against temp copies of config/, each in its own state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIFT_SH="$ROOT_DIR/scripts/drift.sh"
FAILED=0

run_case() {
  local name="$1"
  local expect="$2"
  shift 2

  set +e
  OUTPUT=$("$@" 2>&1)
  ACTUAL=$?
  set -e

  if [ "$ACTUAL" -eq "$expect" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (expected exit $expect, got $ACTUAL)"
    echo "$OUTPUT"
    FAILED=1
  fi
}

# case 1: unchanged config applied once, plan again -> no drift
WORK1=$(mktemp -d)
cp "$ROOT_DIR/config/main.tf" "$WORK1/"
(cd "$WORK1" && terraform init -input=false >/dev/null && terraform apply -input=false -auto-approve >/dev/null)
run_case "unchanged config -> no drift" 0 bash "$DRIFT_SH" "$WORK1"

# case 2: change the config after apply -> drift
WORK2=$(mktemp -d)
cp "$ROOT_DIR/config/main.tf" "$WORK2/"
(cd "$WORK2" && terraform init -input=false >/dev/null && terraform apply -input=false -auto-approve >/dev/null)
sed -i 's/replicas    = 2/replicas    = 5/' "$WORK2/main.tf"
set +e
DRIFT_OUTPUT=$(bash "$DRIFT_SH" "$WORK2" 2>&1)
DRIFT_EXIT=$?
set -e
if [ "$DRIFT_EXIT" -eq 2 ] && echo "$DRIFT_OUTPUT" | grep -q "to update"; then
  echo "PASS: changed config -> drift with counts"
else
  echo "FAIL: changed config -> drift with counts (exit $DRIFT_EXIT)"
  echo "$DRIFT_OUTPUT"
  FAILED=1
fi

# case 3: invalid config -> error
WORK3=$(mktemp -d)
echo 'resource "not_a_real_type" "x" {' >"$WORK3/main.tf"
run_case "invalid config -> error" 1 bash "$DRIFT_SH" "$WORK3"

# case 4: Slack body written to a file when drift is found
WORK4=$(mktemp -d)
cp "$ROOT_DIR/config/main.tf" "$WORK4/"
(cd "$WORK4" && terraform init -input=false >/dev/null && terraform apply -input=false -auto-approve >/dev/null)
sed -i 's/replicas    = 2/replicas    = 9/' "$WORK4/main.tf"
SLACK_FILE=$(mktemp)
SLACK_WEBHOOK_URL="file://$SLACK_FILE" DRY_SLACK_FILE="$SLACK_FILE" bash "$DRIFT_SH" "$WORK4" >/dev/null 2>&1 || true
if grep -q "to update" "$SLACK_FILE" 2>/dev/null; then
  echo "PASS: slack message body built correctly"
else
  echo "FAIL: slack message body built correctly"
  cat "$SLACK_FILE" 2>/dev/null || echo "(no file written)"
  FAILED=1
fi

rm -rf "$WORK1" "$WORK2" "$WORK3" "$WORK4" "$SLACK_FILE"

exit $FAILED
