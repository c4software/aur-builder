FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git curl gnupg cronie sudo && \
    pacman -Sc --noconfirm

RUN useradd -m -G wheel builder && \
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

RUN sed -i 's/^BUILDENV=.*/BUILDENV=(!distcc color !ccache check sign)/' /etc/makepkg.conf

COPY build.sh entrypoint.sh /home/builder/
RUN chmod +x /home/builder/build.sh /home/builder/entrypoint.sh && \
    chown builder:builder /home/builder/build.sh /home/builder/entrypoint.sh

USER builder

ENTRYPOINT ["/home/builder/entrypoint.sh"]
