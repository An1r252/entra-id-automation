#!/usr/bin/env bash
# ============================================================
# create-security-groups.sh
# Creates Entra ID Security Groups via Azure CLI and sets the
# logged-in user as the owner of each group.
# Requires: azure-cli  (brew install azure-cli  OR
#           https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
# ============================================================

set -euo pipefail

# ── Group definitions ────────────────────────────────────────
# Format: "DisplayName|Description"
# Replace dummy names/descriptions with real values before running.
GROUPS=(
  "AZ-APP-BXTY-GROUP1|Baxterity Group 1 Users"
  "AZ-APP-BXTY-GROUP2|Baxterity Group 2 Users"
  "AZ-APP-BXTY-GROUP3|Baxterity Group 3 Users"
  "AZ-APP-BXTY-GROUP4|Baxterity Group 4 Users"
)
# ─────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'
# ─────────────────────────────────────────────────────────────

echo -e "\n${CYAN}[AUTH] Logging in to Azure...${RESET}"
az login --use-device-code --allow-no-subscriptions

# Resolve signed-in user's object ID
OWNER_ID=$(az ad signed-in-user show --query id -o tsv)
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
echo -e "${GREEN}[AUTH] Signed in as: ${UPN}  (ObjectId: ${OWNER_ID})${RESET}\n"

# Counters
CREATED=0; SKIPPED=0; FAILED=0

for ENTRY in "${GROUPS[@]}"; do
  IFS='|' read -r DISPLAY_NAME DESCRIPTION <<< "$ENTRY"

  # Derive a mail nickname (alphanumeric only)
  MAIL_NICK=$(echo "$DISPLAY_NAME" | tr -dc '[:alnum:]')

  printf "[CREATE] %-40s" "$DISPLAY_NAME ..."

  # Check if group already exists
  EXISTING_ID=$(az ad group list \
    --filter "displayName eq '${DISPLAY_NAME}'" \
    --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -n "$EXISTING_ID" ]]; then
    echo -e " ${YELLOW}SKIPPED (already exists: ${EXISTING_ID})${RESET}"
    (( SKIPPED++ )) || true
    continue
  fi

  # Create the security group
  if GROUP_ID=$(az ad group create \
        --display-name "$DISPLAY_NAME" \
        --mail-nickname "$MAIL_NICK" \
        --description "$DESCRIPTION" \
        --query id -o tsv 2>&1); then

    # Set the signed-in user as owner
    az ad group owner add \
      --group "$GROUP_ID" \
      --owner-object-id "$OWNER_ID" \
      --only-show-errors

    echo -e " ${GREEN}CREATED (Id: ${GROUP_ID})${RESET}"
    (( CREATED++ )) || true
  else
    echo -e " ${RED}FAILED${RESET}"
    echo -e "  ${RED}Error: ${GROUP_ID}${RESET}"
    (( FAILED++ )) || true
  fi

done

# Summary
echo ""
echo "── Summary ──────────────────────────────────────────────"
echo -e "  ${GREEN}Created : ${CREATED}${RESET}"
echo -e "  ${YELLOW}Skipped : ${SKIPPED}${RESET}"
echo -e "  ${RED}Failed  : ${FAILED}${RESET}"
echo ""

# Sign out
az logout
echo -e "${CYAN}[AUTH] Logged out.${RESET}\n"
