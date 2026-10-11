[← Retour au README](../README.md)

# 🎯 Prise en main de midPoint : 5 exercices sur un CSV fictif

## 👥 Jeu de données

`data/utilisateurs.csv` contient 12 personnes fictives (domaine `example.test`), construites avec des
cas que l'on rencontre dans des données RH réelles :

| Cas | Ce qu'il permet de tester |
|---|---|
| E1001 et E1012 partagent la même adresse e-mail | le choix de l'identifiant de corrélation |
| E1010 est `inactif`, avec une date de sortie | le traitement d'un départ |
| une hiérarchie `manager` | la désignation d'un relecteur |
| 4 départements | la construction d'un modèle de rôles |

## 📋 Les exercices

Chaque exercice est détaillé ci-dessous, avec ses captures.

<details>
<summary>📥 <b>1. Import des identités</b> : ressource CSV, mappings, synchronisation</summary>

1. Ressource « Source CSV RH » créée à partir de zéro, connecteur CSV, état *Actif (production)*.
   ![Ressource](../captures/04-ressource-informations-de-base.png)
2. Connecteur : fichier `/opt/midpoint/var/import/utilisateurs.csv`, séparateur `,`, attribut unique
   `matricule`, attribut de nom `login` (réglages retrouvés par la découverte automatique).
3. Type d'objet « Compte personne CSV » : sorte *Compte*, type par défaut, créant un *Utilisateur*.
   ![Type d'objet](../captures/06-type-objet-corrige.png)
4. Six mappings *inbound*, du CSV vers l'utilisateur :
   ![Mappings](../captures/19-correspondances-inbound.png)
5. Trois réactions de synchronisation : *non apparié* crée l'utilisateur, *non lié* lie, *lié*
   synchronise.
   ![Réactions](../captures/14-synchronisation-reactions.png)
6. Import depuis l'onglet *Comptes* : 12 utilisateurs, plus `administrator`.
   ![Utilisateurs](../captures/21-utilisateurs-nom-complet.png)

Le nom complet est calculé par un script Groovy (`prenom` est une source déclarée, `input` est
l'attribut principal `nom`) :

```groovy
basic.stringify(prenom) + ' ' + basic.stringify(input)
```

</details>

<details>
<summary>🔗 <b>2. Corrélation</b> : retrouver la bonne identité à partir du matricule</summary>

1. Règle de corrélation sur le type d'objet : poids 1, palier 1, activée.
   ![Règle](../captures/22-correlation-regle-matricule.png)
2. Élément comparé : `personalNumber`, méthode *Exact match*.
   ![Éléments](../captures/23-correlation-items.png)
3. Pour provoquer un cas à corréler, le compte d'`amartin` est dissocié (et non supprimé) depuis
   l'onglet *Projections*.
   ![Dissociation](../captures/26-projections-menu-dissocier.png)
   Le compte reste sur la ressource, orphelin :
   ![Orphelin](../captures/27-compte-apres-dissociation.png)
4. Réimport de ce seul compte : il est de nouveau `LINKED` à `amartin`, il y a toujours 13
   utilisateurs et aucun doublon.
   ![Relié](../captures/28-compte-relie-par-correlation.png)

</details>

<details>
<summary>🎭 <b>3. Rôles</b> : deux rôles métier et six affectations</summary>

Deux rôles de type *Rôle métier*, sans droit technique derrière : ils servent à la certification de
l'exercice suivant, pas à provisionner des comptes.

![Rôles](../captures/30-deux-roles-crees.png)

| Rôle | Utilisateurs |
|---|---|
| `Finance - lecture` | amartin, blefevre, cdubois |
| `IT - admin` | fsimon, gmichel, jfournier |

`kgirard` (Finance) n'a volontairement aucun rôle, et `jfournier`, inactif, garde `IT - admin` : deux
cas destinés à ressortir à la certification.

</details>

<details>
<summary>🔍 <b>4. Campagne de certification</b> : relecture, décision, remédiation</summary>

1. Définition de campagne : utilisateurs, attributions de type rôle uniquement, éléments inactifs
   inclus.
   ![Périmètre](../captures/32-certification-champ-application.png)
2. Une étape de 7 jours (`P7D`), relecteur `administrator`, remédiation automatisée.
   ![Relecteur](../captures/34-certification-verificateur.png)
3. La campagne remonte 7 éléments : les 6 affectations ci-dessus et `Superuser`, que midPoint donne à
   son propre administrateur.
   ![Campagne](../captures/37-campagne-vue-7-elements.png)
4. Décisions : 6 acceptées (dont `Superuser`), 1 révoquée : `IT - admin` pour `jfournier`.
   ![Décisions](../captures/39-decisions-prises.png)
5. Clôture de la phase puis de la campagne : la révocation est appliquée.
   ![Clôture](../captures/40-campagne-close-remediee.png)

Tant que la campagne n'est pas close, l'affectation révoquée existe encore : une décision n'est pas
une remédiation.

</details>

<details>
<summary>🚪 <b>5. Départ (Leaver)</b> : l'état de la source RH pilote l'activation</summary>

La colonne `statut` n'était pas mappée : `jfournier` (inactif dans le CSV) restait actif dans
midPoint. Un mapping *inbound* vers `activation/administrativeStatus` règle cela :

```groovy
input == 'inactif' ? 'disabled' : 'enabled'
```

![Mapping](../captures/41-mapping-statut-activation.png)

Après réimport, `jfournier` est désactivé :
![jfournier](../captures/42-jfournier-desactive.png)

Pour simuler un vrai départ, `kgirard` passe à `inactif` dans le CSV puis le compte est réimporté :
![kgirard](../captures/43-kgirard-desactive.png)

Aucune suppression : les fiches et les comptes restent consultables.

Après avoir remis le CSV d'origine et réimporté : 13 utilisateurs, dont 12 actifs et 1 désactivé
(`jfournier`).

![Tableau de bord](../captures/44-tableau-de-bord.png)

</details>

## ⚠️ Points d'attention

- **La cible du matricule** est `personalNumber`.
- **`Superuser` entre dans le périmètre** d'une campagne sur « tous les utilisateurs » : le révoquer
  coupe l'accès à la console.
- **Dissocier n'est pas supprimer** : *Supprimer* un compte efface aussi la ligne dans une source
  CSV accessible en écriture.
