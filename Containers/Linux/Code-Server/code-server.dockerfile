FROM debian:stable-slim

ARG VERSION

ADD https://github.com/coder/code-server/releases/download/v$VERSION/code-server_${VERSION}_arm64.deb /home

RUN ls /home 

RUN apt update && apt install systemd -y && dpkg -i /home/code-server_${VERSION}_arm64.deb && systemctl enable --now code-server@$USER