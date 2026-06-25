# vinted-bot — mémo Claude

Snapshot du projet pour reprise en session Claude future. Le **code source vit sur le NAS Synology**, pas dans ce repo — cette page n'est qu'un index/mémoire pour comprendre quoi va où.

> Dernier update : 2026-06-25 — après le run du 17/06 qui a optimisé 30 items Aurélien + 54 items Amandine sans flag DataDome durable.

## Localisation du code

- **NAS** (source de vérité) : `/volume1/Aurelien/Scripts/vinted-bot/` (DS716+II, 8 Go)
- **Mac** (accès SMB) : `/Volumes/Aurelien/Scripts/vinted-bot/` quand le partage est monté
- **Pas dans Git** : le code est versionné localement sur le NAS mais n'est **pas** poussé sur GitHub (contient cookies + tokens en clair dans `.env.aurelien` / `.env.amandine` et `data-*/cookies/vinted-cookies.json`)

## Ce que fait le projet

Bot Vinted en Python qui :

1. **Bumper** — remonte les annonces via `delete + recreate` (Vinted a tué l'endpoint `/bump` officiel), avec transformations photo anti-perceptual-hash (crop 0–2 %, micro-rotation ≤0.4°, JPEG ré-encode pour bouger les MD5).
2. **Optimizer** — un LLM (Mistral Small 24B via LM Studio sur le PC Windows distant) repropose **titres + descriptions** des annonces. Pipeline en deux temps : `--generate` propose, l'utilisateur valide dans la **WebUI** (port 8089), puis `--apply` pousse les changements validés sur Vinted (PUT `/api/v2/item_upload/items/<id>`).
3. **Multi-compte** — Aurélien (user_id `20575548`) **et** Amandine (user_id `15260127`, conjointe — cas légitime "ménage", pas du multi-account abusif). Dossiers `data-aurelien/` et `data-amandine/` séparés, conteneurs Docker séparés mais image commune.

## Architecture Docker (sur le NAS)

`docker-compose.yml` à la racine du projet — trois services, tous en `network_mode: host` (WoL bloqué par bridge sinon) :

| Service               | Rôle                                           | Note                                              |
| --------------------- | ---------------------------------------------- | ------------------------------------------------- |
| `vinted-bot-aurelien` | bumper + optimizer compte Aurélien             | `env_file: .env.aurelien`                         |
| `vinted-bot-amandine` | idem compte Amandine                           | `depends_on: aurelien`, `env_file: .env.amandine` |
| `vinted-bot-webui`    | FastAPI + Jinja2 + HTMX + Pico.css sur `:8089` | monte les deux `data-*/` en lecture               |

Lancement : `sudo docker compose up -d --build --force-recreate`. **Pydantic Settings lit `env_file` à la création du conteneur**, donc tout changement dans `.env.*` nécessite `--force-recreate` (pas besoin de `--build` si seul l'env change).

## Tâches planifiées DSM (Task Scheduler Synology)

- **Bumper** : 7j/7, plage 12 h–23 h, jitter 0–45 min, max 6 articles/jour. Sélection pondérée par saison (`BUMP_PREFER_SEASON=auto`, fallback `été`/`hiver` selon mois). Pesée par mots-clés dans titre+description.
- **Optimizer `--generate` (mensuel)** : démarre LM Studio sur le PC via WoL + HA, lance le batch (`OPTIMIZER_BATCH_SIZE`), éteint le PC.
- **Optimizer `--apply` (quotidien 23 h)** : lit les fichiers `data-*/proposals/proposals-*.json`, applique uniquement les items avec `user_action ∈ {apply, edit}` et sans `applied_at`. Idempotent.
- Wrappers : `scripts/run-optimizer-all.sh` (mensuel, fait Aurélien `--no-shutdown` puis Amandine), `scripts/run-optimizer-apply.sh` (quotidien, les deux comptes).

## Pile technique

- Python 3.12, Pydantic Settings v2, Click (CLI), FastAPI 0.115+ (nouvelle API `TemplateResponse(request, "tpl.html", ctx)`), Jinja2, HTMX, Pico.css, Pillow.
- API Vinted v2 reverse-engineered : auth = cookies (`_vinted_fr_session`, `cf_clearance`, `v_uid`, `access_token_web`) + JWT Bearer + `X-CSRF-Token` (scrapé depuis la home HTML) + `X-Anon-Id`.
- Refresh OAuth : `POST /oauth/token` avec `grant_type=refresh_token`, `client_id="web"`.
- LLM : LM Studio sur Windows 11 (Ryzen 9800X3D, RX 9070 XT, 32 Go) via API OpenAI-compatible sur `:1234`. Format `response_format` = **`json_schema`** (pas `json_object`), avec `name`, `strict`, `schema`.
- JWT decode : `access_token_web` → claim `sub` = user_id (à privilégier sur le cookie `v_uid` qui peut être périmé après changement de compte).

## Power-management PC LLM

`src/vinted_bot/optimizer/wol.py` orchestre tout :

1. `ha_get_switch_state()` — note l'état initial de `switch.prise_bureau_switch` (Zigbee via Home Assistant `192.168.1.6:8123`).
2. `ha_power_on_pc()` si éteint.
3. WoL UDP broadcast (nécessite `network_mode: host`).
4. SSH au PC : exécute un script PowerShell volumineux encodé base64 UTF-16LE (`-EncodedCommand`) qui spawne `lms.exe` via **WMI `Invoke-CimMethod Win32_Process Create`** — sinon SSH ferme le Job Object et tue lms quand la session se déconnecte.
5. Poll TCP `Get-NetTCPConnection -LocalPort 1234 -State Listen` (pas `Invoke-WebRequest` vers localhost, faux négatifs de timing).
6. À la fin : `shutdown_pc()` SSH, attente `HA_POST_SHUTDOWN_WAIT_SEC=45 s`, **puis** `ha_power_off_pc()` **uniquement si l'état initial était `off`** (pas de coupure si quelqu'un utilise le PC).

Chemin lms : `$env:USERPROFILE\.lmstudio\bin\lms.exe` — **f-string raw `rf"""..."""` obligatoire** dans le code Python car `\b` se transformerait en `<BS>`. WMI utilise le PATH SYSTEM (pas user) donc chemin complet requis (sinon ReturnValue=9).

## Pièges connus (importants à se rappeler)

| Symptôme                           | Cause                                 | Fix                                                                                                                                                                      |
| ---------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `403` + URL `captcha-delivery.com` | DataDome a flag le cookie/IP          | Bail-out immédiat, attendre 4-12 h ou ré-exporter cookies. Détection dans `runner.py` : matcher aussi `"Aucun X-CSRF-Token"` (DataDome sert un captcha au lieu du HTML). |
| Burst PUT → DataDome instant       | Rate trop élevé                       | `random.uniform(5, 20)` entre chaque PUT dans `apply_proposals()`. Le 17/06 a tenu 54 PUTs en 11 min avant flag.                                                         |
| Bumper 0–45 min jitter             | Anti-pattern detection                | OK 7j/7 plage 12 h–23 h.                                                                                                                                                 |
| HEIC photos iPhone                 | Vinted refuse HEIC                    | Convertir en JPEG via Pillow. Vinted accepte aussi `image/png`.                                                                                                          |
| Status_id=1 sur livres             | Legacy invalid                        | Override en 2 dans `_build_create_payload`. Livres → `status_id` au top-level, vêtements → dans `item_attributes`.                                                       |
| Titre `H&amp;M`                    | API renvoie HTML-encoded              | `html.unescape()` sur title/description/brand.                                                                                                                           |
| `test-cookies.py` user_id faux     | Priorisait cookie `v_uid`             | Lire JWT `sub` en premier, fallback `v_uid`. Honorer `VINTED_COOKIES_PATH`.                                                                                              |
| 404 `GET /item_upload/items/<id>`  | Article supprimé côté Vinted          | Logguer + skip. À terme : marquer `inactive` en DB locale.                                                                                                               |
| LM Studio `response_format` erreur | Mauvais format                        | Utiliser `json_schema` avec `name` + `strict: true` + `schema`, **pas** `json_object`.                                                                                   |
| `NameError: time`                  | Import oublié                         | `import time` en haut de `runner.py` (déjà fait).                                                                                                                        |
| Container env pas pris en compte   | Pydantic lit `env_file` à la création | `--force-recreate` (sans `--build`) suffit pour des changements env-only.                                                                                                |
| WebUI `unhashable type: 'dict'`    | FastAPI 0.115 a changé l'API          | `templates.TemplateResponse(request, "tpl.html", ctx)` — request en 1er.                                                                                                 |

## WebUI (port 8089)

- **Dashboard** : 4 compteurs par compte — 🔵 pending / 🟠 validé (apply ou edit non encore poussé) / 🟢 done (`applied_at` set) / ⚪ skip.
- **List proposals** : agrège **tous** les `proposals-*.json` du compte, paginé 10/page avec nav ⏮ ‹ › ⏭.
- Actions : `apply` (valider tel quel), `skip`, `edit-form` → `save-edit` (modifier titre/description), `view`, `reset`.
- L'action **ne pousse pas tout de suite sur Vinted** — elle écrit `user_action` dans le JSON. La tâche cron 23 h fait le PUT.
- Routes : `src/vinted_bot/webui/server.py` — 8 endpoints.
- Templates : `webui/templates/base.html`, `dashboard.html`, `proposals.html`, `_card.html`, `_card_edit.html`.

## Variables d'env critiques (`.env.aurelien` / `.env.amandine`)

```
VINTED_USER_ID=20575548          # ou 15260127 pour Amandine
VINTED_COOKIES_PATH=/data/cookies/vinted-cookies.json
BUMP_MAX_PER_DAY=6
BUMP_HOUR_START=12
BUMP_HOUR_END=23
BUMP_JITTER_MAX_MIN=45
BUMP_PREFER_SEASON=auto          # auto = se base sur le mois (été M5–M9, hiver M10–M4)

OPTIMIZER_ENABLED=true
OPTIMIZER_BATCH_SIZE=20
OPTIMIZER_MIN_PRICE_EUR=5.0
OPTIMIZER_MIN_DAYS_BETWEEN_OPTIMIZATIONS=30

# PC distant
PC_HOST=192.168.1.X
PC_MAC=XX:XX:XX:XX:XX:XX
PC_SSH_USER=Aurel
PC_SSH_KEY_PATH=/root/.ssh/id_ed25519

# Home Assistant
HA_URL=http://192.168.1.6:8123
HA_TOKEN=<long_lived_access_token>
HA_PC_SWITCH_ENTITY=switch.prise_bureau_switch
HA_POST_SHUTDOWN_WAIT_SEC=45

# LM Studio
LMSTUDIO_URL=http://192.168.1.Y:1234/v1
LMSTUDIO_MODEL=mistralai/mistral-small-3.1-24b-instruct-2503
```

## Commandes utiles

```bash
# Logs live
sudo docker compose logs -f vinted-bot-aurelien
sudo docker compose logs -f vinted-bot-webui

# Forcer un run optimizer apply manuellement
sudo bash /volume1/Aurelien/Scripts/vinted-bot/scripts/run-optimizer-apply.sh

# Test rapide cookies (sans toucher au state)
docker compose exec vinted-bot-aurelien python -m vinted_bot.scripts.test_cookies

# Rebuild après changement de code
sudo docker compose up -d --build --force-recreate
```

## État actuel (2026-06-25)

- ✅ Bumper opérationnel 7j/7
- ✅ Optimizer pipeline complet (generate → WebUI → apply) testé sur 84 items le 17/06
- ✅ HA smart-plug avec préservation d'état (ne coupe pas si déjà allumé au départ)
- ✅ Rate-limit 5–20 s sur les PUT validé (54 PUTs Amandine sans drama)
- ⏳ 1 item Amandine + 1 erreur 404 Aurélien à reprocesser au prochain `--apply` (idempotent)
- ⏳ Pas encore de notif (telegram/mail) post-run — uniquement les logs

## Risques en cours

1. **DataDome peut flag l'IP du NAS** si plusieurs runs successifs flaggent — solution VPN ponctuel si ça récidive.
2. **Cookies expirent** : `access_token_web` durée ≈ 2 h, refresh via OAuth marche tant que `_vinted_fr_session` est valide. Si Vinted invalide la session, re-export manuel cookies via extension Chrome.
3. **PC Windows** : si quelqu'un éteint manuellement pendant un run optimizer, le shutdown_pc échoue mais ne casse rien — la prise reste dans son état initial.

## Liens / refs externes

- Code (NAS) : `/volume1/Aurelien/Scripts/vinted-bot/`
- WebUI : http://nas.local:8089/
- HA : http://192.168.1.6:8123/
- LM Studio CLI cheat : `lms server start --bind 0.0.0.0`, `lms load <model>`, `lms server status`
- Cookies à ré-exporter : extension **EditThisCookie** (Chrome) → "Export" sur `www.vinted.fr`, sauvegarder en `vinted-cookies.json` dans `data-<account>/cookies/`
