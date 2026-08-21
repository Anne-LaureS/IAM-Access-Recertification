<#
.SYNOPSIS
    Détecte les violations de séparation des tâches (SoD — Separation of Duties) à partir
    d'un export d'audit d'accès (ex: produit par LDAP-App-Role-Audit).

.DESCRIPTION
    Reconstruit la vue par personne (qui a quels rôles, sur quelles applications) à partir
    d'un CSV d'audit au format Application/AppDescription/Role/RoleDescription/MemberCount/
    Members, puis vérifie pour chaque personne si elle cumule deux accès déclarés
    incompatibles dans un fichier de règles SoD.

.PARAMETER AuditCsv
    CSV d'audit d'accès en entrée (colonnes attendues : Application, Role, Members).

.PARAMETER SoDRulesJson
    Fichier JSON définissant les paires d'accès incompatibles. Format :
    [
      { "RuleName": "...", "Access1": "Application:Role", "Access2": "Application:Role" }
    ]

.PARAMETER OutputCsv
    CSV de sortie listant chaque violation trouvée.

.EXAMPLE
    .\Find-SoDViolations.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv -SoDRulesJson .\sod-rules.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AuditCsv,

    [Parameter(Mandatory)]
    [string]$SoDRulesJson,

    [string]$OutputCsv = "SoD_Violations.csv"
)

if (-not (Test-Path $AuditCsv)) {
    Write-Host "Fichier d'audit introuvable : $AuditCsv" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $SoDRulesJson)) {
    Write-Host "Fichier de règles SoD introuvable : $SoDRulesJson" -ForegroundColor Red
    exit 1
}

$auditRows = Import-Csv $AuditCsv
$sodRules  = Get-Content $SoDRulesJson -Raw | ConvertFrom-Json

Write-Host "Lignes d'audit chargées : $($auditRows.Count)"
Write-Host "Règles SoD chargées : $($sodRules.Count)"

# --- Reconstruction de la vue par personne : Personne -> liste de "Application:Role" ---
$accessByPerson = @{}

foreach ($row in $auditRows) {
    # Ne sauter que les lignes sans membre — PAS les lignes à Role vide : un Role vide
    # signifie "accès direct à l'application" (pas via un rôle), c'est un accès légitime à
    # part entière, pas une ligne invalide à ignorer. (-not $row.Role) serait vrai pour une
    # chaîne vide et sauterait ces lignes à tort.
    if (-not $row.Members) { continue }

    $accessKey = "$($row.Application):$($row.Role)"
    $members = $row.Members -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    foreach ($person in $members) {
        if (-not $accessByPerson.ContainsKey($person)) {
            $accessByPerson[$person] = [System.Collections.Generic.List[string]]::new()
        }
        $accessByPerson[$person].Add($accessKey)
    }
}

Write-Host "Personnes distinctes trouvées : $($accessByPerson.Keys.Count)"

# --- Application des règles SoD ---
$violations = [System.Collections.ArrayList]::new()

foreach ($person in $accessByPerson.Keys) {
    $personAccess = $accessByPerson[$person]

    foreach ($rule in $sodRules) {
        if ($personAccess -contains $rule.Access1 -and $personAccess -contains $rule.Access2) {
            [void]$violations.Add([PSCustomObject]@{
                Person   = $person
                RuleName = $rule.RuleName
                Access1  = $rule.Access1
                Access2  = $rule.Access2
            })
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | Sort-Object Person, RuleName | Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "=== $($violations.Count) violation(s) SoD trouvée(s) -> $OutputCsv ===" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "=== Aucune violation SoD trouvée ===" -ForegroundColor Green
    # On exporte quand même un fichier vide (avec en-têtes) pour que le résultat soit
    # toujours exploitable par un pipeline/script suivant, plutôt que de ne rien produire.
    [PSCustomObject]@{ Person = ""; RuleName = ""; Access1 = ""; Access2 = "" } |
        Select-Object * | Where-Object { $false } |
        Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8
}
