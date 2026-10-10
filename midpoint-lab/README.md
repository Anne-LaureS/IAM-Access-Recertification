# 🧪 Lab midPoint

Lab local pour découvrir un outil IGA (**Evolveum midPoint 4.10.5**) en rejouant sur un produit ce
que les scripts PowerShell de ce dépôt font à la main : import d'identités, corrélation, rôles,
campagne de certification, départ (Leaver).

- **Le guide** : [GUIDE.md](GUIDE.md), avec les 5 exercices et les captures.
- **Démarrer** : `cp .env.example .env`, remplacer `DB_PASSWORD`, puis `docker compose up -d`.
- **Données** : [data/utilisateurs.csv](data/utilisateurs.csv), 12 personnes fictives (`example.test`).

Il s'agit d'un lab pédagogique à petite échelle (12 personnes, une source CSV), pas d'une
référence de déploiement.

## Origine et licences

Le `docker-compose.yml` est dérivé de [Evolveum/midpoint-docker](https://github.com/Evolveum/midpoint-docker)
(Apache-2.0). midPoint est publié par Evolveum sous EUPL-1.2 ou ultérieure. Le contenu du dossier
`midpoint-lab/` suit la licence MIT du dépôt.
