# 🧪 midPoint Lab : gouvernance des identités sur une plateforme IGA

![midPoint](https://img.shields.io/badge/midPoint-4.10.5-0b6fa4?style=for-the-badge)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![IAM](https://img.shields.io/badge/IAM-Gouvernance%20des%20acc%C3%A8s-0d1117?style=for-the-badge)

![Démarrage de midPoint 4.10.5](captures/01-demarrage-4.10.5.png)

Ce laboratoire rejoue sur une plateforme **IGA** (*Identity Governance and Administration*,
[Evolveum midPoint](https://evolveum.com/midpoint/)) le cycle de vie et la recertification des accès
que les scripts PowerShell de ce dépôt traitent à la main. L'objectif est de comparer les deux
approches sur l'automatisation, la gouvernance, la traçabilité et la remédiation.

Tout est local, reproductible en une commande, et alimenté par des données **fictives**.

## Résultats

| # | Exercice | Résultat observé |
|---|---|---|
| 1 | Import des identités depuis un CSV RH | 12 utilisateurs créés, chacun rattaché à son compte source |
| 2 | Corrélation sur le matricule | un compte dissocié est retrouvé automatiquement, sans doublon |
| 3 | Modèle de rôles | 2 rôles métier, 6 affectations |
| 4 | Campagne de certification | 7 éléments relus, 1 révocation appliquée à la clôture |
| 5 | Départ (Leaver) | l'état « inactif » de la source RH désactive l'utilisateur, sans le supprimer |

## Architecture

```mermaid
flowchart LR
    CSV[("utilisateurs.csv<br/>source RH fictive")] -->|connecteur CSV<br/>mappings inbound| MP
    subgraph MP["midPoint 4.10.5"]
        direction TB
        R[Ressource] --> C[Corrélation<br/>matricule] --> U[Utilisateurs] --> RO[Rôles<br/>métier] --> CA[Campagne de<br/>certification]
    end
    MP --- PG[("PostgreSQL 16")]
    CA -->|remédiation<br/>automatique| U
```

## Démarrage

**Prérequis** : Docker Desktop démarré, environ 4 Go de mémoire libres, 300 Mo à télécharger au
premier lancement.

```bash
cd midpoint-lab
cp .env.example .env      # remplacer DB_PASSWORD par un mot de passe long et aléatoire
docker compose up -d
docker compose logs -f midpoint_server    # attendre le message de démarrage, puis Ctrl+C
```

Interface : <http://localhost:8080/midpoint> (liée à `127.0.0.1`, non exposée).

![Page de connexion](captures/02-connexion.png)

Le compte est `administrator`. midPoint n'a plus de mot de passe par défaut depuis la 4.8.1 : il en
génère un au premier démarrage, lisible dans ses journaux.

```bash
docker compose logs midpoint_server 2>&1 | grep "Administrator initial password"
```

## Jeu de données

`data/utilisateurs.csv` contient 12 personnes fictives (domaine `example.test`), construites avec des
cas que l'on rencontre dans des données RH réelles :

| Cas | Ce qu'il permet de tester |
|---|---|
| E1001 et E1012 partagent la même adresse e-mail | le choix de l'identifiant de corrélation |
| E1010 est `inactif`, avec une date de sortie | le traitement d'un départ |
| une hiérarchie `manager` | la désignation d'un relecteur |
| 4 départements | la construction d'un modèle de rôles |

## Les exercices

Chaque exercice est détaillé ci-dessous, avec ses captures.

<details>
<summary><b>1. Import des identités</b> : ressource CSV, mappings, synchronisation</summary>

1. Ressource « Source CSV RH » créée à partir de zéro, connecteur CSV, état *Actif (production)*.
   ![Ressource](captures/04-ressource-informations-de-base.png)
2. Connecteur : fichier `/opt/midpoint/var/import/utilisateurs.csv`, séparateur `,`, attribut unique
   `matricule`, attribut de nom `login` (réglages retrouvés par la découverte automatique).
3. Type d'objet « Compte personne CSV » : sorte *Compte*, par défaut, créant un *Utilisateur*.
   ![Type d'objet](captures/06-type-objet-corrige.png)
4. Six mappings *inbound*, du CSV vers l'utilisateur :
   ![Mappings](captures/19-correspondances-inbound.png)
5. Trois réactions de synchronisation : *non apparié* crée l'utilisateur, *non lié* lie, *lié*
   synchronise.
   ![Réactions](captures/14-synchronisation-reactions.png)
6. Import depuis l'onglet *Comptes* : 12 utilisateurs, plus `administrator`.
   ![Utilisateurs](captures/21-utilisateurs-nom-complet.png)

Le nom complet est calculé par un script Groovy (`prenom` est une source déclarée, `input` est
l'attribut principal `nom`) :

```groovy
basic.stringify(prenom) + ' ' + basic.stringify(input)
```

</details>

<details>
<summary><b>2. Corrélation</b> : retrouver la bonne identité à partir du matricule</summary>

1. Règle de corrélation sur le type d'objet : poids 1, palier 1, activée.
   ![Règle](captures/22-correlation-regle-matricule.png)
2. Élément comparé : `personalNumber`, méthode *Exact match*.
   ![Éléments](captures/23-correlation-items.png)
3. Pour provoquer un cas à corréler, le compte d'`amartin` est dissocié (et non supprimé) depuis
   l'onglet *Projections*.
   ![Dissociation](captures/26-projections-menu-dissocier.png)
   Le compte reste sur la ressource, orphelin :
   ![Orphelin](captures/27-compte-apres-dissociation.png)
4. Réimport de ce seul compte : il est de nouveau `LINKED` à `amartin`, il y a toujours 13
   utilisateurs et aucun doublon.
   ![Relié](captures/28-compte-relie-par-correlation.png)

</details>

<details>
<summary><b>3. Rôles</b> : deux rôles métier et six affectations</summary>

Deux rôles de type *Rôle métier*, sans droit technique derrière (un rôle qui créerait un compte sur
la ressource CSV écrirait dans le fichier source) :

![Rôles](captures/30-deux-roles-crees.png)

| Rôle | Utilisateurs |
|---|---|
| `Finance - lecture` | amartin, blefevre, cdubois |
| `IT - admin` | fsimon, gmichel, jfournier |

`kgirard` (Finance) n'a volontairement aucun rôle, et `jfournier`, inactif, garde `IT - admin` : deux
cas destinés à ressortir à la certification.

</details>

<details>
<summary><b>4. Campagne de certification</b> : relecture, décision, remédiation</summary>

1. Définition de campagne : utilisateurs, attributions de type rôle uniquement, éléments inactifs
   inclus.
   ![Périmètre](captures/32-certification-champ-application.png)
2. Une étape de 7 jours (`P7D`), relecteur `administrator`, remédiation automatisée.
   ![Relecteur](captures/34-certification-verificateur.png)
3. La campagne remonte 7 éléments : les 6 affectations ci-dessus et `Superuser`, que midPoint donne à
   son propre administrateur.
   ![Campagne](captures/37-campagne-vue-7-elements.png)
4. Décisions : 6 acceptées (dont `Superuser`), 1 révoquée : `IT - admin` pour `jfournier`.
   ![Décisions](captures/39-decisions-prises.png)
5. Clôture de la phase puis de la campagne : la révocation est appliquée.
   ![Clôture](captures/40-campagne-close-remediee.png)

Tant que la campagne n'est pas close, l'affectation révoquée existe encore : une décision n'est pas
une remédiation.

</details>

<details>
<summary><b>5. Départ (Leaver)</b> : l'état de la source RH pilote l'activation</summary>

La colonne `statut` n'était pas mappée : `jfournier` (inactif dans le CSV) restait actif dans
midPoint. Un mapping *inbound* vers `activation/administrativeStatus` règle cela :

```groovy
input == 'inactif' ? 'disabled' : 'enabled'
```

![Mapping](captures/41-mapping-statut-activation.png)

Après réimport, `jfournier` est désactivé :
![jfournier](captures/42-jfournier-desactive.png)

Pour simuler un vrai départ, `kgirard` passe à `inactif` dans le CSV puis le compte est réimporté :
![kgirard](captures/43-kgirard-desactive.png)

Aucune suppression : les fiches et les comptes restent consultables.

État final après restauration du CSV d'origine :

![Tableau de bord](captures/44-tableau-de-bord.png)

</details>

## Comparaison avec les scripts PowerShell du dépôt

| Aspect | Scripts du dépôt | midPoint |
|---|---|---|
| Création et rattachement des comptes | via CSV et scripts | séparation identité / compte, liens gérés par le produit |
| Recherche de la bonne personne | à écrire dans le script | règle de corrélation déclarative |
| Revue des accès | feuille CSV remplie à la main | campagne avec relecteur, décisions horodatées |
| Application des révocations | liste d'actions (`Remediation_Actions.csv`) à exécuter ailleurs | remédiation appliquée à la clôture de la campagne |
| Traçabilité | fichiers produits par les scripts | journal d'audit de chaque opération |

## Points d'attention

- **`employeeNumber` est déprécié depuis la 4.8** : la cible du matricule est `personalNumber`.
- **`Superuser` entre dans le périmètre** d'une campagne sur « tous les utilisateurs » : le révoquer
  coupe l'accès à la console.
- **Dissocier n'est pas supprimer** : *Supprimer* un compte efface aussi la ligne dans une source
  CSV accessible en écriture.

## Limites

- Échelle réduite : 12 personnes, une seule source CSV, un seul relecteur.
- Les rôles ne portent pas de droits techniques réels.
- L'affectation automatique par département n'est pas faite : les rôles sont affectés à la main.
- La corrélation sur l'e-mail (cas E1001 / E1012) n'a pas été testée.

## Suite prévue

- Connecteur **AD/LDAP** vers un annuaire de test.
- **SSO OIDC** de la console midPoint avec un tenant Okta.
- Connecteur **Okta** communautaire (`net.tirasa.connid.bundles.okta`), dont la compatibilité avec la
  4.10 reste à vérifier.

## Arrêt et nettoyage

```bash
docker compose down        # arrête, conserve les données
docker compose down -v     # arrête et supprime la base et la configuration
```

## Origine et licences

Le `docker-compose.yml` est dérivé de [Evolveum/midpoint-docker](https://github.com/Evolveum/midpoint-docker)
(Apache-2.0). midPoint est publié par Evolveum sous EUPL-1.2 ou ultérieure. Le contenu de ce dossier
suit la licence MIT du dépôt.
