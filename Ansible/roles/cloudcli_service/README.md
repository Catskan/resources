# Rôle `cloudcli_service`

Service systemd (sur le **CT hôte** `claude_code_hosts`) pour **cloudcli** = Claude Code WebUI
(`@cloudcli-ai/cloudcli`). cloudcli s'exécute **dans** le conteneur Docker `claude-code`
via `docker exec` (node + CLI `claude` + `~/.claude` + `~/.claude.json` y sont configurés) ;
le CT hôte n'a ni node ni cloudcli.

## Ce que fait le rôle

- Dépose `/usr/local/bin/cloudcli-svc` (start/stop, arrêt propre par pidfile — pas de `pkill`, absent du conteneur).
- Dépose `/etc/systemd/system/claudwebui.service` (`Restart=always`, `After/Requires=docker.service`).
- Active le service ; **le démarre uniquement si cloudcli est déjà dans l'image** (sinon avertit, pour éviter un crash-loop).

## Intégration

Ajouté au play `claude_code_hosts` de `main_wyse_playbook.yml` :

```yaml
roles:
  - role: claude_code_host
  - role: cloudcli_service
```

→ déployé par `make claude-code` (ou `make wyse`).

## Prérequis de persistance (À FAIRE dans le kit `nas-claude-code`, hors de ce rôle)

1. **Dockerfile** (après la ligne `RUN npm install -g @ralph-orchestrator/ralph-cli`) :
   ```dockerfile
   RUN npm install -g @cloudcli-ai/cloudcli
   ```
   puis rebuild l'image. Sans ça, le service reste _activé mais non démarré_ (garde-fou).
2. **docker-compose.yml**, service `claude-code`, ajouter le volume :
   ```yaml
   - ${CLAUDE_DATA:-/volume1/Aurelien/AI/Claude-data}/cloudcli:/root/.cloudcli
   ```
   → la DB `auth.db` (comptes UI) persiste au recreate du conteneur.

## Accès & sécurité

- UI : `http://192.168.1.96:3001` (`HOST=0.0.0.0` → LAN + clients VPN Freebox uniquement, **pas d'expo Internet**).
- ⚠️ L'UI permet de spawner `claude` et des terminaux (= shell complet) → **créer le compte admin au 1er lancement**, accès via VPN seulement.

## Variables (defaults)

`cloudcli_container` (claude-code), `cloudcli_service_name` (claudwebui), `cloudcli_port` (3001),
`cloudcli_host` (0.0.0.0), `cloudcli_pidfile` (/run/cloudcli.pid).
