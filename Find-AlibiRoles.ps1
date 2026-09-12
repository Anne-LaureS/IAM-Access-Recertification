<#
.SYNOPSIS
    Repère les rôles/applications "alibi" — définis dans l'annuaire mais avec peu ou pas de
    membres réels — à partir d'un export d'audit d'accès.

.DESCRIPTION
    Un rôle "alibi" (au sens gouvernance IAM) est un rôle créé/documenté à un moment donné
    mais qui n'est plus (ou jamais) réellement utilisé. Sans données d'activité (dernière
    connexion, dernier usage), on ne peut pas le prouver avec certitude à partir du seul LDAP
    — ce script produit des CANDIDATS à vérifier manuellement, pas une confirmation.

    Deux niveaux de signalement :
    - "Vide" (MemberCount = 0) : rôle défini, personne dedans — candidat fort.
    - "Quasi-vide" (MemberCount <= -MinMemberThreshold, hors 0) : très peu de membres —
      candidat à vérifier (accès legacy conservé pour une seule personne qui a changé de poste,
      par exemple).

.PARAMETER AuditCsv
    CSV d'audit d'accès en entrée.

.PARAMETER MinMemberThreshold
    Seuil en dessous (et y compris) duquel un rôle est signalé comme "quasi-vide". 1 par défaut.

.PARAMETER OutputCsv
    CSV de sortie.

.EXAMPLE
    .\Find-AlibiRoles.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AuditCsv,

    [int]$MinMemberThreshold = 1,

    [string]$OutputCsv = "Alibi_Roles_Candidates.csv"
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

$candidates = [System.Collections.ArrayList]::new()

foreach ($row in $auditRows) {
    # On ne signale que les lignes "Rôle" à proprement parler (pas l'appartenance directe à
    # l'application, Role vide, qui n'a pas vocation à être "alibi" au même sens).
    if (-not $row.Role) { continue }

    $count = [int]$row.MemberCount

    if ($count -eq 0) {
        [void]$candidates.Add([PSCustomObject]@{
            Application = $row.Application
            Role        = $row.Role
            MemberCount = $count
            Signal      = "Vide — aucun membre"
        })
    }
    elseif ($count -le $MinMemberThreshold) {
        [void]$candidates.Add([PSCustomObject]@{
            Application = $row.Application
            Role        = $row.Role
            MemberCount = $count
            Signal      = "Quasi-vide — $count membre(s), à vérifier"
        })
    }
}

if ($candidates.Count -gt 0) {
    $candidates | Sort-Object MemberCount, Application, Role | Export-Csv $OutputCsv -NoTypeInformation -Encoding $csvEncoding
    Write-Host ""
    Write-Host "=== $($candidates.Count) candidat(s) rôle alibi -> $OutputCsv ===" -ForegroundColor Yellow
    Write-Host "Rappel : ce sont des candidats à vérifier manuellement, pas une confirmation" -ForegroundColor Yellow
    Write-Host "(pas de donnée de dernière activité disponible via LDAP seul)." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "=== Aucun candidat rôle alibi (seuil : <= $MinMemberThreshold membre) ===" -ForegroundColor Green
}
