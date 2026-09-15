<#
.SYNOPSIS
    Amorce des règles SoD candidates en repérant les personnes qui cumulent un rôle à
    privilège (ex: "Admin") sur plusieurs applications différentes — utile quand l'annuaire
    modélise l'accès par paliers génériques (Admin/Standard/Lecture/...) plutôt que par rôles
    d'action fins (VendorCreate/PaymentApproval), où une comparaison de mots-clés au sein d'une
    même application ne trouve rien.

.DESCRIPTION
    Pour chaque personne, liste les applications où elle détient un rôle correspondant au
    mot-clé de privilège (insensible à la casse/accents), puis, dès qu'elle en cumule sur 2
    applications ou plus, génère une règle SoD candidate par paire d'applications concernées.

    Contrairement à un cumul au sein d'une même application (souvent normal : un admin a aussi
    accès en lecture à son propre périmètre), cumuler un rôle à privilège sur deux applications
    sans lien fonctionnel évident concentre deux domaines sensibles chez la même personne — un
    signal à faire valider par le métier, pas une violation confirmée.

.PARAMETER AuditCsv
    CSV produit par LDAP-App-Role-Audit (colonnes attendues : Application, Role, Members).

.PARAMETER PrivilegeKeyword
    Mot-clé identifiant un rôle à privilège dans le nom du rôle (ex: "Admin", "Owner").
    Insensible à la casse et aux accents. "Admin" par défaut.

.PARAMETER RulesOutputJson
    Règles candidates au format sod-rules.json — à relire, corriger et ne copier dans
    sod-rules.json QUE celles validées par le métier.

.PARAMETER EvidenceOutputCsv
    Détail par règle candidate : la ou les personnes réellement concernées aujourd'hui, pour
    prioriser la validation.

.EXAMPLE
    .\Find-CrossAppAdminOverlap.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AuditCsv,

    [string]$PrivilegeKeyword = "Admin",

    [string]$RulesOutputJson = "Candidate_SoD_Rules.json",

    [string]$EvidenceOutputCsv = "Candidate_SoD_Rules_Evidence.csv"
)

if (-not (Test-Path $AuditCsv)) {
    Write-Host "Fichier d'audit introuvable : $AuditCsv" -ForegroundColor Red
    exit 1
}

# -Encoding UTF8 ajoute le BOM sous Windows PowerShell 5.1 mais pas sous PowerShell 7+, où
# Excel (locale FR) lit alors les accents comme du Windows-1252 et les corrompt. On force le
# BOM sur les deux versions.
$csvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }

function Remove-Diacritics {
    param([string]$Text)
    if (-not $Text) { return "" }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

$auditRows = Import-Csv $AuditCsv
Write-Host "Lignes d'audit chargées : $($auditRows.Count)"

$keywordNorm = Remove-Diacritics $PrivilegeKeyword

# --- Pour chaque personne, liste des applications où elle a un rôle à privilège ---
# Clé = personne, valeur = liste d'objets {Application, AccessLabel}
$privilegedAccessByPerson = @{}

foreach ($row in $auditRows) {
    if (-not $row.Application -or -not $row.Members) { continue }
    $roleNorm = Remove-Diacritics $row.Role
    if ($roleNorm -notmatch [regex]::Escape($keywordNorm)) { continue }

    $accessLabel = if ($row.Role) { $row.Role } else { "(accès direct)" }
    $members = $row.Members -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    foreach ($person in $members) {
        if (-not $privilegedAccessByPerson.ContainsKey($person)) {
            $privilegedAccessByPerson[$person] = [System.Collections.Generic.List[object]]::new()
        }
        $privilegedAccessByPerson[$person].Add([PSCustomObject]@{
            Application = $row.Application
            AccessLabel = $accessLabel
        })
    }
}

Write-Host "Personnes avec au moins un rôle '$PrivilegeKeyword' : $($privilegedAccessByPerson.Keys.Count)"

# --- Génère une règle candidate par paire d'applications cumulées par une même personne ---
$evidenceByPair = @{}   # clé de paire non ordonnée -> liste de PSCustomObject (règle + personne)

foreach ($person in $privilegedAccessByPerson.Keys) {
    $accesses = $privilegedAccessByPerson[$person] | Sort-Object Application -Unique
    if ($accesses.Count -lt 2) { continue }   # un seul périmètre à privilège : pas de cumul cross-app

    for ($i = 0; $i -lt $accesses.Count; $i++) {
        for ($j = $i + 1; $j -lt $accesses.Count; $j++) {
            $access1 = "$($accesses[$i].Application):$($accesses[$i].AccessLabel)"
            $access2 = "$($accesses[$j].Application):$($accesses[$j].AccessLabel)"
            $pairKey = (@($access1, $access2) | Sort-Object) -join "||"

            if (-not $evidenceByPair.ContainsKey($pairKey)) {
                $evidenceByPair[$pairKey] = [PSCustomObject]@{
                    RuleName    = "Cumul cross-app '$PrivilegeKeyword' — $($accesses[$i].Application) + $($accesses[$j].Application)"
                    Access1     = $access1
                    Access2     = $access2
                    Comment     = "Cumuler un rôle '$PrivilegeKeyword' sur 2 applications sans lien fonctionnel évident concentre deux périmètres sensibles chez la même personne."
                    PeopleNames = [System.Collections.Generic.List[string]]::new()
                }
            }
            $evidenceByPair[$pairKey].PeopleNames.Add($person)
        }
    }
}

$candidates = $evidenceByPair.Values | ForEach-Object {
    [PSCustomObject]@{
        RuleName          = $_.RuleName
        Access1           = $_.Access1
        Access2           = $_.Access2
        Comment           = $_.Comment
        PeopleAffectedNow = $_.PeopleNames.Count
        PeopleNames       = ($_.PeopleNames -join "; ")
    }
}

Write-Host ""
Write-Host "=== $($candidates.Count) paire(s) candidate(s) trouvée(s) ===" -ForegroundColor Yellow

if ($candidates.Count -eq 0) {
    Write-Host "Aucun cumul cross-application détecté pour le mot-clé '$PrivilegeKeyword' —" -ForegroundColor Green
    Write-Host "essayez un autre mot-clé (-PrivilegeKeyword) si vos rôles à privilège en portent un autre." -ForegroundColor Green
    exit 0
}

# Règles au format sod-rules.json — prêtes à relire puis copier (celles validées) dans sod-rules.json
$candidates |
    Select-Object RuleName, Access1, Access2, Comment |
    ConvertTo-Json -Depth 5 |
    Out-File $RulesOutputJson -Encoding $csvEncoding

# Preuves par règle, triées pour prioriser la validation (les plus concrètes en premier)
$candidates |
    Sort-Object -Property PeopleAffectedNow -Descending |
    Export-Csv $EvidenceOutputCsv -NoTypeInformation -Encoding $csvEncoding

Write-Host "Règles candidates (à valider) -> $RulesOutputJson" -ForegroundColor Yellow
Write-Host "Preuves / priorisation         -> $EvidenceOutputCsv" -ForegroundColor Yellow
Write-Host ""
Write-Host "Rappel : ce sont des CANDIDATS issus d'un cumul cross-application réel, pas des" -ForegroundColor Yellow
Write-Host "règles métier confirmées. À faire valider avant de les copier dans sod-rules.json." -ForegroundColor Yellow
