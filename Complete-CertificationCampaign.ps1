<#
.SYNOPSIS
    Traite une campagne de recertification remplie (générée par New-CertificationCampaign.ps1)
    et produit la liste des actions de remédiation (accès à révoquer) + un résumé.

.DESCRIPTION
    Lit le CSV de campagne une fois la colonne "Decision" remplie par les reviewers
    (valeurs attendues : Approve / Revoke, insensible à la casse). Produit :
    - un CSV des accès à révoquer (une ligne par Decision = Revoke)
    - un résumé en console : nombre d'accès revus, approuvés, révoqués, non traités

.PARAMETER CampaignCsv
    CSV de campagne rempli en entrée (colonnes : Person, Application, Role, AccessLabel,
    Reviewer, Decision, Comment).

.PARAMETER OutputCsv
    CSV de sortie listant les actions de remédiation (révocations).

.EXAMPLE
    .\Complete-CertificationCampaign.ps1 -CampaignCsv .\CertificationCampaign_2026-08-21.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CampaignCsv,

    [string]$OutputCsv = "Remediation_Actions.csv"
)

if (-not (Test-Path $CampaignCsv)) {
    Write-Host "Fichier de campagne introuvable : $CampaignCsv" -ForegroundColor Red
    exit 1
}

# -Encoding UTF8 ajoute le BOM sous Windows PowerShell 5.1 mais pas sous PowerShell 7+, où
# Excel (locale FR) lit alors les accents comme du Windows-1252 et les corrompt. On force le
# BOM sur les deux versions.
$csvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }

$campaignRows = Import-Csv $CampaignCsv
Write-Host "Lignes de campagne chargées : $($campaignRows.Count)"

$revoked   = [System.Collections.ArrayList]::new()
$approved  = 0
$untreated = [System.Collections.ArrayList]::new()

foreach ($row in $campaignRows) {
    $decision = if ($row.Decision) { $row.Decision.Trim().ToLower() } else { "" }

    switch ($decision) {
        "revoke" {
            [void]$revoked.Add([PSCustomObject]@{
                Person      = $row.Person
                Application = $row.Application
                Role        = $row.Role
                AccessLabel = $row.AccessLabel
                Reviewer    = $row.Reviewer
                Comment     = $row.Comment
            })
        }
        "approve" {
            $approved++
        }
        default {
            [void]$untreated.Add($row)
        }
    }
}

$revoked | Sort-Object Person, Application, Role | Export-Csv $OutputCsv -NoTypeInformation -Encoding $csvEncoding

Write-Host ""
Write-Host "=== Résumé de la campagne ===" -ForegroundColor Cyan
Write-Host "Accès revus au total : $($campaignRows.Count)"
Write-Host "Approuvés            : $approved" -ForegroundColor Green
Write-Host "À révoquer           : $($revoked.Count) -> $OutputCsv" -ForegroundColor Yellow
if ($untreated.Count -gt 0) {
    Write-Host "Non traités (Decision vide ou invalide) : $($untreated.Count)" -ForegroundColor Red
    Write-Host "  -> vérifier que 'Decision' contient bien 'Approve' ou 'Revoke' pour chaque ligne." -ForegroundColor Red
}
