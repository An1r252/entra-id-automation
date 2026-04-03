#!/usr/bin/env bash
# ============================================================
# create-security-groups.sh
# Creates Entra ID Security Groups via Azure CLI and sets a
# specified user as the owner of each group.
# Requires: azure-cli  (brew install azure-cli  OR
#           https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
# ============================================================

set -euo pipefail

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

echo -e "\n${CYAN}[AUTH] Logging in to Azure...${RESET}"
az login --use-device-code --allow-no-subscriptions
echo -e "${GREEN}[AUTH] Logged in.${RESET}\n"

# Counters
CREATED=0; SKIPPED=0; FAILED=0

for ENTRY in "${GROUPS[@]}"; do
  IFS='|' read -r DISPLAY_NAME DESCRIPTION OWNER_UPN <<< "$ENTRY"

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

  # Resolve owner UPN to Object ID
  OWNER_ID=$(az ad user show --id "$OWNER_UPN" --query id -o tsv 2>/dev/null || true)
  if [[ -z "$OWNER_ID" ]]; then
    echo -e " ${RED}FAILED (owner not found: ${OWNER_UPN})${RESET}"
    (( FAILED++ )) || true
    continue
  fi

  # Create the security group
  if GROUP_ID=$(az ad group create \
        --display-name "$DISPLAY_NAME" \
        --mail-nickname "$MAIL_NICK" \
        --description "$DESCRIPTION" \
        --query id -o tsv 2>&1); then

    # Set the specified user as owner
    az ad group owner add \
      --group "$GROUP_ID" \
      --owner-object-id "$OWNER_ID" \
      --only-show-errors

    echo -e " ${GREEN}CREATED (Id: ${GROUP_ID}  Owner: ${OWNER_UPN})${RESET}"
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
