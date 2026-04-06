#!/usr/bin/env bash
# ============================================================
# create-access-packages.sh
# Creates Entra ID Access Packages and links a Security Group
# to each package via the Microsoft Graph API (az rest).
#
# CSV format (no spaces around commas):
#   AccessPackageName,Description,CatalogName,GroupDisplayName
#   Dev Access,Access for developers,IT Catalog,AZ-APP-BXTY-GROUP1
#
# Usage:
#   ./create-access-packages.sh                        # uses default access-packages.csv
#   ./create-access-packages.sh my-custom-file.csv     # uses a custom CSV file
#
# Requires: azure-cli  (brew install azure-cli)
# ============================================================

set -uo pipefail

# ── CSV input ────────────────────────────────────────────────
CSV_FILE="${1:-$(dirname "$0")/access-packages.csv}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo -e "\033[0;31m[ERROR] CSV file not found: ${CSV_FILE}\033[0m"
  echo -e "        Create the file or pass a path as an argument:"
  echo -e "        Usage: ./create-access-packages.sh [path/to/file.csv]"
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
LOG_FILE="$LOG_DIR/create-access-packages-$(date +%Y%m%d-%H%M%S).log"
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

# ── Counters ─────────────────────────────────────────────────
CREATED=0; SKIPPED=0; FAILED=0; ROW=0
# ─────────────────────────────────────────────────────────────

# ── Process CSV ──────────────────────────────────────────────
echo -e "${CYAN}[INFO] Reading CSV: ${CSV_FILE}${RESET}\n"
log "INFO" "Reading CSV: ${CSV_FILE}"

while IFS=',' read -r AP_NAME DESCRIPTION CATALOG_NAME GROUP_NAME; do
  # Skip header row
  (( ROW++ )) || true
  if [[ $ROW -eq 1 && "${AP_NAME,,}" == "accesspackagename" ]]; then
    log "INFO" "Skipping header row"
    continue
  fi

  # Trim whitespace
  AP_NAME="${AP_NAME#"${AP_NAME%%[![:space:]]*}"}"
  AP_NAME="${AP_NAME%"${AP_NAME##*[![:space:]]}"}"
  DESCRIPTION="${DESCRIPTION#"${DESCRIPTION%%[![:space:]]*}"}"
  CATALOG_NAME="${CATALOG_NAME#"${CATALOG_NAME%%[![:space:]]*}"}"
  CATALOG_NAME="${CATALOG_NAME%"${CATALOG_NAME##*[![:space:]]}"}"
  GROUP_NAME="${GROUP_NAME#"${GROUP_NAME%%[![:space:]]*}"}"
  GROUP_NAME="${GROUP_NAME%"${GROUP_NAME##*[![:space:]]}"}"

  # Skip empty rows
  if [[ -z "$AP_NAME" || -z "$CATALOG_NAME" || -z "$GROUP_NAME" ]]; then
    log "WARN" "Skipping incomplete row at line ${ROW}"
    continue
  fi

  echo -e "${CYAN}[PROCESSING] Access Package: '${AP_NAME}' | Catalog: '${CATALOG_NAME}' | Group: '${GROUP_NAME}'${RESET}"
  log "INFO" "Processing row ${ROW}: Package='${AP_NAME}' | Catalog='${CATALOG_NAME}' | Group='${GROUP_NAME}'"

  # ── Step 1: Find the catalog ────────────────────────────────
  echo -e "  [1/5] Looking up catalog: '${CATALOG_NAME}'..."
  log "INFO" "  [1/5] Looking up catalog: '${CATALOG_NAME}'"

  CATALOG_ID=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs?\$filter=displayName eq '${CATALOG_NAME}'" \
    --query "value[0].id" -o tsv 2>/dev/null || true)

  if [[ -z "$CATALOG_ID" || "$CATALOG_ID" == "None" ]]; then
    echo -e "  ${YELLOW}  Catalog not found. Creating catalog: '${CATALOG_NAME}'...${RESET}"
    log "INFO" "  Catalog not found. Creating: '${CATALOG_NAME}'"

    CATALOG_RESP=$(az rest \
      --method POST \
      --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs" \
      --headers "Content-Type=application/json" \
      --body "{\"displayName\": \"${CATALOG_NAME}\", \"description\": \"${CATALOG_NAME} catalog\", \"isExternallyVisible\": false}" \
      2>&1)
    CATALOG_EXIT=$?

    if [[ $CATALOG_EXIT -ne 0 ]]; then
      echo -e "  ${RED}  FAILED — could not create catalog '${CATALOG_NAME}'${RESET}"
      echo -e "  ${RED}  Error: ${CATALOG_RESP}${RESET}"
      log "ERROR" "  FAILED — could not create catalog. Error: ${CATALOG_RESP}"
      (( FAILED++ )) || true
      continue
    fi

    CATALOG_ID=$(echo "$CATALOG_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)
    echo -e "  ${GREEN}  Catalog created (Id: ${CATALOG_ID})${RESET}"
    log "INFO" "  Catalog created (Id: ${CATALOG_ID})"
  else
    echo -e "  ${GREEN}  Catalog found (Id: ${CATALOG_ID})${RESET}"
    log "INFO" "  Catalog found (Id: ${CATALOG_ID})"
  fi

  # ── Step 2: Look up the group ───────────────────────────────
  echo -e "  [2/5] Looking up group: '${GROUP_NAME}'..."
  log "INFO" "  [2/5] Looking up group: '${GROUP_NAME}'"

  GROUP_ID=$(az ad group list \
    --filter "displayName eq '${GROUP_NAME}'" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -z "$GROUP_ID" || "$GROUP_ID" == "None" ]]; then
    echo -e "  ${RED}  FAILED — group not found: '${GROUP_NAME}'${RESET}"
    log "ERROR" "  FAILED — group not found: '${GROUP_NAME}'"
    (( FAILED++ )) || true
    continue
  fi

  echo -e "  ${GREEN}  Group found (Id: ${GROUP_ID})${RESET}"
  log "INFO" "  Group found (Id: ${GROUP_ID})"

  # ── Step 3: Add group as a resource to the catalog ──────────
  echo -e "  [3/5] Adding group to catalog (if not already added)..."
  log "INFO" "  [3/5] Checking if group is already a resource in catalog '${CATALOG_ID}'"

  EXISTING_RESOURCE=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources?\$filter=originId eq '${GROUP_ID}'" \
    --query "value[0].id" -o tsv 2>/dev/null || true)

  if [[ -z "$EXISTING_RESOURCE" || "$EXISTING_RESOURCE" == "None" ]]; then
    ADD_RESOURCE_RESP=$(az rest \
      --method POST \
      --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/resourceRequests" \
      --headers "Content-Type=application/json" \
      --body "{
        \"requestType\": \"adminAdd\",
        \"resource\": {
          \"originId\": \"${GROUP_ID}\",
          \"originSystem\": \"AadGroup\"
        },
        \"catalog\": { \"id\": \"${CATALOG_ID}\" }
      }" 2>&1)
    ADD_RESOURCE_EXIT=$?

    if [[ $ADD_RESOURCE_EXIT -ne 0 ]]; then
      echo -e "  ${RED}  FAILED — could not add group to catalog${RESET}"
      echo -e "  ${RED}  Error: ${ADD_RESOURCE_RESP}${RESET}"
      log "ERROR" "  FAILED — could not add group to catalog. Error: ${ADD_RESOURCE_RESP}"
      (( FAILED++ )) || true
      continue
    fi
    echo -e "  ${GREEN}  Group added to catalog${RESET}"
    log "INFO" "  Group added to catalog successfully"
    sleep 3  # allow Graph to propagate the resource
  else
    echo -e "  ${GREEN}  Group already in catalog (ResourceId: ${EXISTING_RESOURCE})${RESET}"
    log "INFO" "  Group already exists in catalog (ResourceId: ${EXISTING_RESOURCE})"
  fi

  # ── Step 4: Check if access package already exists ──────────
  echo -e "  [4/5] Checking if access package already exists: '${AP_NAME}'..."
  log "INFO" "  [4/5] Checking if access package '${AP_NAME}' already exists"

  AP_ID=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages?\$filter=displayName eq '${AP_NAME}'" \
    --query "value[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$AP_ID" && "$AP_ID" != "None" ]]; then
    echo -e "  ${YELLOW}  SKIPPED — access package already exists (Id: ${AP_ID})${RESET}"
    log "WARN" "  SKIPPED — access package '${AP_NAME}' already exists (Id: ${AP_ID})"
    (( SKIPPED++ )) || true
    continue
  fi

  # Create access package
  echo -e "  Creating access package: '${AP_NAME}'..."
  log "INFO" "  Creating access package '${AP_NAME}' in catalog '${CATALOG_ID}'"

  AP_RESP=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages" \
    --headers "Content-Type=application/json" \
    --body "{
      \"displayName\": \"${AP_NAME}\",
      \"description\": \"${DESCRIPTION}\",
      \"isHidden\": false,
      \"catalog\": { \"id\": \"${CATALOG_ID}\" }
    }" 2>&1)
  AP_EXIT=$?

  if [[ $AP_EXIT -ne 0 ]]; then
    echo -e "  ${RED}  FAILED — could not create access package '${AP_NAME}'${RESET}"
    echo -e "  ${RED}  Error: ${AP_RESP}${RESET}"
    log "ERROR" "  FAILED — could not create access package. Error: ${AP_RESP}"
    (( FAILED++ )) || true
    continue
  fi

  AP_ID=$(echo "$AP_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)
  echo -e "  ${GREEN}  Access package created (Id: ${AP_ID})${RESET}"
  log "INFO" "  Access package created (Id: ${AP_ID})"

  # ── Step 5: Link group resource role to access package ──────
  echo -e "  [5/5] Linking group to access package..."
  log "INFO" "  [5/5] Linking group (Id: ${GROUP_ID}) to access package (Id: ${AP_ID})"

  # Get resource ID from catalog
  RESOURCE_ID=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources?\$filter=originId eq '${GROUP_ID}'" \
    --query "value[0].id" -o tsv 2>/dev/null || true)

  # Get member role ID
  ROLE_ID=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources/${RESOURCE_ID}/roles" \
    --query "value[?displayName=='Member'].id | [0]" -o tsv 2>/dev/null || true)

  # Get resource scope ID
  SCOPE_ID=$(az rest \
    --method GET \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources/${RESOURCE_ID}/scopes" \
    --query "value[0].id" -o tsv 2>/dev/null || true)

  LINK_RESP=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/${AP_ID}/resourceRoleScopes" \
    --headers "Content-Type=application/json" \
    --body "{
      \"role\": {
        \"id\": \"${ROLE_ID}\",
        \"originId\": \"Member_${GROUP_ID}\",
        \"originSystem\": \"AadGroup\",
        \"resource\": {
          \"id\": \"${RESOURCE_ID}\",
          \"originId\": \"${GROUP_ID}\",
          \"originSystem\": \"AadGroup\"
        }
      },
      \"scope\": {
        \"id\": \"${SCOPE_ID}\",
        \"originSystem\": \"AadGroup\"
      }
    }" 2>&1)
  LINK_EXIT=$?

  if [[ $LINK_EXIT -ne 0 ]]; then
    echo -e "  ${RED}  FAILED — could not link group to access package${RESET}"
    echo -e "  ${RED}  Error: ${LINK_RESP}${RESET}"
    log "ERROR" "  FAILED — could not link group to access package. Error: ${LINK_RESP}"
    (( FAILED++ )) || true
    continue
  fi

  echo -e "  ${GREEN}  Group linked to access package as 'Member'${RESET}"
  log "INFO" "  Group linked to access package successfully"
  echo -e "  ${GREEN}SUCCESS — Access package '${AP_NAME}' created and configured${RESET}\n"
  log "INFO" "SUCCESS — Access package '${AP_NAME}' fully created (Id: ${AP_ID})"
  (( CREATED++ )) || true

done < "$CSV_FILE"
# ─────────────────────────────────────────────────────────────

# ── Summary ──────────────────────────────────────────────────
echo ""
echo    "── Summary ──────────────────────────────────────────────"
echo -e "  ${GREEN}Created : ${CREATED}${RESET}"
echo -e "  ${YELLOW}Skipped : ${SKIPPED}${RESET}"
echo -e "  ${RED}Failed  : ${FAILED}${RESET}"
echo ""
echo -e "  Log file: ${LOG_FILE}"
echo    "─────────────────────────────────────────────────────────"

log "INFO" "Script completed — Created: ${CREATED} | Skipped: ${SKIPPED} | Failed: ${FAILED}"
