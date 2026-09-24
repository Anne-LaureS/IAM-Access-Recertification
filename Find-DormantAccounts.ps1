<#
.SYNOPSIS
    Détecte les comptes dormants, orphelins, leavers encore actifs et désactivés qui gardent des
    accès, en croisant l'inventaire des comptes, l'audit des rôles et un référentiel RH.

.DESCRIPTION
    Quatre signaux, un par ligne de résultat (un compte peut en cumuler plusieurs) :

      Leaver encore actif        le référentiel RH dit que la personne est partie (Status=Left) mais
                                 son compte est activé ou garde des accès applicatifs
      Désactivé avec accès       compte désactivé qui reste membre d'un ou plusieurs rôles
      Orphelin                   compte absent du référentiel RH, activé ou avec des accès
      Dormant                    compte activé sans connexion depuis -DormantDays jours (ou jamais
                                 connecté depuis sa création, s'il a plus de -DormantDays jours)

    La gravité dépend des accès détenus : Élevée si un rôle contient -PrivilegeKeyword (Admin par
    défaut), Moyenne si le compte a au moins un accès applicatif, Faible sinon.

    Ne se connecte à aucun annuaire : consomme des CSV (voir les fichiers d'entrée ci-dessous),
    comme les autres scripts de ce repo.

    Limites :
      - lastLogonTimestamp est répliqué avec un décalage pouvant atteindre ~14 jours : à n'utiliser
        qu'avec des seuils de plusieurs dizaines de jours (30, 60, 90).
      - Les comptes dont le référentiel indique Type=Builtin (Administrateur, Invité, krbtgt)
        sont ignorés.
      - Sans -ReferentialCsv, les signaux « Leaver encore actif » et « Orphelin » sont impossibles
        et seuls « Désactivé avec accès » et « Dormant » sont produits.

.PARAMETER AccountsCsv
    Inventaire des comptes (Get-LdapAccountInventory.ps1 de LDAP-App-Role-Audit) : SamAccountName,
    Name, OU, Enabled, WhenCreated, LastLogon...

.PARAMETER AuditCsv
    Audit des rôles (Get-LdapAppRoleAudit.ps1, idéalement avec -ResolveNested) : Application, Role,
    Members. Les membres y sont désignés par leur nom (Name de l'inventaire).

.PARAMETER ReferentialCsv
    Référentiel RH : SamAccountName, Name, Status (Active/Left), Type (Employee/Admin/Service/Test/
    Builtin), Owner, Department, LeaveDate.

.PARAMETER DormantDays
    Seuil d'inactivité en jours (90 par défaut).

.PARAMETER AsOf
    Date de référence du calcul (aujourd'hui par défaut). Permet de rejouer un résultat à une date
    donnée.

.PARAMETER PrivilegeKeyword
    Mot-clé repérant un rôle à privilège dans son nom (Admin par défaut, insensible à la casse).

.PARAMETER OutputCsv
    CSV de sortie (Dormant_Accounts.csv par défaut).

.EXAMPLE
    .\Find-DormantAccounts.ps1 -AccountsCsv .\sample-data\Accounts_Inventory.csv -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv -ReferentialCsv .\sample-data\HR_Referential.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AccountsCsv,

    [Parameter(Mandatory)]
    [string]$AuditCsv,

    [string]$ReferentialCsv,

    [int]$DormantDays = 90,

    [datetime]$AsOf = (Get-Date).Date,

    [string]$PrivilegeKeyword = "Admin",

    [string]$OutputCsv = "Dormant_Accounts.csv"
)

foreach ($f in @($AccountsCsv, $AuditCsv)) {
    if (-not (Test-Path $f)) {
        Write-Host "Fichier introuvable : $f" -ForegroundColor Red
        exit 1
    }
}
if ($ReferentialCsv -and -not (Test-Path $ReferentialCsv)) {
    Write-Host "Référentiel RH introuvable : $ReferentialCsv" -ForegroundColor Red
    exit 1
}

$csvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }
$culture = [System.Globalization.CultureInfo]::InvariantCulture

$accounts = Import-Csv $AccountsCsv
$audit = Import-Csv $AuditCsv
Write-Host "Comptes chargés : $($accounts.Count) ; lignes d'audit : $($audit.Count)"

# Accès applicatifs par personne (nom d'objet, tel qu'affiché par l'audit)
$rolesByName = @{}
foreach ($row in $audit) {
    if (-not $row.Role) { continue }
    $members = $row.Members -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($m in $members) {
        if (-not $rolesByName.ContainsKey($m)) { $rolesByName[$m] = [System.Collections.Generic.List[string]]::new() }
        $rolesByName[$m].Add("$($row.Application):$($row.Role)")
    }
}

$refBySam = @{}
if ($ReferentialCsv) {
    foreach ($r in (Import-Csv $ReferentialCsv)) { $refBySam[$r.SamAccountName] = $r }
    Write-Host "Référentiel RH chargé : $($refBySam.Count) comptes"
}
else {
    Write-Host "ATTENTION : pas de référentiel RH (-ReferentialCsv) : les signaux 'Leaver encore actif' et 'Orphelin' sont désactivés." -ForegroundColor Yellow
}

$privPattern = [regex]::Escape($PrivilegeKeyword)
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param($Account, [string]$Signal, [string]$Detail, [object[]]$Roles, $Inactive)
    $roleList = @($Roles | Where-Object { $_ })
    $isPriv = @($roleList | Where-Object { ($_ -split ':', 2)[1] -match "(?i)$privPattern" }).Count -gt 0
    $severity = if ($isPriv) { "Élevée" } elseif ($roleList.Count -gt 0) { "Moyenne" } else { "Faible" }
    $findings.Add([PSCustomObject]@{
        SamAccountName = $Account.SamAccountName
        Name           = $Account.Name
        Signal         = $Signal
        Severity       = $severity
        Enabled        = $Account.Enabled
        LastLogon      = $Account.LastLogon
        InactiveDays   = $Inactive
        Roles          = ($roleList -join "; ")
        Detail         = $Detail
    })
}

foreach ($a in $accounts) {
    $sam = $a.SamAccountName
    $ref = if ($refBySam.ContainsKey($sam)) { $refBySam[$sam] } else { $null }
    if ($ref -and $ref.Type -eq 'Builtin') { continue }

    $enabled = ($a.Enabled -eq 'True')
    $roles = if ($rolesByName.ContainsKey($a.Name)) { @($rolesByName[$a.Name]) } else { @() }
    $state = if ($enabled) { "compte activé" } else { "compte désactivé" }
    $raised = $false

    if ($ref -and $ref.Status -eq 'Left' -and ($enabled -or $roles.Count -gt 0)) {
        Add-Finding $a "Leaver encore actif" "Parti le $($ref.LeaveDate) ; $state ; $($roles.Count) accès conservé(s)" $roles ""
        $raised = $true
    }

    if (-not $raised -and -not $enabled -and $roles.Count -gt 0) {
        Add-Finding $a "Désactivé avec accès" "Compte désactivé ; $($roles.Count) accès conservé(s)" $roles ""
    }

    if ($ReferentialCsv -and -not $ref -and ($enabled -or $roles.Count -gt 0)) {
        Add-Finding $a "Orphelin" "Absent du référentiel RH ; $state ; $($roles.Count) accès" $roles ""
    }

    if ($enabled) {
        $reference = $null
        $never = $false
        if ($a.LastLogon) { $reference = [datetime]::ParseExact($a.LastLogon, 'yyyy-MM-dd', $culture) }
        elseif ($a.WhenCreated) { $reference = [datetime]::ParseExact($a.WhenCreated, 'yyyy-MM-dd', $culture); $never = $true }
        if ($reference) {
            $days = [int]($AsOf - $reference).TotalDays
            if ($days -ge $DormantDays) {
                $detail = if ($never) { "Jamais connecté depuis la création le $($a.WhenCreated) ($days jours)" }
                          else { "Dernière connexion le $($a.LastLogon) ($days jours)" }
                Add-Finding $a "Dormant" $detail $roles $days
            }
        }
    }
}

$order = @{ "Élevée" = 0; "Moyenne" = 1; "Faible" = 2 }
$sorted = $findings | Sort-Object @{ Expression = { $order[$_.Severity] } }, Signal, SamAccountName
$sorted | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding $csvEncoding

Write-Host ""
Write-Host "=== $($findings.Count) constat(s) -> $OutputCsv ===" -ForegroundColor $(if ($findings.Count -gt 0) { 'Yellow' } else { 'Green' })
$findings | Group-Object Signal | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-28} {1}" -f $_.Name, $_.Count) }
Write-Host ("Comptes distincts concernés : {0} ; gravité Élevée : {1}" -f (($findings | Select-Object -ExpandProperty SamAccountName -Unique).Count), (@($findings | Where-Object { $_.Severity -eq 'Élevée' }).Count))
Write-Host "Rappel : ce sont des candidats à vérifier avec le propriétaire du compte, pas une confirmation." -ForegroundColor DarkGray
