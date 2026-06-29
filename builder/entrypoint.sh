#!/usr/bin/env bash
set -euo pipefail

CHROOT_DIR="/chroot"
GPG_KEY_ID_FILE="/root/.gnupg/repo-key-id"

# Init GPG
mkdir -p /root/.gnupg && chmod 700 /root/.gnupg
if [[ ! -f "$GPG_KEY_ID_FILE" ]]; then
    echo "[entrypoint] Génération de la clé GPG..."
    gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: Custom Arch Repo
Name-Email: repo@local
Expire-Date: 0
%no-protection
%commit
EOF
    gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}' > "$GPG_KEY_ID_FILE"
    echo "[entrypoint] Clé générée : $(cat "$GPG_KEY_ID_FILE")"
fi

# Init chroot de base (persisted dans un volume)
if [[ ! -f "$CHROOT_DIR/root/.initialized" ]]; then
    echo "[entrypoint] Création du chroot de base avec pacstrap..."
    mkdir -p "$CHROOT_DIR/root"

    # pacstrap sans unshare (systemd-nspawn ne fonctionne pas dans Docker)
    pacstrap "$CHROOT_DIR/root" base-devel sudo

    # pacstrap moderne ne copie pas pacman.conf — on le fait manuellement
    if [[ ! -f "$CHROOT_DIR/root/etc/pacman.conf" ]]; then
        cp /etc/pacman.conf "$CHROOT_DIR/root/etc/pacman.conf"
    fi

    # locale-gen via arch-chroot (pas systemd-nspawn)
    printf 'en_US.UTF-8 UTF-8\n' > "$CHROOT_DIR/root/etc/locale.gen"
    arch-chroot "$CHROOT_DIR/root" locale-gen

    # Utilisateur non-root pour makepkg (qui refuse de tourner en root)
    arch-chroot "$CHROOT_DIR/root" useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' \
        >> "$CHROOT_DIR/root/etc/sudoers"

    touch "$CHROOT_DIR/root/.initialized"
    echo "[entrypoint] Chroot initialisé."
fi

echo "[entrypoint] Premier build..."
build-all.sh

echo "[entrypoint] Installation du crontab..."
(crontab -l 2>/dev/null; echo "0 3 */4 * * build-all.sh >> /var/log/aur-builder.log 2>&1") \
    | sort -u | crontab -

exec crond -n
