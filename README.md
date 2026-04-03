# Entra ID Automation

Azure CLI and PowerShell scripts for managing Microsoft Entra ID (Azure AD) resources including Security Groups and Access Packages.

---

## Repository Structure

```
entra-id-automation/
├── scripts/
│   ├── groups/
│   │   ├── create-security-groups.sh       # Azure CLI (bash)
│   │   └── Create-SecurityGroups.ps1       # PowerShell (Microsoft.Graph SDK)
│   └── access-packages/                    # Coming soon
├── docs/
│   └── az-cli-reference.md                 # Azure CLI command reference
└── README.md
```

---

## Prerequisites

### Azure CLI (bash scripts)
- Install: https://aka.ms/installazurecliwindows
- Login: `az login --use-device-code --allow-no-subscriptions`

### PowerShell scripts
- Requires Microsoft.Graph SDK:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```

---

## Usage

### Security Groups

**Bash (Azure CLI)**
```bash
chmod +x scripts/groups/create-security-groups.sh
./scripts/groups/create-security-groups.sh
```

**PowerShell**
```powershell
./scripts/groups/Create-SecurityGroups.ps1
```

Both scripts will:
1. Prompt you to log in via device code
2. Resolve your user ID automatically
3. Create each group with you set as owner
4. Skip groups that already exist
5. Print a created/skipped/failed summary

---

## Useful Azure CLI Commands

### Groups
```bash
# Get a group
az ad group show --group "AZ-APP-BXTY-USERS"

# List groups (server-side filter)
az ad group list --filter "displayName eq 'AZ-APP-BXTY-USERS'" --output table

# List group members
az ad group member list --group "AZ-APP-BXTY-USERS" --output table

# Check current login
az account show --query user.name -o tsv

# Switch tenant
az login --tenant <tenant-id> --use-device-code --allow-no-subscriptions
```

### Access Packages
```bash
# List all access packages
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages"

# Get specific access package
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/<id>"

# Get resource roles inside a package
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/<id>/resourceRoleScopes"
```

---

## Notes
- All groups are created as cloud-only security groups (`securityEnabled: true`, `mailEnabled: false`)
- Scripts require `Group.ReadWrite.All` and `User.Read` Graph permissions
- Access package commands require `EntitlementManagement.Read.All` or `EntitlementManagement.ReadWrite.All`
