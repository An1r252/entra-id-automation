#!/usr/bin/env bash
# ============================================================
# create-security-groups.sh
# Creates Entra ID Security Groups via Azure CLI and sets a
# specified user as the owner of each group.
# Requires: azure-cli  (brew install azure-cli  OR
#           https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
# ============================================================

set -uo pipefail

# ── Group definitions ────────────────────────────────────────
# Format: "DisplayName|Description|OwnerUPN"
# Replace values before running.
GROUPS=(
  "AZ-APP-BXTY-GROUP1|Baxterity Group 1 Users|owner1@contoso.com"
  "AZ-APP-BXTY-GROUP2|Baxterity Group 2 Users|owner1@contoso.com"
  "AZ-APP-BXTY-GROUP3|Baxterity Group 3 Users|owner2@contoso.com"
  "AZ-APP-BXTY-GROUP4|Baxterity Group 4 Users|owner2@contoso.com"
)
# ─────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'
# ─────────────────────────────────────────────────────────────

# ── Log file setup ───────────────────────────────────────────
LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-security-groups-$(date +%Y%m%d-%H%M%S).log"
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

# Counters
CREATED=0; SKIPPED=0; FAILED=0

for ENTRY in "${GROUPS[@]}"; do
  IFS='|' read -r DISPLAY_NAME DESCRIPTION OWNER_UPN <<< "$ENTRY"

  echo -e "\n${CYAN}[PROCESSING] ${DISPLAY_NAME}${RESET}"
  log "INFO" "Processing group: ${DISPLAY_NAME} | Description: ${DESCRIPTION} | Owner: ${OWNER_UPN}"

  # Derive a mail nickname (alphanumeric only)
  MAIL_NICK=$(echo "$DISPLAY_NAME" | tr -dc '[:alnum:]')
  log "INFO" "  Mail nickname: ${MAIL_NICK}"

  # Check if group already exists
  echo -e "  Checking if group already exists..."
  log "INFO" "  Checking if group already exists..."
  EXISTING_ID=$(az ad group list \
    --filter "displayName eq '${DISPLAY_NAME}'" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$EXISTING_ID" ]]; then
    echo -e "  ${YELLOW}SKIPPED — group already exists (Id: ${EXISTING_ID})${RESET}"
    log "WARN" "  SKIPPED — group already exists (Id: ${EXISTING_ID})"
    (( SKIPPED++ )) || true
    continue
  fi

  log "INFO" "  Group does not exist, proceeding with creation."

  # Resolve owner UPN to Object ID (timeout after 15 seconds)
  echo -e "  Resolving owner: ${OWNER_UPN}..."
  log "INFO" "  Resolving owner UPN: ${OWNER_UPN}"

  OWNER_RESOLVE=$(timeout 15 az ad user show --id "$OWNER_UPN" --query id -o tsv 2>&1)
  OWNER_EXIT=$?

  if [[ $OWNER_EXIT -eq 124 ]]; then
    echo -e "  ${RED}FAILED — timed out resolving owner: ${OWNER_UPN}${RESET}"
    log "ERROR" "  FAILED — timed out resolving owner: ${OWNER_UPN}"
    (( FAILED++ )) || true
    continue
  fi

  OWNER_ID=$(echo "$OWNER_RESOLVE" | tr -d '[:space:]')

  if [[ -z "$OWNER_ID" || "$OWNER_EXIT" -ne 0 ]]; then
    echo -e "  ${RED}FAILED — owner not found: ${OWNER_UPN}${RESET}"
    echo -e "  ${RED}Error: ${OWNER_RESOLVE}${RESET}"
    log "ERROR" "  FAILED — owner not found: ${OWNER_UPN}. Error: ${OWNER_RESOLVE}"
    (( FAILED++ )) || true
    continue
  fi

  echo -e "  Owner resolved (ObjectId: ${OWNER_ID})"
  log "INFO" "  Owner resolved (ObjectId: ${OWNER_ID})"

  # Create the security group
  echo -e "  Creating group..."
  log "INFO" "  Creating group: ${DISPLAY_NAME}"
  GROUP_ID=$(az ad group create \
    --display-name "$DISPLAY_NAME" \
    --mail-nickname "$MAIL_NICK" \
    --description "$DESCRIPTION" \
    --query id -o tsv 2>&1) && CREATED_OK=true || CREATED_OK=false

  if [[ "$CREATED_OK" == "true" ]]; then
    echo -e "  Group created (Id: ${GROUP_ID})"
    log "INFO" "  Group created (Id: ${GROUP_ID})"

    # Set the specified user as owner
    echo -e "  Assigning owner: ${OWNER_UPN}..."
    log "INFO" "  Assigning owner (ObjectId: ${OWNER_ID}) to group (Id: ${GROUP_ID})"
    if az ad group owner add \
        --group "$GROUP_ID" \
        --owner-object-id "$OWNER_ID" \
        --only-show-errors; then
      echo -e "  ${GREEN}SUCCESS — Created and owner assigned (Owner: ${OWNER_UPN})${RESET}"
      log "INFO" "  SUCCESS — owner assigned successfully"
    else
      echo -e "  ${YELLOW}WARNING — Group created but owner assignment failed${RESET}"
      log "WARN" "  WARNING — Group created but owner assignment failed"
    fi
    (( CREATED++ )) || true
  else
    echo -e "  ${RED}FAILED — could not create group${RESET}"
    echo -e "  ${RED}Error: ${GROUP_ID}${RESET}"
    log "ERROR" "  FAILED — could not create group. Error: ${GROUP_ID}"
    (( FAILED++ )) || true
  fi

done

# Summary
echo ""
echo    "── Summary ──────────────────────────────────────────────"
echo -e "  ${GREEN}Created : ${CREATED}${RESET}"
echo -e "  ${YELLOW}Skipped : ${SKIPPED}${RESET}"
echo -e "  ${RED}Failed  : ${FAILED}${RESET}"
echo ""
echo -e "  Log file: ${LOG_FILE}"
echo    "─────────────────────────────────────────────────────────"

log "INFO" "Script completed — Created: ${CREATED} | Skipped: ${SKIPPED} | Failed: ${FAILED}"

# Sign out
az logout
echo -e "${CYAN}[AUTH] Logged out.${RESET}\n"
log "INFO" "Logged out of Azure."
