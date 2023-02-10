FROM debian:stable-slim

ARG VERSION

ADD https://github.com/coder/code-server/releases/download/v$VERSION/code-server_${VERSION}_amd64.deb /home/Downloads

RUN dpkg -i /home/Downloads/code-server_${VERSION}_amd64.deb && systemctl enable --now code-server@$USER