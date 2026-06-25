# vinted-bot

Bot Python pour Vinted : **republication automatique** d'annonces (anti-bump-removed) + **optimisation LLM** des titres/descriptions + **WebUI de validation**. Conçu pour tourner en autonomie sur un NAS Synology, avec un PC distant servant de GPU LLM à la demande.

> **Cas d'usage légitime "ménage"** : deux comptes (Aurélien + sa conjointe Amandine), pas du multi-account abusif. Toute la chaîne est conçue pour rester sous les radars anti-bot tout en respectant les CGU.

## TL;DR

| Quoi                          | Comment                                                             | Où                                                     |
| ----------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------ |
| Remonter les annonces         | `delete + recreate` avec photos transformées (anti-perceptual-hash) | Cron 7j/7, plage 12 h–23 h, jitter ≤45 min, max 6/jour |
| Optimiser titres/descriptions | LLM Mistral 24B local (LM Studio sur PC Windows distant)            | Cron mensuel `--generate`                              |
| Valider les propositions LLM  | WebUI FastAPI sur `:8089`                                           | `apply` / `edit` / `skip`                              |
| Pousser les optims validées   | PUT `/api/v2/item_upload/items/<id>` avec rate-limit 5–20 s         | Cron quotidien `--apply` à 23 h                        |

## Architecture

```
┌──────────────────────┐         ┌────────────────────────┐
│  NAS Synology DS716+ │  WoL    │  PC Windows (Ryzen 9800X3D, │
│  ┌────────────────┐  │ ───────▶│   RX 9070 XT, 32 Go)        │
│  │ vinted-bot-    │  │         │  ┌──────────────────────┐   │
│  │   aurelien     │  │  SSH    │  │ LM Studio :1234      │   │
│  │ vinted-bot-    │  │ ───────▶│  │  └── Mistral Small   │   │
│  │   amandine     │  │         │  │      24B (Vulkan)    │   │
│  │ vinted-bot-    │  │         │  └──────────────────────┘   │
│  │   webui :8089  │  │         └────────────────────────┘    │
│  └────────────────┘  │              ▲ POST switch on/off
│   3× containers,     │              │
│   network_mode: host │     ┌────────┴────────┐
└──────────┬───────────┘     │ Home Assistant  │
           │                 │  prise Zigbee   │
           │ HTTPS           │  192.168.1.6    │
           ▼                 └─────────────────┘
   api.vinted.fr
```

## Stack

- **Runtime** : Python 3.12, Docker Compose, NAS Synology DSM 7
- **Web** : FastAPI 0.115, Jinja2, HTMX, Pico.css
- **API Vinted v2** : reverse-engineered (auth cookies + JWT Bearer + `X-CSRF-Token` scrapé + `X-Anon-Id`)
- **LLM** : LM Studio CLI (`lms`) + Mistral Small 24B, format `response_format = json_schema`
- **Photos** : Pillow (crop ≤8 px, rotation ≤0.6°, JPEG re-encode 84-92, noise σ=3)
- **Power** : Wake-on-LAN UDP + Home Assistant (prise Zigbee) + SSH WMI spawn pour détacher lms du Job Object

## Setup rapide

### 1. Cloner et configurer

```bash
git clone <ce-repo>
cd Projects/vinted-bot
cp .env.example .env.aurelien
# édite .env.aurelien avec tes vraies valeurs
cp .env.example .env.amandine    # optionnel pour 2ᵉ compte
```

### 2. Récupérer les cookies Vinted

1. Connecte-toi sur https://www.vinted.fr/ depuis Chrome
2. Installe l'extension **EditThisCookie**
3. Sur la page Vinted, clique sur l'icône extension → **Export** (JSON)
4. Sauvegarde dans `data-aurelien/cookies/vinted-cookies.json`
5. Vérifie avec : `python scripts/test-cookies.py` (doit afficher "✅ API OK")

Renouveler tous les ~30 jours (ou quand le bot signale `Aucun X-CSRF-Token`).

### 3. (Optionnel) PC Windows pour le LLM

- Activer SSH sur Windows (OpenSSH Server feature)
- Installer LM Studio + télécharger le modèle Mistral Small 24B
- Tester localement : `lms server start --bind 0.0.0.0` puis `lms load <model>`
- Générer une clé SSH côté NAS et l'ajouter à `~/.ssh/authorized_keys` du compte Windows
- Renseigner `PC_MAC`, `PC_IP`, `PC_SSH_USER`, `PC_SSH_KEY_PATH` dans `.env.*`
- (Optionnel) Configurer Home Assistant + token long-lived pour piloter la prise Zigbee

### 4. Lancer

```bash
sudo docker compose up -d --build
```

- WebUI accessible sur http://<nas-ip>:8089/
- Logs : `sudo docker compose logs -f vinted-bot-aurelien`

### 5. Planifier (Task Scheduler DSM)

| Tâche              | Cmd                                                                  | Fréquence                    |
| ------------------ | -------------------------------------------------------------------- | ---------------------------- |
| Bumper             | `docker exec vinted-bot-aurelien python -m vinted_bot.bumper.runner` | toutes les heures, 12 h–23 h |
| Optimizer generate | `bash scripts/run-optimizer-all.sh`                                  | 1× / mois                    |
| Optimizer apply    | `bash scripts/run-optimizer-apply.sh`                                | quotidien à 23 h             |

## Layout du repo

```
vinted-bot/
├── CLAUDE.md                    # mémoire projet pour reprise Claude
├── README.md                    # ce fichier
├── .env.example                 # template config (à copier en .env.aurelien etc.)
├── .gitignore                   # exclut secrets + runtime data
├── Dockerfile
├── docker-compose.yml           # 3 services, network_mode: host
├── pyproject.toml
├── src/vinted_bot/
│   ├── config.py                # Pydantic Settings (lit env_file à la création conteneur)
│   ├── db.py                    # SQLite (item state, dedup, history)
│   ├── log.py                   # loguru avec rotation gzip
│   ├── bumper/                  # republier annonces
│   │   ├── runner.py
│   │   ├── scheduler.py         # HOUR_WEIGHTS = pics 12-13h + 19-22h
│   │   ├── seasonal.py          # mots-clés saisonniers (été/hiver)
│   │   └── selector.py          # poids = freshness × seasonality × random
│   ├── photos/transformer.py    # crop/rotate/jpeg-reencode anti-perceptual-hash
│   ├── vinted/                  # client API v2
│   │   ├── client.py            # OAuth refresh, X-CSRF-Token scrape, X-Anon-Id
│   │   ├── endpoints.py
│   │   ├── errors.py
│   │   └── models.py
│   ├── optimizer/               # LLM Mistral
│   │   ├── runner.py            # --generate / --apply / --all
│   │   ├── llm.py               # client OpenAI-compatible vers LM Studio
│   │   ├── prompts.py           # system+user prompts SEO Vinted
│   │   ├── proposals.py         # I/O JSON multi-fichiers (proposals-YYYYMMDD.json)
│   │   └── wol.py               # HA plug + WoL + SSH WMI spawn + lms load
│   ├── webui/                   # FastAPI app
│   │   ├── server.py            # 8 routes (dashboard + 7 actions)
│   │   └── templates/           # base.html + dashboard + proposals + _card[+edit]
│   ├── crosspost/               # leboncoin (POC, non actif)
│   └── notif/                   # email SMTP (non actif)
├── scripts/
│   ├── deploy-nas.sh            # sync Mac → NAS via SMB
│   ├── run-optimizer-all.sh     # wrapper mensuel
│   ├── run-optimizer-apply.sh   # wrapper quotidien
│   ├── test-cookies.py          # validation cookies + JWT decode
│   ├── test-client.py           # smoke test Vinted API
│   ├── test-infra.sh            # validation env complète
│   ├── live-bump-prepare.py     # dry-run bumper
│   ├── live-bump-commit.py      # exécution un bump
│   ├── explore-api.py           # capture de routes API pour reverse-eng
│   ├── probe-item-detail.py     # debug payload item
│   ├── migrate-to-multi-compte.sh
│   └── test-{transformer,scheduler,optimizer-llm,bumper-logic}.py
├── userscript/leboncoin-prefill.user.js   # Tampermonkey pour Phase 2 (crosspost)
├── data-aurelien/               # runtime data compte Aurélien
│   ├── cookies/.gitkeep         # vinted-cookies.json (gitignore)
│   ├── db/.gitkeep              # vinted-bot.sqlite (gitignore)
│   ├── logs/.gitkeep
│   ├── proposals/.gitkeep
│   └── crosspost/.gitkeep
└── data-amandine/               # idem, compte Amandine
```

## Workflow Optimizer (le plus complexe)

```
┌──────────┐   1. WoL + HA on    ┌────────────┐
│   NAS    │ ─────────────────▶  │ PC Windows │
│ generate │   2. SSH lms start  │ LM Studio  │
│ --batch  │   3. POST /v1/chat  │  :1234     │
│          │ ◀───────────────── │  Mistral24B│
│ writes   │   4. proposals/     └────────────┘
│ JSON     │   proposals-YYYYMMDD.json
└──────────┘
     │
     │  5. user opens WebUI :8089
     ▼
┌──────────────────────────────┐
│  WebUI (FastAPI)             │
│  ┌────────────────────────┐  │
│  │ apply / edit / skip    │  │  6. user_action écrit dans le JSON
│  └────────────────────────┘  │     (PAS de PUT immédiat sur Vinted)
└──────────────────────────────┘
     │
     │  7. cron quotidien 23h
     ▼
┌──────────────────────────────┐
│ apply_proposals()            │
│   foreach JSON file:         │
│     foreach item:            │
│       if user_action in      │
│         {apply, edit}        │
│         and not applied_at:  │
│           PUT /item_upload/  │
│           sleep(5-20s)       │   8. rate-limit anti-DataDome
│           mark applied_at    │
└──────────────────────────────┘
```

## Pièges connus (lire avant de débugger)

| Symptôme                           | Cause                                         | Fix                                                                                                                                               |
| ---------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `403` URL `captcha-delivery.com`   | DataDome a flag le cookie/IP                  | Bail-out immédiat, attendre 4-12 h ou ré-exporter cookies. Détection : matcher `"Aucun X-CSRF-Token"` (DataDome sert un captcha au lieu du HTML). |
| Burst PUT → DataDome               | Rate trop élevé                               | `random.uniform(5, 20)` entre chaque PUT. Tient 50+ PUTs/run.                                                                                     |
| HEIC photos iPhone                 | Vinted refuse                                 | Convertir JPEG via Pillow (PNG aussi accepté).                                                                                                    |
| Titre `H&amp;M`                    | API renvoie HTML-encoded                      | `html.unescape()` sur title/description/brand.                                                                                                    |
| `test-cookies.py` user_id faux     | Cookie `v_uid` périmé après changement compte | Lire JWT `sub` en premier, fallback `v_uid`.                                                                                                      |
| Container env pas pris en compte   | Pydantic lit `env_file` à la création         | `docker compose up -d --force-recreate` (pas besoin de `--build`).                                                                                |
| `lms server` meurt après SSH close | Job Object kill children                      | Spawn via WMI `Invoke-CimMethod Win32_Process Create`.                                                                                            |
| LM Studio `response_format` erreur | Mauvais format                                | Utiliser `json_schema` avec `name` + `strict: true` + `schema`.                                                                                   |
| `lms.exe` introuvable via WMI      | WMI utilise PATH SYSTEM                       | Chemin complet `$env:USERPROFILE\.lmstudio\bin\lms.exe` + raw f-string `rf"""..."""` (`\b` se transformerait en `<BS>`).                          |
| WebUI `unhashable type: 'dict'`    | FastAPI 0.115 changement API                  | `templates.TemplateResponse(request, "tpl.html", ctx)` — request en 1er.                                                                          |
| WoL bloqué depuis Docker           | UDP broadcast bloqué par bridge               | `network_mode: host` sur tous les services.                                                                                                       |
| Status_id=1 sur livres             | Legacy invalid                                | Override en 2. Livres → top-level, vêtements → dans `item_attributes`.                                                                            |

## Sécurité / Compliance

- **Pas de scraping non autorisé** : on utilise notre propre dressing via cookies de session standards.
- **Pas de mass-account** : 2 comptes uniquement (cas légitime ménage).
- **Pas d'évasion captcha** : si DataDome captcha, on bail-out, on ne contourne pas.
- **Rate-limit volontaire** : jitter aléatoire 5–20 s entre PUTs, max 6 bumps/jour/compte.
- **Cookies en local** : jamais transmis ailleurs que vers `api.vinted.fr`.
- **Code source non publié** : ce repo Catskan est **privé**, et le code n'est jamais déployé en clair.

## Licence / Auteur

Personal project — Aurélien Busutil. Pas de redistribution, pas de SLA.

## Voir aussi

- [`CLAUDE.md`](CLAUDE.md) — mémoire détaillée pour reprise en session Claude Code
- Repo principal : [`Catskan/resources`](https://github.com/Catskan/resources)
