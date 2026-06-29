FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm arch-install-scripts gnupg cronie git sudo devtools && \
    pacman -Sc --noconfirm

COPY entrypoint.sh build-all.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-all.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
