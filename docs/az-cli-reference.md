# Azure CLI Reference — Entra ID

Quick reference for Azure CLI commands used in this project.

---

## Authentication

```bash
# Login with device code (recommended for restricted environments)
az login --use-device-code --allow-no-subscriptions

# Login to a specific tenant
az login --tenant <tenant-id-or-domain> --use-device-code --allow-no-subscriptions

# Check current login
az account show

# Check who you are logged in as
az account show --query user.name -o tsv

# Check current tenant
az account show --query tenantId -o tsv

# List all tenants/subscriptions
az account list --query "[].{Name:name, TenantId:tenantId}" -o table

# Logout
az logout
```

---

## Security Groups

```bash
# Get a group by name or object ID
az ad group show --group "AZ-APP-BXTY-USERS"
az ad group show --group <object-id>

# List all groups
az ad group list --output table

# Filter by display name (server-side — fast)
az ad group list --filter "displayName eq 'AZ-APP-BXTY-USERS'" --output table

# Get just the Object ID
az ad group show --group "AZ-APP-BXTY-USERS" --query id -o tsv

# Create a security group
az ad group create \
  --display-name "AZ-APP-BXTY-USERS" \
  --mail-nickname "AZAPPBXTYUsers" \
  --description "Baxterity Users for all regions"

# Delete a group
az ad group delete --group <object-id>
```

---

## Group Members

```bash
# List members
az ad group member list --group "AZ-APP-BXTY-USERS" --output table

# Check if a user is a member
az ad group member check --group "AZ-APP-BXTY-USERS" --member-id <user-object-id>

# Add a member
az ad group member add --group "AZ-APP-BXTY-USERS" --member-id <user-object-id>

# Remove a member
az ad group member remove --group "AZ-APP-BXTY-USERS" --member-id <user-object-id>
```

---

## Group Owners

```bash
# List owners
az ad group owner list --group "AZ-APP-BXTY-USERS"

# Add an owner
az ad group owner add --group "AZ-APP-BXTY-USERS" --owner-object-id <user-object-id>

# Remove an owner
az ad group owner remove --group "AZ-APP-BXTY-USERS" --owner-object-id <user-object-id>
```

---

## Users

```bash
# Get signed-in user details
az ad signed-in-user show

# Get signed-in user object ID
az ad signed-in-user show --query id -o tsv

# Get a user by UPN or object ID
az ad user show --id user@domain.com

# Get groups a user belongs to
az ad user get-member-groups --id user@domain.com
```

---

## Access Packages (via Graph API)

```bash
# List all access packages
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages"

# Get a specific access package
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/<id>"

# Filter by display name
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages?\$filter=displayName eq 'PackageName'"

# Get resource roles inside a package
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/<id>/resourceRoleScopes"

# Get assignments for an access package
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?\$filter=accessPackage/id eq '<id>'"
```

---

## Required Permissions

| Task                  | Required Scope                          |
|-----------------------|-----------------------------------------|
| Read/write groups     | `Group.ReadWrite.All`                   |
| Read current user     | `User.Read`                             |
| Read access packages  | `EntitlementManagement.Read.All`        |
| Write access packages | `EntitlementManagement.ReadWrite.All`   |
