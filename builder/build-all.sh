#!/usr/bin/env bash
set -euo pipefail

PACKAGES_FILE="/etc/aur-packages"
CHROOT_DIR="/chroot"
REPO_DIR="/repo"
GPGKEY=$(cat /root/.gnupg/repo-key-id)

# Mise à jour du chroot de base AVANT les builds
echo "[build] Mise à jour du chroot de base..."
arch-nspawn "$CHROOT_DIR/root" pacman -Syu --noconfirm

gpg --armor --export "$GPGKEY" > "$REPO_DIR/custom-repo.pub"

failed=()

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue

    build_dir="/tmp/src-${pkg}"
    rm -rf "$build_dir"

    echo "[build] === $pkg ==="

    git clone --depth=1 "https://aur.archlinux.org/${pkg}.git" "$build_dir"

    echo "[build:$pkg] === PKGBUILD ==="
    cat "$build_dir/PKGBUILD"
    echo "[build:$pkg] ==============="

    pkgver=$(grep -m1 '^pkgver=' "$build_dir/PKGBUILD" | cut -d= -f2- | tr -d "\"' ")
    pkgrel=$(grep -m1  '^pkgrel=' "$build_dir/PKGBUILD" | cut -d= -f2- | tr -d "\"' ")
    if grep -qE "^arch=\(['\"]any['\"]\)" "$build_dir/PKGBUILD"; then
        arch_val="any"
    else
        arch_val="x86_64"
    fi

    if [[ -f "$REPO_DIR/${pkg}-${pkgver}-${pkgrel}-${arch_val}.pkg.tar.zst" ]]; then
        echo "[build:$pkg] Déjà à jour ($pkgver-$pkgrel), ignoré."
        rm -rf "$build_dir"
        continue
    fi

    if (cd "$build_dir" && makechrootpkg -c -r "$CHROOT_DIR" -- -s --noconfirm); then

        for pkg_file in "$build_dir/"*.pkg.tar.zst; do
            [[ -f "$pkg_file" ]] || continue
            basename=$(basename "$pkg_file")

            find "$REPO_DIR" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst"     -delete
            find "$REPO_DIR" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst.sig" -delete

            cp "$pkg_file" "$REPO_DIR/"
            gpg --detach-sign --no-armor --local-user "$GPGKEY" "$REPO_DIR/$basename"
        done

        repo-add --sign --key "$GPGKEY" \
            "$REPO_DIR/custom.db.tar.gz" "$REPO_DIR/${pkg}"-*.pkg.tar.zst

        echo "[build:$pkg] OK ($pkgver-$pkgrel)"
    else
        echo "[build:$pkg] ECHEC"
        failed+=("$pkg")
    fi

    rm -rf "$build_dir"
done < "$PACKAGES_FILE"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "[build] Paquets en échec : ${failed[*]}"
    exit 1
fi
echo "[build] Terminé."
