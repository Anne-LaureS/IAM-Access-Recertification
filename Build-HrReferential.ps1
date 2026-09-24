<#
.SYNOPSIS
    Reconstruit le référentiel RH utilisé par Find-DormantAccounts.ps1 à partir de sources
    indépendantes de l'annuaire : un état de base du personnel, les flux RH rejoués dans l'ordre, et
    un registre des comptes techniques.

.DESCRIPTION
    Un référentiel tiré de l'annuaire lui-même ne peut pas révéler un orphelin : il faut des sources
    qui ne viennent pas de l'AD. Ce script assemble :

      1. un état de base du personnel (-BaselineCsv) : les personnes déjà connues avant les flux
         (SamAccountName, Name, Status Active/Left, Department, LeaveDate) ;
      2. les flux RH (-HRFeedCsv), rejoués dans l'ordre donné, au format d'IAM-JML-Lifecycle :
           Joiner -> personne active (identifiant calculé comme New-Joiner.ps1 : 1re lettre du prénom
                     + nom, en minuscules sans accents, suffixe numérique en cas de collision)
           Mover  -> département mis à jour
           Leaver -> Status = Left
           DeviceLost / DeviceFound -> ignorés (le matériel n'est pas une identité)
      3. un registre des comptes techniques (-RegisterCsv) : comptes admin, service, test et
         intégrés, avec leur type et leur propriétaire. Dans une organisation réelle, c'est la CMDB
         ou le registre IT, pas le SIRH.

    Un compte de l'annuaire absent de ces sources est un orphelin.

    Limite : les flux ne portent pas de date de départ ; LeaveDate n'est renseigné que pour les
    personnes de l'état de base.

.PARAMETER BaselineCsv
    État de base : SamAccountName, Name, Status, Department, LeaveDate.

.PARAMETER HRFeedCsv
    Un ou plusieurs flux RH, dans l'ordre chronologique.

.PARAMETER RegisterCsv
    Registre des comptes techniques : SamAccountName, Name, Type (Admin/Service/Test/Builtin), Owner,
    Description.

.PARAMETER OutputCsv
    Référentiel produit : SamAccountName, Name, Status, Type, Owner, Department, LeaveDate.

.EXAMPLE
    .\Build-HrReferential.ps1 -BaselineCsv .\sample-data\HR_Baseline.csv -HRFeedCsv .\sample-data\HR_Feed_Sample.csv, .\sample-data\HR_Feed_Banque.csv, .\sample-data\HR_Feed_Banque_Reprise.csv -RegisterCsv .\sample-data\Technical_Accounts_Register.csv -OutputCsv .\sample-data\HR_Referential.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselineCsv,

    [Parameter(Mandatory)]
    [string[]]$HRFeedCsv,

    [string]$RegisterCsv,

    [string]$OutputCsv = "HR_Referential.csv"
)

foreach ($f in (@($BaselineCsv) + $HRFeedCsv + @($RegisterCsv | Where-Object { $_ }))) {
    if (-not (Test-Path $f)) {
        Write-Host "Fichier introuvable : $f" -ForegroundColor Red
        exit 1
    }
}

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
    return $sb.ToString()
}

function Get-CandidateSam {
    param([string]$FirstName, [string]$LastName)
    $first = (Remove-Diacritics $FirstName).Substring(0, 1)
    $last = (Remove-Diacritics $LastName) -replace '[^A-Za-z]', ''
    return ($first + $last).ToLowerInvariant()
}

$people = [ordered]@{}

foreach ($row in (Import-Csv $BaselineCsv)) {
    $people[$row.SamAccountName] = [PSCustomObject]@{
        SamAccountName = $row.SamAccountName
        Name           = $row.Name
        Status         = $row.Status
        Type           = "Employee"
        Owner          = ""
        Department     = $row.Department
        LeaveDate      = $row.LeaveDate
    }
}
$baselineCount = $people.Count

$joiners = 0; $movers = 0; $leavers = 0
foreach ($feed in $HRFeedCsv) {
    foreach ($row in (Import-Csv $feed)) {
        switch ($row.ActionType) {
            "Joiner" {
                $candidate = Get-CandidateSam $row.FirstName $row.LastName
                $sam = $candidate
                $i = 1
                while ($people.Contains($sam)) { $i++; $sam = "$candidate$i" }
                $people[$sam] = [PSCustomObject]@{
                    SamAccountName = $sam
                    Name           = "$($row.FirstName) $($row.LastName)"
                    Status         = "Active"
                    Type           = "Employee"
                    Owner          = ""
                    Department     = $row.Department
                    LeaveDate      = ""
                }
                $joiners++
            }
            "Mover" {
                if ($people.Contains($row.SamAccountName)) {
                    $people[$row.SamAccountName].Department = $row.NewDepartment
                    $movers++
                }
                else { Write-Host "ATTENTION : Mover sur un compte inconnu du référentiel : $($row.SamAccountName)" -ForegroundColor Yellow }
            }
            "Leaver" {
                if ($people.Contains($row.SamAccountName)) {
                    $people[$row.SamAccountName].Status = "Left"
                    $leavers++
                }
                else { Write-Host "ATTENTION : Leaver sur un compte inconnu du référentiel : $($row.SamAccountName)" -ForegroundColor Yellow }
            }
        }
    }
}

$technical = 0
if ($RegisterCsv) {
    foreach ($row in (Import-Csv $RegisterCsv)) {
        if ($people.Contains($row.SamAccountName)) {
            Write-Host "ATTENTION : $($row.SamAccountName) figure à la fois dans le personnel et dans le registre technique : le registre est ignoré pour ce compte." -ForegroundColor Yellow
            continue
        }
        $people[$row.SamAccountName] = [PSCustomObject]@{
            SamAccountName = $row.SamAccountName
            Name           = $row.Name
            Status         = "Active"
            Type           = $row.Type
            Owner          = $row.Owner
            Department     = ""
            LeaveDate      = ""
        }
        $technical++
    }
}

$people.Values | Sort-Object Type, SamAccountName | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding $csvEncoding

Write-Host "=== Référentiel RH reconstruit : $($people.Count) comptes -> $OutputCsv ===" -ForegroundColor Green
Write-Host "  état de base : $baselineCount ; joiners : $joiners ; movers : $movers ; leavers : $leavers ; comptes techniques : $technical"
