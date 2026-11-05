#!/usr/bin/env bash
# Runs terraform plan against a config dir and reports whether live state drifted.
# Exit codes: 0 = no drift, 1 = error, 2 = drift found.
set -euo pipefail

CONFIG_DIR="${1:-config}"
PLAN_FILE="tfplan"

cd "$CONFIG_DIR"

terraform init -input=false >/dev/null

set +e
terraform plan -detailed-exitcode -input=false -out="$PLAN_FILE"
PLAN_EXIT=$?
set -e

if [ "$PLAN_EXIT" -eq 0 ]; then
  echo "no drift"
  exit 0
fi

if [ "$PLAN_EXIT" -eq 1 ]; then
  echo "terraform plan failed"
  exit 1
fi

# PLAN_EXIT is 2: drift found. Count the change types from the plan.
# A replacement shows up as actions ["delete","create"] (or occasionally the reverse order), so
# it's counted on its own instead of silently missing every create/update/delete filter below.
PLAN_JSON=$(terraform show -json "$PLAN_FILE")
CREATES=$(echo "$PLAN_JSON" | jq '[(.resource_changes // [])[] | select(.change.actions == ["create"])] | length')
UPDATES=$(echo "$PLAN_JSON" | jq '[(.resource_changes // [])[] | select(.change.actions == ["update"])] | length')
DELETES=$(echo "$PLAN_JSON" | jq '[(.resource_changes // [])[] | select(.change.actions == ["delete"])] | length')
REPLACES=$(echo "$PLAN_JSON" | jq '[(.resource_changes // [])[] | select(.change.actions == ["delete", "create"] or .change.actions == ["create", "delete"])] | length')

echo "drift found: $CREATES to create, $UPDATES to update, $DELETES to delete, $REPLACES to replace"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Drift detected"
    echo ""
    echo "| create | update | delete | replace |"
    echo "|---|---|---|---|"
    echo "| $CREATES | $UPDATES | $DELETES | $REPLACES |"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  BODY=$(jq -n \
    --arg text "Drift detected: $CREATES to create, $UPDATES to update, $DELETES to delete, $REPLACES to replace" \
    '{text: $text}')

  # DRY_SLACK_FILE lets tests capture the message body instead of posting it.
  if [ -n "${DRY_SLACK_FILE:-}" ]; then
    echo "$BODY" >"$DRY_SLACK_FILE"
  else
    # A failed Slack post is a notification problem, not a drift-detection problem - warn and
    # keep going so the script still exits 2 for the drift that was actually found.
    if ! curl -sf -X POST -H "Content-Type: application/json" -d "$BODY" "$SLACK_WEBHOOK_URL" >/dev/null; then
      echo "warning: failed to post Slack notification" >&2
    fi
  fi
fi

exit 2
