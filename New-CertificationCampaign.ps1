<#
.SYNOPSIS
    Génère une feuille de recertification des accès (1 ligne par personne + application/rôle)
    à partir d'un export d'audit d'accès — à faire remplir par les reviewers (managers/
    propriétaires d'application).

.DESCRIPTION
    Éclate chaque ligne de l'audit (qui peut lister plusieurs personnes dans "Members") en
    une ligne par personne, et ajoute les colonnes vides à remplir par le reviewer :
    Decision (Approve/Revoke), Reviewer, Comment.

.PARAMETER AuditCsv
    CSV d'audit d'accès en entrée.

.PARAMETER OutputCsv
    CSV de campagne en sortie, à ouvrir dans Excel/LibreOffice pour la revue.

.EXAMPLE
    .\New-CertificationCampaign.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AuditCsv,

    [string]$OutputCsv = "CertificationCampaign_$(Get-Date -Format 'yyyy-MM-dd').csv"
)

if (-not (Test-Path $AuditCsv)) {
    Write-Host "Fichier d'audit introuvable : $AuditCsv" -ForegroundColor Red
    exit 1
}

# -Encoding UTF8 ajoute le BOM sous Windows PowerShell 5.1 mais pas sous PowerShell 7+, où
# Excel (locale FR) lit alors les accents comme du Windows-1252 et les corrompt. On force le
# BOM sur les deux versions.
$csvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }

$auditRows = Import-Csv $AuditCsv
Write-Host "Lignes d'audit chargées : $($auditRows.Count)"

$campaignRows = [System.Collections.ArrayList]::new()

foreach ($row in $auditRows) {
    if (-not $row.Members) { continue }

    $members = $row.Members -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $accessLabel = if ($row.Role) { "$($row.Application) / $($row.Role)" } else { "$($row.Application) (accès direct)" }

    foreach ($person in $members) {
        [void]$campaignRows.Add([PSCustomObject]@{
            Person      = $person
            Application = $row.Application
            Role        = $row.Role
            AccessLabel = $accessLabel
            Reviewer    = ""
            Decision    = ""   # à remplir : Approve / Revoke
            Comment     = ""
        })
    }
}

$campaignRows |
    Sort-Object Person, Application, Role |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding $csvEncoding

Write-Host ""
Write-Host "=== Campagne générée : $OutputCsv ($($campaignRows.Count) lignes à revoir) ===" -ForegroundColor Green
Write-Host "Remplir la colonne 'Decision' (Approve / Revoke) puis lancer Complete-CertificationCampaign.ps1"
