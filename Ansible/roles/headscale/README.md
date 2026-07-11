# Headscale + Tailscale (accès Mac cross-site) — déploiement Ansible

Control plane **Headscale** auto-hébergé (LXC dédié sur le Wyse) + clients **Tailscale**,
pour donner au Mac une **IP tailnet `100.x` stable** injectable dans `hosts.json` → `run-on`
joint le Mac quelle que soit l'interface (dock `.8` / Wi-Fi `.116`) ou le site.

## Fichiers livrés

- `roles/proxmox_headscale_lxc/` — crée le CT 102 « headscale » via `pct` (clone de `proxmox_claude_lxc`).
- `roles/headscale/` — install headscale, config TLS wildcard, preauthkey, updater DynDNS IONOS.
- `roles/tailscale_client/` — rattache un hôte au tailnet (appliqué au CT claude-code).
- `main_headscale_playbook.yml` — orchestrateur (4 plays : LXC → headscale → tun → client).
- `inventory/host_vars/headscale/{connection,secrets}.yml`.

## 1. Patch inventaire — `inventory/hosts.yaml`

Ajouter le groupe sous `all.children` :

```yaml
headscale_hosts:
  hosts:
    headscale:
```

## 2. Patch `Makefile`

Ajouter aux `.PHONY` `headscale check-headscale`, puis les cibles :

```make
headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml $(ARGS)

check-headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml --check --diff $(ARGS)
```

## 3. Entrée KeePass (déjà en place)

Entrée **`Certificate *.eonelia.fr`** (groupe racine) avec **4 attachments** :

| Attachment                       | Rôle                              |
| -------------------------------- | --------------------------------- |
| `eonelia.fr_ssl_certificate.cer` | certificat feuille `*.eonelia.fr` |
| `intermediate1.cer`              | intermédiaire 1                   |
| `intermediate2.cer`              | intermédiaire 2                   |
| `*.eonelia.fr_private_key.key`   | clé privée                        |

Le rôle copie ces 4 fichiers sur le CT, normalise les `.cer` en PEM (`openssl`, gère PEM et DER)
et assemble la fullchain `feuille + int1 + int2`. Rien à concaténer à la main.
Références dans `inventory/host_vars/headscale/secrets.yml` (lookups `viczem.keepass … attachments`).

## 4. Étapes manuelles (hors Ansible)

1. **IONOS** : enregistrement **A statique** `mom.eonelia.fr → 88.172.204.162` (IP publique fixe de la Freebox de la mère). Pas de DynDNS (IP fixe).
2. **Freebox de la mère** (`88.172.204.162`) : redirection **`TCP 443 → <IP CT 102>:443`**.
3. **Mac** (à la maison) : installer Tailscale, puis
   `tailscale up --login-server=https://mom.eonelia.fr` (approuver via `headscale nodes list` / preauthkey).
   Récupérer son IP : `tailscale ip -4` → **la mettre dans `hosts.json` `.public` = `abusutil@100.x.y.z:2022`**.

## 5. Ordre de déploiement

```bash
make headscale ARGS='--limit proxmox_hosts'    # crée le CT 102 → note son IP DHCP
# reporter l'IP dans inventory/host_vars/headscale/connection.yml (ansible_host)
# créer la réservation DHCP du CT 102 sur la Freebox mère + le port-forward 443
make headscale ARGS='--limit headscale_hosts'  # install+config serveur (TLS, DynDNS, user, preauthkey)
make headscale                                 # run complet : + tun CT101 + client tailscale sur claude-code
```

Puis rattacher le Mac (étape 4.3) et mettre son `100.x` dans `hosts.json`.

## Prérequis / notes

- Collection **`viczem.keepass`** déjà utilisée par le repo (secrets).
- **DERP** : relais publics Tailscale par défaut (fallback chiffré). Pour du strict 100 % self-hosted, activer un DERP local (`derp.server.enabled: true` dans `config.yaml.j2`).
- Vérifier la dernière release Headscale (`headscale_version` dans `roles/headscale/defaults/main.yml`).
- Le CT claude-code (101) est **privilégié** → le play « tun » ajoute `/dev/net/tun` (kernel-mode) ; le conteneur Docker en `network_mode: host` hérite alors de `tailscale0` et des routes `100.x`.
