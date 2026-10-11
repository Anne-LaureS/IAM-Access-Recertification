#!/usr/bin/env bash
# Pilote le lab midPoint : démarrage, arrêt, nettoyage complet.
#   ./lab.sh up       démarre (crée .env avec un mot de passe aléatoire s'il n'existe pas)
#   ./lab.sh stop     arrête, conserve les données
#   ./lab.sh clean    SUPPRIME conteneurs, réseau, volumes ET .env (remise à zéro complète)
#   ./lab.sh status   état des conteneurs, volumes et .env
set -euo pipefail
cd "$(dirname "$0")"
PROJECT=midpoint-lab

volumes()    { docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT"; }
placeholder() { grep -q -E '^DB_PASSWORD=(remplacer|change)' .env 2>/dev/null; }

case "${1:-}" in
  up)
    if [ ! -f .env ]; then
      if [ -n "$(volumes)" ]; then
        echo "Des volumes d'une installation précédente existent, mais .env est absent :"
        echo "le mot de passe de la base est perdu. Lancer d'abord : ./lab.sh clean" >&2
        exit 1
      fi
      pw=$(python3 -c 'import secrets;print(secrets.token_urlsafe(30))')
      umask 077
      printf 'MP_VER=4.10.5\nDB_PASSWORD=%s\n' "$pw" > .env
      echo ".env créé avec un mot de passe aléatoire."
    fi
    if placeholder; then
      echo "DB_PASSWORD contient encore la valeur d'exemple. La remplacer dans .env." >&2
      exit 1
    fi
    docker compose up -d
    port=$(grep -E '^MP_PORT=' .env | cut -d= -f2 || true)
    echo "Interface : http://localhost:${port:-8888}/midpoint"
    echo "Mot de passe initial (premier démarrage seulement) :"
    echo "  docker compose logs midpoint_server 2>&1 | grep 'Administrator initial password'"
    ;;
  stop)
    docker compose down
    echo "Arrêté. Données conservées (volumes) : $(volumes | wc -l)."
    ;;
  clean)
    echo "Ceci supprime conteneurs, réseau, volumes (base et configuration midPoint) et .env."
    read -r -p "Taper « oui » pour confirmer : " ans
    [ "$ans" = "oui" ] || { echo "Annulé."; exit 1; }
    docker compose down -v --remove-orphans
    rm -f .env
    left=$(volumes | wc -l)
    if [ "$left" -eq 0 ]; then
      echo "Nettoyage complet : plus aucun volume, plus de .env."
    else
      echo "Volumes restants à supprimer à la main :"; volumes >&2; exit 1
    fi
    ;;
  status)
    docker compose ps
    echo "Volumes : $(volumes | wc -l)"
    [ -f .env ] && echo ".env : présent" || echo ".env : absent"
    ;;
  *)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
