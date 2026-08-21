# 🔁 IAM Access Recertification

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![IAM](https://img.shields.io/badge/IAM-Access%20Governance-0d1117?style=for-the-badge)
![Cross Platform](https://img.shields.io/badge/Cross%20Platform-Windows%20%7C%20Linux%20%7C%20macOS-6e40c9?style=for-the-badge)

Boîte à outils PowerShell open source de gouvernance des accès IAM, inspirée des campagnes de
recertification type SailPoint IdentityIQ. Elle **ferme la boucle** de l'audit d'accès :

1. **Détecter** les violations de séparation des tâches (SoD)
2. **Repérer** les rôles "alibi" (définis mais quasi-inutilisés)
3. **Générer** une campagne de recertification à faire revoir par les propriétaires d'accès
4. **Traiter** la campagne remplie en actions de remédiation concrètes (accès à révoquer)

Prend en entrée le CSV produit par [LDAP-App-Role-Audit](https://github.com/Anne-LaureS/LDAP-App-Role-Audit)
(ou tout export au même format Application/Role/Members).

Contrairement à `LDAP-App-Role-Audit`, ces 4 scripts ne dépendent d'aucune fonctionnalité
Windows — pur traitement CSV/JSON, testable et utilisable sous Windows, Linux ou macOS avec
PowerShell 7+.

## ⚙️ Les 4 scripts

| Script | Rôle |
|---|---|
| [`Find-SoDViolations.ps1`](Find-SoDViolations.ps1) | Détecte les personnes cumulant deux accès déclarés incompatibles |
| [`Find-AlibiRoles.ps1`](Find-AlibiRoles.ps1) | Repère les rôles vides ou quasi-vides, candidats à nettoyer |
| [`New-CertificationCampaign.ps1`](New-CertificationCampaign.ps1) | Génère une feuille de revue (1 ligne par personne + accès) |
| [`Complete-CertificationCampaign.ps1`](Complete-CertificationCampaign.ps1) | Traite la feuille remplie en liste de révocations |

## ▶️ Utilisation

### 1. Détection des violations SoD

```powershell
.\Find-SoDViolations.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv -SoDRulesJson .\sod-rules.json
```

Les règles SoD sont définies dans un fichier JSON, une paire d'accès incompatibles par règle
(voir [`sod-rules.json`](sod-rules.json)) :

```json
[
  {
    "RuleName": "Nom de la règle métier",
    "Access1": "Application:Role",
    "Access2": "Application:Role"
  }
]
```

Un `Role` vide dans la clé (`"Application:"`) désigne l'accès direct à l'application elle-même
(pas via un rôle), au même format que la colonne `Role` de l'audit d'entrée.

### 2. Détection des rôles alibi

```powershell
.\Find-AlibiRoles.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv -MinMemberThreshold 1
```

Signale les rôles à 0 membre ("Vide") et ceux à `MinMemberThreshold` membre(s) ou moins
("Quasi-vide"). Ce sont des **candidats à vérifier manuellement** : sans données de dernière
activité (non disponibles via LDAP seul), le script ne peut pas confirmer qu'un rôle est
réellement obsolète, seulement qu'il mérite qu'on s'y penche.

### 3. Génération d'une campagne de recertification

```powershell
.\New-CertificationCampaign.ps1 -AuditCsv .\sample-data\LDAP_Applications_Roles_Audit.csv
```

Produit un CSV (ouvrable dans Excel/LibreOffice) avec une ligne par personne + accès, et des
colonnes vides `Reviewer`, `Decision`, `Comment` à faire remplir par le propriétaire de
l'application ou le manager concerné. `Decision` attend `Approve` ou `Revoke`.

### 4. Traitement de la campagne remplie

```powershell
.\Complete-CertificationCampaign.ps1 -CampaignCsv .\CertificationCampaign_2026-08-21.csv
```

Lit la colonne `Decision` remplie (insensible à la casse) et produit :
- un CSV des accès à révoquer ([`Remediation_Actions.csv`](Remediation_Actions.csv) par défaut)
- un résumé en console : nombre d'accès approuvés, révoqués, et non traités (lignes où
  `Decision` est resté vide ou ne vaut ni `Approve` ni `Revoke`)

## 📊 Exemple de bout en bout

Avec les données d'exemple ([`sample-data/`](sample-data)) et la règle de démo dans
[`sod-rules.json`](sod-rules.json) :

```
Find-SoDViolations.ps1     -> 1 violation : tesla cumule Scientists (accès direct) + rôle Italians
Find-AlibiRoles.ps1        -> 1 candidat  : rôle Italians (Scientists), 1 seul membre
New-CertificationCampaign  -> 14 lignes à revoir (1 par personne/accès)
Complete-CertificationCampaign -> selon les décisions saisies, liste des révocations
```

## 🔐 Sécurité & précautions

- Ces scripts ne se connectent à aucun annuaire — ils ne consomment que des CSV/JSON déjà
  exportés. Aucune donnée d'authentification en jeu ici (voir
  [LDAP-App-Role-Audit](https://github.com/Anne-LaureS/LDAP-App-Role-Audit) pour la partie
  connexion LDAP).
- Le champ `Decision` est comparé en minuscules et sans espaces superflus (`.Trim().ToLower()`)
  pour tolérer les variations de saisie manuelle (`Revoke`, `REVOKE`, `revoke `) sans faux
  négatif silencieux.
- `Find-SoDViolations.ps1` et `New-CertificationCampaign.ps1` ne sautent que les lignes sans
  aucun membre (`Members` vide) — un `Role` vide reste un accès légitime (accès direct à
  l'application) à traiter, pas une ligne à ignorer.
- Les révocations produites par `Complete-CertificationCampaign.ps1` sont une **liste
  d'actions à exécuter manuellement** (ou via votre outil de provisioning existant) — ce
  script ne modifie aucun annuaire lui-même.
