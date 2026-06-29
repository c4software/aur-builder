# Plan : Réécriture avec makechrootpkg (devtools)

## Contexte

Le script `build-all.sh` actuel réimplémente manuellement ce que `makechrootpkg` (paquet `devtools`, outil officiel des mainteneurs Arch) fait déjà :
- Création d'un overlay tmpfs par paquet
- Exécution de `makepkg` en tant qu'utilisateur non-root dans le chroot
- Nettoyage automatique après build

`paru` et `yay` ne sont pas adaptés : ce sont des AUR helpers interactifs, conçus pour installer des paquets sur sa propre machine, pas pour alimenter un dépôt pacman signé en CI. Ils ne gèrent pas la sortie des `.pkg.tar.zst` dans un répertoire contrôlé, ni la signature.

**Gain attendu :** ~40 lignes de gestion overlay/chroot supprimées, remplacement par 1-2 appels `makechrootpkg`.

---

## Fichiers à modifier

### 1. `builder/Dockerfile`

Ajouter `devtools` à la liste des paquets installés :

```dockerfile
RUN pacman -Sy --noconfirm arch-install-scripts gnupg cronie git sudo devtools
```

### 2. `builder/entrypoint.sh`

Remplacer le bloc `pacstrap` + création manuelle du user `builder` + sudoers par `mkarchroot` :

```bash
# Avant (à supprimer) :
pacstrap /chroot/root base-devel sudo
# + génération locale, ajout user builder, sudoers...

# Après :
mkarchroot "$CHROOT_DIR/root" base-devel
```

`mkarchroot` crée un chroot propre avec `base-devel`. `makechrootpkg` gère lui-même l'utilisateur de build — pas besoin de créer `builder` manuellement.

La mise à jour du chroot de base change aussi :
```bash
# Avant :
arch-chroot "$CHROOT_DIR/root" pacman -Syu --noconfirm

# Après :
arch-nspawn "$CHROOT_DIR/root" pacman -Syu --noconfirm
```

### 3. `builder/build-all.sh`

Supprimer tout le bloc overlay (tmpfs + mount overlay + mkdir + chown + arch-chroot + umount), remplacer par :

```bash
# Clone dans /tmp/src-${pkg} (inchangé)

# Build :
cd "$build_dir"
if makechrootpkg -c -r "$CHROOT_DIR" -- -s --noconfirm; then
    for pkg_file in "$build_dir/"*.pkg.tar.zst; do
        # ... même logique de publication/signature (inchangée)
    done
else
    failed+=("$pkg")
fi

rm -rf "$build_dir"
```

Notes :
- `-c` : nettoie le chroot copy avant le build (isolation garantie)
- `-r "$CHROOT_DIR"` : utilise le chroot persistant comme base
- `--` : passe le reste des flags à `makepkg`
- `makechrootpkg` place les `.pkg.tar.zst` dans le répertoire courant (le clone git)

La logique de vérification de version, publication et signature reste **identique**.

---

## Ce qui ne change pas

- GPG signing (packages + repo-add)
- Nginx / docker-compose
- packages.conf
- Volumes Docker (chroot persistant, gpg-keys, repo)
- Le container reste `privileged` (overlayfs requiert toujours des droits élevés)
- Cron schedule

---

## Vérification

1. `docker compose build builder`
2. `docker compose up -d`
3. `docker compose logs -f builder` — vérifier que le chroot s'initialise avec `mkarchroot`
4. Vérifier qu'un paquet se build et apparaît dans `/repo/` avec sa signature `.sig`
5. Sur un client : `pacman -Sy && pacman -S google-chrome` — vérifier l'installation depuis le repo
