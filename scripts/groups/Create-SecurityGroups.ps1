# ============================================================
# Create-SecurityGroups.ps1
# Creates Entra ID Security Groups and sets the logged-in
# user as the owner of each group.
# Requires: Microsoft.Graph PowerShell SDK
#   Install: Install-Module Microsoft.Graph -Scope CurrentUser
# ============================================================

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement

# ── Group definitions ────────────────────────────────────────
# Edit this list before running.
$Groups = @(
    @{ DisplayName = "SG-AppTeam-Dev";        Description = "App team developers" }
    @{ DisplayName = "SG-AppTeam-Prod";       Description = "App team production access" }
    @{ DisplayName = "SG-CloudOps-Admins";    Description = "Cloud operations administrators" }
    @{ DisplayName = "SG-Security-Analysts";  Description = "Security analyst team" }
)
# ─────────────────────────────────────────────────────────────

# 1. Login — opens browser for interactive auth
Write-Host "`n[AUTH] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read" -NoWelcome

# 2. Resolve the signed-in user's object ID
$Me = Get-MgContext
$CurrentUser = Get-MgUser -UserId $Me.Account
$OwnerId = $CurrentUser.Id

Write-Host "[AUTH] Signed in as: $($Me.Account)  (ObjectId: $OwnerId)`n" -ForegroundColor Green

# 3. Create each group
$Results = @()

foreach ($G in $Groups) {

    Write-Host "[CREATE] $($G.DisplayName)..." -NoNewline

    # Check if group already exists
    $Existing = Get-MgGroup -Filter "displayName eq '$($G.DisplayName)'" -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Host " SKIPPED (already exists)" -ForegroundColor Yellow
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Skipped - already exists"; Id = $Existing.Id }
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

        Write-Host " CREATED (Id: $($NewGroup.Id))" -ForegroundColor Green
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Created"; Id = $NewGroup.Id }

    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $Results += [PSCustomObject]@{ Group = $G.DisplayName; Status = "Failed: $_"; Id = $null }
    }
}

# 4. Summary
Write-Host "`n── Summary ──────────────────────────────────────────────"
$Results | Format-Table -AutoSize

# 5. Disconnect
Disconnect-MgGraph | Out-Null
Write-Host "[AUTH] Disconnected.`n" -ForegroundColor Cyan
