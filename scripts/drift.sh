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
PLAN_JSON=$(terraform show -json "$PLAN_FILE")
CREATES=$(echo "$PLAN_JSON" | jq '[.resource_changes[] | select(.change.actions == ["create"])] | length')
UPDATES=$(echo "$PLAN_JSON" | jq '[.resource_changes[] | select(.change.actions == ["update"])] | length')
DELETES=$(echo "$PLAN_JSON" | jq '[.resource_changes[] | select(.change.actions == ["delete"])] | length')

echo "drift found: $CREATES to create, $UPDATES to update, $DELETES to delete"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Drift detected"
    echo ""
    echo "| create | update | delete |"
    echo "|---|---|---|"
    echo "| $CREATES | $UPDATES | $DELETES |"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  BODY=$(jq -n \
    --arg text "Drift detected: $CREATES to create, $UPDATES to update, $DELETES to delete" \
    '{text: $text}')

  # DRY_SLACK_FILE lets tests capture the message body instead of posting it.
  if [ -n "${DRY_SLACK_FILE:-}" ]; then
    echo "$BODY" >"$DRY_SLACK_FILE"
  else
    curl -sf -X POST -H "Content-Type: application/json" -d "$BODY" "$SLACK_WEBHOOK_URL" >/dev/null
  fi
fi

exit 2
