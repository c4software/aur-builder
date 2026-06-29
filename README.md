# AUR Builder

Repo pacman custom auto-hébergé : build des paquets AUR dans Docker et les expose via nginx.

## Architecture

```
builder  →  clone AUR + makepkg + repo-add  →  ./repo/
nginx    →  sert ./repo/ en HTTP sur :9080
```

La liste des paquets est définie dans la variable d'env `AUR_PACKAGES` du service `builder` dans `docker-compose.yml`.

## Démarrage

```bash
docker compose up -d
docker compose logs -f builder   # suivre le premier build
```

## Configuration côté client (Arch / CachyOS)

**Import de la clé GPG (une seule fois)**

```bash
sudo curl http://<ip>:9080/custom-repo.pub | sudo pacman-key --add -

FINGERPRINT=$(gpg --with-colons --import-options show-only \
  --import <(curl -s http://<ip>:9080/custom-repo.pub) \
  | awk -F: '/^fpr/{print $10; exit}')

sudo pacman-key --lsign-key "$FINGERPRINT"
```

**`/etc/pacman.conf`** — ajouter avant `[extra]` :

```ini
[custom]
SigLevel = Required DatabaseOptional
Server = http://<ip>:9080
```

```bash
sudo pacman -Sy
sudo pacman -S google-chrome slack-desktop
```

## Opérations courantes

| Action | Commande |
|---|---|
| Forcer un rebuild immédiat | `docker compose exec builder /home/builder/build.sh` |
| Voir les logs cron | `docker compose exec builder tail -f /home/builder/build.log` |
| Voir le crontab actif | `docker compose exec builder crontab -l` |
| Ajouter un paquet | Modifier `AUR_PACKAGES` dans `docker-compose.yml` + `docker compose up -d` |

## Rebuild automatique

Cron : tous les 4 jours à 3h du matin (`0 3 */4 * * /home/builder/build.sh`).  
Les paquets déjà à jour sont skippés (comparaison `pkgver-pkgrel`).
