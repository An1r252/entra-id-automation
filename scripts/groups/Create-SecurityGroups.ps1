# ============================================================
# Create-SecurityGroups.ps1
# Creates Entra ID Security Groups and sets a specified user
# as the owner of each group.
# Requires: Microsoft.Graph PowerShell SDK
#   Install: Install-Module Microsoft.Graph -Scope CurrentUser
# ============================================================

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement

# ── Group definitions ────────────────────────────────────────
# Edit this list before running.
# Owner: UPN of the user to assign as group owner (e.g. john@contoso.com)
$Groups = @(
    @{ DisplayName = "SG-AppTeam-Dev";        Description = "App team developers";             Owner = "owner1@contoso.com" }
    @{ DisplayName = "SG-AppTeam-Prod";       Description = "App team production access";      Owner = "owner1@contoso.com" }
    @{ DisplayName = "SG-CloudOps-Admins";    Description = "Cloud operations administrators"; Owner = "owner2@contoso.com" }
    @{ DisplayName = "SG-Security-Analysts";  Description = "Security analyst team";           Owner = "owner2@contoso.com" }
)
# ─────────────────────────────────────────────────────────────

# 1. Login — opens browser for interactive auth
Write-Host "`n[AUTH] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All" -NoWelcome

Write-Host "[AUTH] Connected.`n" -ForegroundColor Green

# 2. Create each group
$Results = @()

foreach ($G in $Groups) {

    Write-Host "[CREATE] $($G.DisplayName)..." -NoNewline

    # Check if group already exists
    $Existing = Get-MgGroup -Filter "displayName eq '$($G.DisplayName)'" -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Host " SKIPPED (already exists)" -ForegroundColor Yellow
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Skipped - already exists"; Id = $Existing.Id; Owner = $G.Owner }
        continue
    }

    # Resolve owner UPN to Object ID
    try {
        $OwnerUser = Get-MgUser -UserId $G.Owner -ErrorAction Stop
        $OwnerId = $OwnerUser.Id
    } catch {
        Write-Host " FAILED (owner not found: $($G.Owner))" -ForegroundColor Red
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Failed: Owner not found"; Id = $null; Owner = $G.Owner }
        continue
    }

    try {
        # Create security group (mailEnabled=false, securityEnabled=true)
        $NewGroup = New-MgGroup -BodyParameter @{
            displayName         = $G.DisplayName
            description         = $G.Description
            mailEnabled         = $false
            mailNickname        = ($G.DisplayName -replace '[^a-zA-Z0-9]', '')
            securityEnabled     = $true
            "owners@odata.bind" = @("https://graph.microsoft.com/v1.0/users/$OwnerId")
        }

        Write-Host " CREATED (Id: $($NewGroup.Id)  Owner: $($G.Owner))" -ForegroundColor Green
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Created"; Id = $NewGroup.Id; Owner = $G.Owner }

    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Failed: $_"; Id = $null; Owner = $G.Owner }
    }
}

# 3. Summary
Write-Host "`n── Summary ──────────────────────────────────────────────"
$Results | Format-Table -AutoSize

# 4. Disconnect
Disconnect-MgGraph | Out-Null
Write-Host "[AUTH] Disconnected.`n" -ForegroundColor Cyan
