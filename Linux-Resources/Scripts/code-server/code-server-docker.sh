docker run -d --name code-server -p 127.0.0.1:5454:8080 \
  -v "/volume1/docker/code-server/config:/config" \
  -e "DOCKER_USER=$USER" \
  -e PUID=1026 \
  -e PGID=100 \
  -e TZ=Europe/Bucharest \
  -e PASSWORD=mapn.fr \
  -e SUDO_PASSWORD=mapn.fr \



docker run -d --name=codeserver \
-p 8377:8443 \
-e PUID=1034 \
-e PGID=100 \
-e TZ=Europe/Paris \
-e PASSWORD=mapn.fr \
-e PROXY_DOMAIN=codeserver.mapn.fr \
-e SUDO_PASSWORD=mapn.fr \
-v "/volume1/docker/code-server/config:/config" \
--restart always \
codercom/code-server:latest
