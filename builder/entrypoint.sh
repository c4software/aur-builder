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
Name-Real: Valentin Brosseau - Custom Arch Repository
Name-Email: admin@arch.local
Expire-Date: 0
%no-protection
%commit
EOF
    gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}' > "$GPG_KEY_ID_FILE"
    echo "[entrypoint] Clé générée : $(cat "$GPG_KEY_ID_FILE")"
fi

# Init chroot de base (persisted dans un volume)
if [[ ! -f "$CHROOT_DIR/root/.initialized" ]]; then
    echo "[entrypoint] Création du chroot de base avec mkarchroot..."
    mkdir -p "$CHROOT_DIR"
    mkarchroot "$CHROOT_DIR/root" base-devel
    touch "$CHROOT_DIR/root/.initialized"
    echo "[entrypoint] Chroot initialisé."
fi

echo "[entrypoint] Premier build..."
build-all.sh

echo "[entrypoint] Installation du crontab..."
(crontab -l 2>/dev/null; echo "0 3 */4 * * build-all.sh >> /var/log/aur-builder.log 2>&1") \
    | sort -u | crontab -

exec crond -n
