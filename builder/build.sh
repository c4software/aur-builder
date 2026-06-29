#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/repo"
GPG_KEY_ID_FILE="$HOME/.gnupg/repo-key-id"

init_gpg() {
    if [[ -f "$GPG_KEY_ID_FILE" ]]; then
        GPGKEY=$(cat "$GPG_KEY_ID_FILE")
        echo "[gpg] Using existing key: $GPGKEY"
    else
        echo "[gpg] Generating new GPG key..."
        gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: Custom Arch Repo
Name-Email: repo@local
Expire-Date: 0
%no-protection
%commit
EOF
        GPGKEY=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
        echo "$GPGKEY" > "$GPG_KEY_ID_FILE"
        echo "[gpg] New key generated: $GPGKEY"
    fi

    echo "GPGKEY=\"$GPGKEY\"" > ~/.makepkg.conf
    gpg --armor --export "$GPGKEY" > "$REPO_DIR/custom-repo.pub"
    echo "[gpg] Public key exported to $REPO_DIR/custom-repo.pub"
}

build_package() {
    local pkg="$1"
    local build_dir="/tmp/build-${pkg}"

    echo "[build] === Building $pkg ==="

    rm -rf "$build_dir"
    git clone "https://aur.archlinux.org/${pkg}.git" "$build_dir"
    cd "$build_dir"

    # shellcheck disable=SC1091
    CARCH=x86_64 CHOST=x86_64-pc-linux-gnu source PKGBUILD

    local arch_val="${arch[0]:-x86_64}"
    if [[ "$arch_val" == "any" ]]; then
        arch_val="any"
    else
        arch_val="x86_64"
    fi

    local expected="${pkg}-${pkgver}-${pkgrel}-${arch_val}.pkg.tar.zst"

    if [[ -f "$REPO_DIR/$expected" ]]; then
        echo "[build] $pkg is already up-to-date ($expected), skipping."
        cd /
        rm -rf "$build_dir"
        return
    fi

    # Remove old versions of this package
    find "$REPO_DIR" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst" -delete
    find "$REPO_DIR" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst.sig" -delete

    GPGKEY=$(cat "$GPG_KEY_ID_FILE")
    makepkg -s --noconfirm --skippgpcheck --sign

    cp ./*.pkg.tar.zst "$REPO_DIR/"
    cp ./*.pkg.tar.zst.sig "$REPO_DIR/" 2>/dev/null || true

    repo-add --sign --key "$GPGKEY" "$REPO_DIR/custom.db.tar.gz" "$REPO_DIR/${pkg}"-*.pkg.tar.zst

    echo "[build] $pkg done."
    cd /
    rm -rf "$build_dir"
}

main() {
    if [[ -z "${AUR_PACKAGES:-}" ]]; then
        echo "[error] AUR_PACKAGES env var is not set or empty"
        exit 1
    fi

    init_gpg

    local failed=()
    for pkg in $AUR_PACKAGES; do
        if ! build_package "$pkg"; then
            echo "[error] Failed to build $pkg"
            failed+=("$pkg")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "[done] Completed with errors. Failed packages: ${failed[*]}"
        exit 1
    fi

    echo "[done] All packages built successfully."
}

main
