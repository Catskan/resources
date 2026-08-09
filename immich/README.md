# Service machine-learning Immich déporté sur le Mac

Sort l'inférence Immich du NAS Synology, dont le CPU et les I/O sont le facteur
limitant. Le service écoute sur le port **3003**, joint par le NAS via le tailnet
(`http://100.64.0.3:3003`).

## Configuration côté Immich

Dans **Administration → Paramètres → Machine Learning**, renseigner **deux** URL,
dans cet ordre :

```
1. http://100.64.0.3:3003                 ← ce Mac, essayé en premier
2. http://immich-machine-learning:3003    ← conteneur du NAS, en secours
```

Immich essaie les URL séquentiellement. La documentation recommande d'**ajouter**
l'URL distante plutôt que de remplacer la locale : si le Mac est éteint ou en veille,
reconnaissance faciale et détection de doublons continuent de fonctionner sur le NAS
au lieu d'échouer. Passer par l'interface et non par `IMMICH_MACHINE_LEARNING_URL` —
la variable d'environnement n'accepte qu'une seule URL.

## Les deux jobs launchd

| Job                       | Rôle                                                          |
| ------------------------- | ------------------------------------------------------------- |
| `com.user.immichml`       | le service : `RunAtLoad` + `KeepAlive`, relancé s'il s'arrête |
| `com.user.immichml.daily` | le rafraîchissement : redémarre le service à 3 h              |

**Pourquoi deux jobs.** Un même job launchd ne peut pas être à la fois service
permanent et tâche planifiée : `StartCalendarInterval` est ignoré tant que le job
tourne. Dans la version initiale, un seul job cumulait les deux rôles et le script
sortait sur un verrou s'il se trouvait déjà lancé — la mise à jour de 3 h ne
s'exécutait donc jamais.

`git pull` et `uv sync` sont faits par `start-immich-ml-agent.sh` **à chaque
démarrage**. Redémarrer le service suffit donc à le mettre à jour, et le job
quotidien se contente d'un `launchctl kickstart -k`.

## Installation

```bash
# 1. Retirer l'ancien job (il cumulait service et planification)
launchctl bootout gui/$(id -u)/com.user.immichml.daily 2>/dev/null

# 2. Installer les deux plists
cp ~/git/resources/immich/com.user.immichml.plist       ~/Library/LaunchAgents/
cp ~/git/resources/immich/com.user.immichml.daily.plist ~/Library/LaunchAgents/

# 3. Charger
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.immichml.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.immichml.daily.plist

# 4. Vérifier
launchctl list | grep immichml
curl -sS http://127.0.0.1:3003/ping   # doit répondre : pong
```

Les scripts doivent être exécutables (`chmod +x *.sh`) : launchd les invoque
directement, sans passer par un interpréteur.

## Exploitation

```bash
# Forcer une mise à jour immédiate (git pull + uv sync + redémarrage)
launchctl kickstart -k gui/$(id -u)/com.user.immichml

# Journaux
tail -f ~/Library/Logs/immichml.log
tail -f ~/Library/Logs/immichml.err
```

## Limite à connaître

Le service ne tourne que si le Mac est allumé et la session ouverte — un LaunchAgent
n'est pas un démon système. Mac éteint ou endormi, Immich bascule sur le conteneur ML
du NAS (seconde URL), **sans avertissement** : la charge d'inférence revient alors sur
la machine qu'on cherchait à soulager. Si tu retires la seconde URL, les jobs échouent
puis sont remis en file — rien n'est perdu, mais visages et recherche intelligente
restent en attente jusqu'au retour du Mac.
