# 🧪 Lab midPoint — découvrir un outil IGA

![Bannière de démarrage de midPoint 4.10.5](captures/01-demarrage-4.10.5.png)

Objectif : **rejouer sur midPoint ce que j'ai déjà construit en PowerShell**, pour comprendre ce
qu'un produit IGA fait de plus que mes scripts. Ce guide est d'abord mon support d'apprentissage ;
les 5 exercices sont faits et décrits ci-dessous, avec mes captures.

> ℹ️ Les libellés de l'interface peuvent varier selon la version (4.10.5 ici). Quand un nom
> d'écran diffère de ce guide, la documentation officielle fait foi :
> https://docs.evolveum.com/midpoint/

## 0. 📋 Prérequis

- Docker Desktop **démarré** (il est arrêté si `docker ps` répond « Cannot connect »).
- ~4 Go de mémoire libres : midPoint est une application Java, plus une base PostgreSQL.
- Premier lancement : téléchargement d'environ 300 Mo.

## 1. 🚀 Démarrer

```bash
cd midpoint-lab
cp .env.example .env     # puis remplacer DB_PASSWORD par un mot de passe long et aléatoire
docker compose up -d
docker compose logs -f midpoint_server     # attendre le message de démarrage, puis Ctrl+C
```

Interface : http://localhost:8080/midpoint (accessible seulement depuis ma machine).

![Page de connexion de midPoint](captures/02-connexion.png)

🔑 **Au premier démarrage, lancer cette commande pour avoir le mot de passe**

```bash
docker compose logs midpoint_server 2>&1 | grep "Administrator initial password"
```

## 2. 👥 Ce que contient `data/utilisateurs.csv`

12 personnes fictives (domaine `example.test`). Elles sont **piégées exprès**, comme mes données
réelles le seront :

| Cas | Pourquoi c'est intéressant |
|---|---|
| E1001 et E1012 ont la **même adresse e-mail** | test de la **corrélation** : deux lignes, une identité ? |
| E1010 est `inactif` avec une `date_sortie` | **départ** (Leaver) : que devient le compte ? |
| Une hiérarchie `manager` (E1001 → E1002, E1003, E1011) | **propriétaire de revue** : qui certifie les accès de qui ? |
| 4 départements (Finance, RH, IT, Achats) | base d'un **modèle de rôles** |

## 3. 🎯 Les 5 exercices, et ce que j'ai déjà construit en PowerShell

| # | Exercice dans midPoint | À observer | Mon équivalent PowerShell |
|---|---|---|---|
| 1 | **Importer les utilisateurs** : créer une ressource « fichier CSV » pointant sur `/opt/midpoint/var/import/utilisateurs.csv`, puis lancer l'import | comment le produit sépare *l'identité* (utilisateur) du *compte* (sur la ressource) | `IAM-JML-Lifecycle` (création, Joiner) |
| 2 | **Définir un attribut faisant autorité** : décider que `matricule` identifie une personne, et traiter le doublon d'e-mail | la **corrélation** : ce que le produit décide seul, et ce qu'il me demande de trancher | `LDAP-App-Role-Audit` (inventaire) |
| 3 | **Créer 2 ou 3 rôles** (par exemple « Finance — lecture » et « IT — admin ») et les affecter par département | rôle *vs* droit, affectation automatique ou manuelle | `IAM-Access-Recertification` (rôles « alibi ») |
| 4 | **Lancer une campagne de certification** sur ces affectations ; approuver certains accès, en révoquer d'autres | **le cycle complet** : qui reçoit la revue, que se passe-t-il après une révocation | `IAM-Access-Recertification` (campagnes) |
| 5 | **Traiter le départ de E1010** : modifier `statut` et relancer la synchronisation | désactivation automatique, conservation de la trace | `IAM-JML-Lifecycle` (Leaver) |

Prévoir 1 journée au total ; les exercices 2 et 4 sont ceux qui donnent le plus matière à parler.

## 4. 📝 Ce que je note pour en parler honnêtement

À la fin de chaque exercice, j'écris **deux lignes** :

1. *Ce que j'ai fait* (précisément).
2. *Ce que le produit a fait seul* (que mon script faisait à la main).

### 📥 Exercice 1 — Importer les utilisateurs

**🛠️ Ce que j'ai fait.**

1. Créé la ressource « Source CSV RH » avec l'assistant, *à partir de zéro* (aucun modèle proposé),
   connecteur CSV, état « Actif (production) » :
   ![Informations de base de la ressource](captures/04-ressource-informations-de-base.png)
2. Configuré le connecteur : fichier `/opt/midpoint/var/import/utilisateurs.csv`, séparateur `,`,
   attribut unique `matricule`, attribut de nom `login`. midPoint a retrouvé ces réglages seul
   (« discovery »).
3. Créé le type d'objet « Compte personne CSV » : sorte *Compte*, finalité `default`, par défaut =
   vrai, classe `AccountObjectClass`, créant un *Utilisateur* :
   ![Type d'objet corrigé](captures/06-type-objet-corrige.png)
4. Écrit 6 mappings *inbound* (du CSV vers l'utilisateur) :

   ![Mappings inbound](captures/19-correspondances-inbound.png)
5. Ajouté 3 réactions de synchronisation : *non apparié → ajouter un centre* (crée l'utilisateur),
   *non lié → lier*, *lié → synchroniser* :
   ![Réactions de synchronisation](captures/14-synchronisation-reactions.png)
6. Lancé l'import depuis l'onglet *Comptes* de la ressource : **12 utilisateurs créés** (plus
   `administrator`, soit 13 dans la liste), chacun avec un compte rattaché, un matricule et un
   nom complet.
   ![Utilisateurs importés](captures/21-utilisateurs-nom-complet.png)

Le nom complet est calculé par ce script (le premier vrai « code » de ce lab) :

```groovy
basic.stringify(prenom) + ' ' + basic.stringify(input)
```

`prenom` est une source déclarée dans le mapping ; `input` est l'attribut principal (`nom`).

**⚙️ Ce que le produit a fait seul.**

- Lire la structure du fichier et proposer les réglages du connecteur.
- Séparer le **compte** (sur la ressource) de l'**utilisateur** (dans midPoint), et les relier.
- Tracer chaque modification dans le **journal d'audit** (qui, quand, avec quel résultat).

Mon script PowerShell créait les comptes, mais ne séparait pas l'identité du compte et ne
gardait aucune piste d'audit.

### 🔗 Exercice 2 — La corrélation

**🛠️ Ce que j'ai fait.**

1. Ajouté une règle de corrélation « matricule » sur le type d'objet (section *Corrélation*) :
   poids 1, palier 1, activée.
   ![Règle de corrélation](captures/22-correlation-regle-matricule.png)
2. Défini l'élément comparé : champ `personalNumber`, méthode *Exact match* (égalité stricte).
   ![Éléments de corrélation](captures/23-correlation-items.png)
3. Provoqué un cas à corréler : sur la fiche d'`amartin`, onglet *Projections*, action
   **Dissocier** (et non *Supprimer*, qui aurait effacé le compte) :
   ![Menu des projections](captures/26-projections-menu-dissocier.png)
   Le compte restait sur la ressource, orphelin (sans propriétaire ni situation) :
   ![Compte après dissociation](captures/27-compte-apres-dissociation.png)
4. Réimporté ce seul compte depuis l'onglet *Comptes* de la ressource.

**✅ Résultat :** le compte est de nouveau `LINKED` à `amartin`. Il y a toujours 13 utilisateurs
et aucun `amartin.1`.

![Compte relié par corrélation](captures/28-compte-relie-par-correlation.png)

**⚙️ Ce que le produit a fait seul.** Retrouver le bon utilisateur à partir du matricule, sans que je
désigne la cible : c'est la corrélation. Mon script PowerShell faisait cette recherche à la main.

### 🎭 Exercice 3 — Les rôles

**🛠️ Ce que j'ai fait.**

1. Créé deux rôles de type **Rôle métier** (l'assistant propose aussi *Application role*, un droit
   précis dans une application) : `Finance - lecture` et `IT - admin`, chacun avec une
   description. Je n'ai ajouté aucun droit derrière, volontairement : un rôle qui créerait un
   compte sur la ressource CSV risquerait d'écrire dans mon fichier.
   ![Les deux rôles créés](captures/30-deux-roles-crees.png)
2. Affecté ces rôles à la main, depuis l'onglet *Attributions* de chaque utilisateur :

   | Rôle | Utilisateurs |
   |---|---|
   | `Finance - lecture` | amartin, blefevre, cdubois |
   | `IT - admin` | fsimon, gmichel, jfournier |

   Deux choix voulus : `kgirard` (Finance) n'a **aucun** rôle, et `jfournier`, **inactif**, garde
   `IT - admin`. Ce sont deux cas à faire ressortir à la certification.

**⚙️ Ce que le produit a fait seul.** Séparer le **rôle** (le paquet) de l'**affectation** (le fait de
l'avoir), et garder chaque affectation consultable par personne. Mes scripts listaient des
appartenances à des groupes, sans cette distinction.

### 🔍 Exercice 4 — La campagne de certification

**🛠️ Ce que j'ai fait.**

1. Créé une définition de campagne « Revue des rôles - lab » (menu *Certification > Définitions de
   campagnes*), avec un champ d'application resserré : **utilisateurs**, **attributions** de type
   **rôle** uniquement (inductions et autres types de cibles décochés), éléments inactifs inclus.
   ![Champ d'application](captures/32-certification-champ-application.png)
2. Défini une étape de 7 jours (`P7D`) dont le relecteur est `administrator`, via la *référence au
   vérificateur par défaut*, et gardé la remédiation **automatisée**.
   ![Vérificateur par défaut](captures/34-certification-verificateur.png)
3. Créé la campagne depuis la définition, puis ouvert la première étape : **7 éléments** à
   certifier, soit mes 6 affectations plus `Superuser`, que midPoint donne à son propre
   administrateur.
   ![Vue de la campagne](captures/37-campagne-vue-7-elements.png)
4. Décidé dans *Éléments à certifier* : 6 **acceptés**, dont `Superuser` (le révoquer m'aurait
   coupé l'accès au lab), et 1 **révoqué** : `jfournier`, inactif, qui avait encore `IT - admin`.
   ![Décisions prises](captures/39-decisions-prises.png)
5. Clos la phase de révision, puis la campagne.

**Résultat :** la campagne est `CLOSED`, `jfournier` n'a plus aucune attribution, et les 6 autres
affectations sont intactes.

![Campagne close et remédiée](captures/40-campagne-close-remediee.png)

**⚙️ Ce que le produit a fait seul.**

- Construire la liste des affectations à relire à partir de mon champ d'application.
- Garder chaque décision, avec son auteur et son horodatage.
- Appliquer la révocation (remédiation automatique) à la clôture de la campagne.

Entre la décision et la clôture, l'affectation de `jfournier` existait toujours : **décider n'est
pas appliquer**. C'est ce que mes rôles « alibi » de `IAM-Access-Recertification` ne faisaient pas.

### 🚪 Exercice 5 — Le départ (Leaver)

**🛠️ Ce que j'ai fait.**

1. Constaté le point de départ : dans le CSV, E1010 (`jfournier`) est `inactif` avec une date de
   sortie, mais dans midPoint il était toujours **actif**. Je n'avais mappé que 6 colonnes, pas
   `statut`.
2. Ajouté un mapping *inbound* `statut vers activation` : de l'attribut `statut` vers
   `activation/administrativeStatus`, avec ce script (Groovy) :

   ```groovy
   input == 'inactif' ? 'disabled' : 'enabled'
   ```

   ![Mapping statut vers activation](captures/41-mapping-statut-activation.png)
3. Relancé l'import : `jfournier` est passé à **désactivé**, les autres sont restés actifs.
   ![jfournier désactivé](captures/42-jfournier-desactive.png)
4. Simulé un vrai départ : dans le CSV, passé `kgirard` (E1011) de `actif` à `inactif` avec une
   date de sortie, puis relancé l'import de son compte. Il est passé à **désactivé** à son tour.
   ![kgirard désactivé](captures/43-kgirard-desactive.png)

**✅ Résultat :** 2 utilisateurs désactivés, 11 actifs. Aucune suppression : les deux fiches et leurs
comptes sont conservés.

**⚙️ Ce que le produit a fait seul.**

- Recalculer l'état de l'utilisateur dès que la source change, sans que je touche à la fiche.
- Conserver la trace : la personne reste consultable, avec son compte et son historique.

Mon script PowerShell de départ désactivait le compte ; ici, c'est la **source RH** qui décide,
et midPoint suit.

**📊 État final du lab.** Après les 5 exercices : 13 utilisateurs, dont 12 actifs et 1 désactivé
(`jfournier`), 7 rôles (mes 2 rôles métier compris) et 1 ressource en service.

![Tableau de bord final](captures/44-tableau-de-bord.png)

## 5. ⚠️ Ce que ce lab ne m'apprend pas

- **L'échelle** : 12 personnes, pas 12 000. La qualité des données, la montée en charge et la
  gouvernance du projet n'apparaissent pas à cette taille.
- **L'intégration réelle** : ici une source CSV. Un connecteur AD/LDAP est proposé par midPoint, mais
  je ne l'ai pas encore branché (voir la section 7).

## 6. 🧹 Arrêter et nettoyer

```bash
docker compose down            # arrête, conserve les données
docker compose down -v         # arrête ET supprime base et configuration (repart de zéro)
```

Aucun port n'est exposé hors de `127.0.0.1`, et le mot de passe de la base est dans `.env`
(non partagé, droits `600`).

## 7. 🔭 Pour aller plus loin, seulement après les 5 exercices

- Brancher une vraie source : le connecteur LDAP vers un annuaire de test.
- Écrire une règle de calcul simple (mapping d'attribut) et mesurer ce qui est « configuration »
  et ce qui est « développement ».

## 📚 Origine et licences

Le `docker-compose.yml` est dérivé de [Evolveum/midpoint-docker](https://github.com/Evolveum/midpoint-docker)
(Apache-2.0). midPoint est publié par Evolveum sous EUPL-1.2 ou ultérieure. Le contenu de ce
dossier suit la licence MIT du dépôt.
