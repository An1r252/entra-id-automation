#!/usr/bin/env bash
# ============================================================
# rename-groups.sh
# Renames Entra ID Security Groups via Azure CLI using a CSV
# file as input.
#
# CSV format (no spaces around commas):
#   OldDisplayName,NewDisplayName
#   AZ-APP-BXTY-GROUP1,AZ-APP-BXTY-USERS
#
# Usage:
#   ./rename-groups.sh                        # uses default groups-rename.csv
#   ./rename-groups.sh my-custom-file.csv     # uses a custom CSV file
#
# Requires: azure-cli  (brew install azure-cli)
# ============================================================

set -uo pipefail

# ── CSV input ────────────────────────────────────────────────
CSV_FILE="${1:-$(dirname "$0")/groups-rename.csv}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo -e "\033[0;31m[ERROR] CSV file not found: ${CSV_FILE}\033[0m"
  echo -e "        Create the file or pass a path as an argument:"
  echo -e "        Usage: ./rename-groups.sh [path/to/file.csv]"
  exit 1
fi
# ─────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'
# ─────────────────────────────────────────────────────────────

# ── Log file setup ───────────────────────────────────────────
LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/rename-groups-$(date +%Y%m%d-%H%M%S).log"
# ─────────────────────────────────────────────────────────────

# ── Logging helper ───────────────────────────────────────────
log() {
  local LEVEL="$1"
  local MSG="$2"
  local TIMESTAMP
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$TIMESTAMP] [$LEVEL] $MSG" >> "$LOG_FILE"
}
# ─────────────────────────────────────────────────────────────

log "INFO" "Script started"
log "INFO" "Using CSV file: ${CSV_FILE}"

# ── Auth check ───────────────────────────────────────────────
echo -e "\n${CYAN}[AUTH] Checking Azure login status...${RESET}"
log "INFO" "Checking Azure login status..."

SIGNED_IN_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)

if [[ -n "$SIGNED_IN_UPN" ]]; then
  echo -e "${GREEN}[AUTH] Already logged in as: ${SIGNED_IN_UPN}${RESET}\n"
  log "INFO" "Already logged in as: ${SIGNED_IN_UPN}"
else
  echo -e "${YELLOW}[AUTH] Not logged in. Initiating login...${RESET}"
  log "INFO" "Not logged in. Initiating Azure login..."

  if ! az login --use-device-code --allow-no-subscriptions; then
    echo -e "${RED}[AUTH] Login failed. Exiting.${RESET}"
    log "ERROR" "Azure login failed. Exiting."
    exit 1
  fi

  SIGNED_IN_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "unknown")
  echo -e "${GREEN}[AUTH] Logged in as: ${SIGNED_IN_UPN}${RESET}\n"
  log "INFO" "Logged in as: ${SIGNED_IN_UPN}"
fi
# ─────────────────────────────────────────────────────────────

# ── Process CSV ──────────────────────────────────────────────
echo -e "${CYAN}[INFO] Reading CSV: ${CSV_FILE}${RESET}"
log "INFO" "Reading CSV: ${CSV_FILE}"

# Counters
RENAMED=0; SKIPPED=0; FAILED=0; ROW=0

while IFS=',' read -r OLD_NAME NEW_NAME; do
  # Skip header row
  (( ROW++ )) || true
  if [[ $ROW -eq 1 && "${OLD_NAME,,}" == "olddisplayname" ]]; then
    log "INFO" "Skipping header row"
    continue
  fi

  # Trim whitespace
  OLD_NAME="${OLD_NAME// /}"
  NEW_NAME="${NEW_NAME// /}"

  # Skip empty rows
  if [[ -z "$OLD_NAME" || -z "$NEW_NAME" ]]; then
    log "WARN" "Skipping empty row at line ${ROW}"
    continue
  fi

  echo -e "\n${CYAN}[PROCESSING] '${OLD_NAME}' → '${NEW_NAME}'${RESET}"
  log "INFO" "Processing row ${ROW}: '${OLD_NAME}' → '${NEW_NAME}'"

  # Find the group by old display name
  echo -e "  Looking up group: ${OLD_NAME}..."
  log "INFO" "  Looking up group: ${OLD_NAME}"

  GROUP_ID=$(az ad group list \
    --filter "displayName eq '${OLD_NAME}'" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -z "$GROUP_ID" ]]; then
    echo -e "  ${RED}FAILED — group not found: '${OLD_NAME}'${RESET}"
    log "ERROR" "  FAILED — group not found: '${OLD_NAME}'"
    (( FAILED++ )) || true
    continue
  fi

  log "INFO" "  Group found (Id: ${GROUP_ID})"

  # Check if new name is already taken
  echo -e "  Checking if new name is already in use: ${NEW_NAME}..."
  log "INFO" "  Checking if new name '${NEW_NAME}' is already in use..."

  CONFLICT_ID=$(az ad group list \
    --filter "displayName eq '${NEW_NAME}'" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$CONFLICT_ID" ]]; then
    echo -e "  ${YELLOW}SKIPPED — new name already exists: '${NEW_NAME}' (Id: ${CONFLICT_ID})${RESET}"
    log "WARN" "  SKIPPED — new name '${NEW_NAME}' already in use (Id: ${CONFLICT_ID})"
    (( SKIPPED++ )) || true
    continue
  fi

  # Rename the group (update displayName and mailNickname)
  NEW_MAIL_NICK=$(echo "$NEW_NAME" | tr -dc '[:alnum:]')
  echo -e "  Renaming group (Id: ${GROUP_ID})..."
  log "INFO" "  Renaming group (Id: ${GROUP_ID}) to '${NEW_NAME}' (mailNickname: ${NEW_MAIL_NICK})"

  if az rest \
      --method PATCH \
      --uri "https://graph.microsoft.com/v1.0/groups/${GROUP_ID}" \
      --body "{\"displayName\": \"${NEW_NAME}\", \"mailNickname\": \"${NEW_MAIL_NICK}\"}" \
      --only-show-errors 2>/dev/null; then
    echo -e "  ${GREEN}SUCCESS — Renamed '${OLD_NAME}' → '${NEW_NAME}'${RESET}"
    log "INFO" "  SUCCESS — Renamed '${OLD_NAME}' → '${NEW_NAME}'"
    (( RENAMED++ )) || true
  else
    echo -e "  ${RED}FAILED — could not rename group '${OLD_NAME}'${RESET}"
    log "ERROR" "  FAILED — could not rename group '${OLD_NAME}' (Id: ${GROUP_ID})"
    (( FAILED++ )) || true
  fi

done < "$CSV_FILE"
# ─────────────────────────────────────────────────────────────

# ── Summary ──────────────────────────────────────────────────
echo ""
echo    "── Summary ──────────────────────────────────────────────"
echo -e "  ${GREEN}Renamed : ${RENAMED}${RESET}"
echo -e "  ${YELLOW}Skipped : ${SKIPPED}${RESET}"
echo -e "  ${RED}Failed  : ${FAILED}${RESET}"
echo ""
echo -e "  Log file: ${LOG_FILE}"
echo    "─────────────────────────────────────────────────────────"

log "INFO" "Script completed — Renamed: ${RENAMED} | Skipped: ${SKIPPED} | Failed: ${FAILED}"
