#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Fixing .gnupg permissions..."
sudo chown -R builder:builder /home/builder/.gnupg
sudo chmod 700 /home/builder/.gnupg

echo "[entrypoint] Starting initial build..."
/home/builder/build.sh

echo "[entrypoint] Installing crontab..."
(crontab -l 2>/dev/null; echo "0 3 */4 * * /home/builder/build.sh >> /home/builder/build.log 2>&1") \
    | sort -u | crontab -

echo "[entrypoint] Starting crond..."
exec sudo crond -n
