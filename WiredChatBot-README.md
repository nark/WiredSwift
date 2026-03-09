# WiredChatBot

Un chatbot daemon entièrement configurable pour le protocole **Wired 3**, écrit en Swift compatible Linux. Le bot s'appuie sur des modèles LLM (Ollama, OpenAI, Anthropic) pour répondre aux messages, réagir aux événements du serveur et exécuter des commandes personnalisées.

- Daemon POSIX complet (fork, PID file, SIGTERM/SIGHUP)
- Configuration JSON, rechargeable sans recompilation
- Trois backends LLM prêts à l'emploi (self-hosted ou cloud)
- Triggers regex avec cooldowns, templates et dispatch LLM
- Contexte de conversation par canal et par DM
- Architecture modulaire préparée pour un wrapper SwiftUI macOS

---

## Table des matières

1. [Prérequis](#prérequis)
2. [Compilation](#compilation)
3. [Utilisation CLI](#utilisation-cli)
4. [Référence de configuration](#référence-de-configuration)
   - [server](#server)
   - [identity](#identity)
   - [llm](#llm)
   - [behavior](#behavior)
   - [triggers](#triggers)
   - [daemon](#daemon)
5. [Providers LLM](#providers-llm)
   - [Ollama (self-hosted)](#ollama)
   - [OpenAI-compatible](#openai-compatible-lm-studio-groq-)
   - [Anthropic Claude](#anthropic-claude)
6. [Système de triggers](#système-de-triggers)
7. [Variables de template](#variables-de-template)
8. [Mode daemon Linux](#mode-daemon-linux)
9. [Systemd](#systemd)
10. [Wrapper SwiftUI macOS](#wrapper-swiftui-macos)
11. [Dépannage](#dépannage)

---

## Prérequis

**Linux**
- Swift 5.9+
- `zlib1g-dev`, `liblz4-dev`
- Pour le LLM self-hosted : [Ollama](https://ollama.com) ou tout autre serveur compatible OpenAI

**macOS**
- Xcode 15+ ou Swift 5.9+ en ligne de commande
- macOS 13+ recommandé pour `async/await` stable

---

## Compilation

```bash
# Cloner le dépôt
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift

# Compiler uniquement le bot
swift build --product WiredChatBot -c release

# Le binaire se trouve dans
.build/release/WiredChatBot
```

Copier le binaire et le fichier de spec du protocole :

```bash
sudo cp .build/release/WiredChatBot /usr/local/bin/wiredbot
sudo mkdir -p /usr/share/wiredbot
sudo cp Sources/WiredSwift/wired.xml /usr/share/wiredbot/
```

---

## Utilisation CLI

```
UTILISATION
  wiredbot <sous-commande>

SOUS-COMMANDES
  run               Démarrer le chatbot (défaut)
  generate-config   Écrire une configuration par défaut sur disque

OPTIONS GLOBALES
  --help            Afficher l'aide
```

### `wiredbot run`

```
OPTIONS
  -c, --config <path>   Fichier de configuration JSON         (défaut : wiredbot.json)
  -s, --spec <path>     Chemin vers wired.xml                 (défaut : auto-détecté)
  -f, --foreground      Forcer le mode premier plan            (défaut : false)
      --verbose         Activer le niveau DEBUG                (défaut : false)
```

Exemples :

```bash
# Démarrage simple (lit wiredbot.json dans le répertoire courant)
wiredbot run

# Configuration explicite, foreground pour Docker/debugging
wiredbot run --config /etc/wiredbot/bot.json --spec /usr/share/wiredbot/wired.xml --foreground

# Mode verbose pour diagnostiquer les problèmes de connexion
wiredbot run --foreground --verbose
```

### `wiredbot generate-config`

```
OPTIONS
  -o, --output <path>   Fichier de sortie   (défaut : wiredbot.json)
```

```bash
# Génère un wiredbot.json avec toutes les valeurs par défaut commentées
wiredbot generate-config --output /etc/wiredbot/wiredbot.json
```

---

## Référence de configuration

La configuration est un fichier **JSON** lu au démarrage. Exemple minimal :

```json
{
  "server":   { "url": "wired://monbot:motdepasse@wired.exemple.fr:4871" },
  "identity": { "nick": "MonBot" },
  "llm":      { "provider": "ollama", "model": "llama3" },
  "behavior": {},
  "triggers": [],
  "daemon":   { "foreground": true }
}
```

Toutes les clés non présentes prennent leur valeur par défaut.

---

### `server`

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `url` | string | `"wired://guest@localhost:4871"` | URL complète du serveur Wired. Format : `wired://login:motdepasse@hote:port` |
| `channels` | [uint] | `[1]` | IDs des canaux à rejoindre après connexion. `1` = chat public. |
| `reconnectDelay` | float | `30.0` | Secondes d'attente entre deux tentatives de reconnexion. |
| `maxReconnectAttempts` | int | `0` | Nombre max de tentatives. `0` = infini. |
| `specPath` | string? | `null` | Chemin vers `wired.xml`. `null` = auto-détection (voir ci-dessous). |

**Auto-détection de `wired.xml`** — Le bot cherche dans cet ordre :

1. Valeur de `specPath` dans la config
2. Flag `--spec` en ligne de commande
3. Même répertoire que le binaire
4. `./wired.xml`, `./Resources/wired.xml`
5. `/etc/wiredbot/wired.xml`
6. `/usr/share/wiredbot/wired.xml`
7. `/usr/local/share/wiredbot/wired.xml`

```json
"server": {
  "url": "wired://botaccount:s3cr3t@chat.monserveur.fr:4871",
  "channels": [1, 5, 12],
  "reconnectDelay": 15.0,
  "maxReconnectAttempts": 10,
  "specPath": "/opt/wired/wired.xml"
}
```

---

### `identity`

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `nick` | string | `"WiredBot"` | Pseudonyme du bot sur le serveur. |
| `status` | string | `"Powered by AI"` | Message de statut visible dans la liste d'utilisateurs. |
| `icon` | string? | `null` | Icône encodée en base64 (même format que Wired). `null` = icône par défaut. |
| `idleTimeout` | float | `0` | Secondes avant de passer en mode absent. `0` = jamais. |

```json
"identity": {
  "nick": "HAL9000",
  "status": "I'm sorry, I can't do that.",
  "icon": null,
  "idleTimeout": 0
}
```

Pour encoder une icône en base64 :

```bash
base64 -w 0 mon-icone.png
```

---

### `llm`

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `provider` | string | `"ollama"` | Backend LLM : `"ollama"`, `"openai"`, `"anthropic"` |
| `endpoint` | string | `"http://localhost:11434"` | URL de base de l'API (sans `/v1` ni `/api`). |
| `apiKey` | string? | `null` | Clé API. Obligatoire pour `openai` et `anthropic`. |
| `model` | string | `"llama3"` | Nom du modèle. Exemples : `"llama3"`, `"gpt-4o"`, `"claude-sonnet-4-6"` |
| `systemPrompt` | string | *(voir défaut)* | Prompt système injecté en tête de chaque conversation. Supporte les variables `{nick}`, `{server}`. |
| `temperature` | float | `0.7` | Créativité des réponses. `0.0` = déterministe, `1.0` = très créatif. |
| `maxTokens` | int | `512` | Nombre maximum de tokens dans une réponse LLM. |
| `contextMessages` | int | `10` | Nombre de tours de conversation mémorisés par canal/DM. |
| `timeoutSeconds` | float | `30.0` | Délai d'expiration des requêtes HTTP vers le LLM. |

```json
"llm": {
  "provider": "ollama",
  "endpoint": "http://localhost:11434",
  "apiKey": null,
  "model": "mistral",
  "systemPrompt": "Tu es un assistant serviable sur un serveur Wired. Sois concis, limite tes réponses à 2-3 phrases maximum. Pas de markdown — texte brut uniquement.",
  "temperature": 0.5,
  "maxTokens": 256,
  "contextMessages": 8,
  "timeoutSeconds": 20.0
}
```

---

### `behavior`

Contrôle quand et comment le bot réagit aux événements.

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `respondToMentions` | bool | `true` | Répondre quand le nick du bot (ou un `mentionKeyword`) est détecté dans un message. |
| `respondToAll` | bool | `false` | Répondre à **tous** les messages publics. À utiliser avec prudence et `rateLimitSeconds` élevé. |
| `respondToPrivateMessages` | bool | `true` | Répondre aux messages privés (DM). |
| `greetOnJoin` | bool | `true` | Envoyer un message de bienvenue quand un utilisateur rejoint un canal. |
| `greetMessage` | string | `"Welcome, {nick}!"` | Template du message de bienvenue. Supporte `{nick}`, `{chatID}`. |
| `farewellOnLeave` | bool | `false` | Envoyer un message d'au-revoir quand un utilisateur quitte. |
| `farewellMessage` | string | `"Goodbye, {nick}!"` | Template du message d'au-revoir. |
| `announceNewThreads` | bool | `true` | Annoncer les nouveaux posts dans les boards. |
| `announceNewThreadMessage` | string | `"New board post: \"{subject}\" by {nick}"` | Template de l'annonce. Supporte `{nick}`, `{subject}`, `{board}`. |
| `announceFileUploads` | bool | `false` | Annoncer les fichiers déposés sur le serveur. |
| `announceFileMessage` | string | `"{nick} uploaded: {filename}"` | Template de l'annonce. Supporte `{nick}`, `{filename}`, `{path}`. |
| `rateLimitSeconds` | float | `2.0` | Délai minimum (secondes) entre deux réponses du bot. Évite le spam. |
| `maxResponseLength` | int | `500` | Longueur maximale d'une réponse (en caractères). Les réponses plus longues sont tronquées avec `…`. |
| `ignoreOwnMessages` | bool | `true` | Ignorer les messages envoyés par le bot lui-même (évite les boucles). |
| `ignoredNicks` | [string] | `[]` | Liste de pseudonymes qui seront toujours ignorés. |
| `mentionKeywords` | [string] | `[]` | Mots-clés supplémentaires comptant comme une mention du bot (en plus du nick). |

```json
"behavior": {
  "respondToMentions": true,
  "respondToAll": false,
  "respondToPrivateMessages": true,
  "greetOnJoin": true,
  "greetMessage": "Salut {nick}, bienvenue sur le serveur !",
  "farewellOnLeave": true,
  "farewellMessage": "À bientôt {nick} !",
  "announceNewThreads": true,
  "announceNewThreadMessage": "Nouveau post dans les boards : \"{subject}\" par {nick}",
  "announceFileUploads": false,
  "announceFileMessage": "{nick} a déposé : {filename}",
  "rateLimitSeconds": 3.0,
  "maxResponseLength": 400,
  "ignoreOwnMessages": true,
  "ignoredNicks": ["Spambot", "OldBot"],
  "mentionKeywords": ["!bot", "@bot", "hey bot"]
}
```

---

### `triggers`

Tableau de déclencheurs personnalisés. Chaque trigger est un objet JSON.

| Clé | Type | Obligatoire | Description |
|-----|------|-------------|-------------|
| `name` | string | oui | Identifiant unique (utilisé pour les logs et les cooldowns). |
| `pattern` | string | oui | Expression régulière (POSIX étendu) testée contre le texte du message. |
| `eventTypes` | [string] | non | Types d'événements activants : `"chat"`, `"private"`, `"all"`. Défaut : `["chat", "private"]`. |
| `response` | string? | non | Réponse statique. Prioritaire sur `useLLM`. Supporte les templates `{variable}`. |
| `useLLM` | bool | non | Si `true` et `response` est absent, envoie l'entrée au LLM. Défaut : `false`. |
| `llmPromptPrefix` | string? | non | Texte préfixé à l'entrée utilisateur avant envoi au LLM. |
| `caseSensitive` | bool | non | La regex est-elle sensible à la casse ? Défaut : `false`. |
| `cooldownSeconds` | float | non | Délai entre deux déclenchements du même trigger **par utilisateur**. `0` = pas de cooldown. |

**Ordre de priorité :** Les triggers sont testés dans l'ordre du tableau. Le **premier match** gagne. Si aucun trigger ne correspond, le bot vérifie la mention avant d'appeler le LLM.

```json
"triggers": [
  {
    "name": "ping",
    "pattern": "^!ping$",
    "eventTypes": ["chat", "private"],
    "response": "Pong !",
    "caseSensitive": false,
    "cooldownSeconds": 0
  },
  {
    "name": "meteo",
    "pattern": "^!météo (.+)",
    "eventTypes": ["chat"],
    "useLLM": true,
    "llmPromptPrefix": "Donne la météo actuelle pour cette ville (réponse en 1-2 phrases) : ",
    "cooldownSeconds": 10
  },
  {
    "name": "blague",
    "pattern": "^!blague",
    "eventTypes": ["chat", "private"],
    "useLLM": true,
    "llmPromptPrefix": "Raconte une blague courte et drôle en français : ",
    "cooldownSeconds": 15
  },
  {
    "name": "aide",
    "pattern": "^!(help|aide|\\?)",
    "eventTypes": ["chat", "private"],
    "response": "Commandes : !ping, !aide, !ask <question>, !blague | Mentionner le bot pour parler.",
    "cooldownSeconds": 5
  },
  {
    "name": "ask",
    "pattern": "^!ask (.+)",
    "eventTypes": ["chat", "private"],
    "useLLM": true,
    "cooldownSeconds": 2
  }
]
```

---

### `daemon`

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `foreground` | bool | `false` | Ne pas forker en arrière-plan. Utile pour Docker, systemd avec `Type=simple`, ou le debugging. |
| `pidFile` | string | `"/tmp/wiredbot.pid"` | Chemin du fichier PID écrit au démarrage et supprimé à l'arrêt. |
| `logFile` | string? | `null` | Chemin du fichier de log. `null` = sortie sur stdout uniquement. |
| `logLevel` | string | `"INFO"` | Niveau de log : `"DEBUG"`, `"INFO"`, `"WARNING"`, `"ERROR"`. |

```json
"daemon": {
  "foreground": false,
  "pidFile": "/var/run/wiredbot/wiredbot.pid",
  "logFile": "/var/log/wiredbot/wiredbot.log",
  "logLevel": "INFO"
}
```

> **Note :** Le flag `--verbose` en ligne de commande force le niveau `DEBUG` indépendamment de `logLevel`.

---

## Providers LLM

### Ollama

Idéal pour un déploiement entièrement local. Aucune clé API requise.

```bash
# Installer Ollama et télécharger un modèle
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3
ollama pull mistral
ollama pull gemma3
```

```json
"llm": {
  "provider": "ollama",
  "endpoint": "http://localhost:11434",
  "model": "llama3"
}
```

Ollama sur un autre hôte (ex. serveur dédié GPU) :

```json
"llm": {
  "provider": "ollama",
  "endpoint": "http://192.168.1.50:11434",
  "model": "llama3:70b"
}
```

---

### OpenAI-compatible (LM Studio, Groq…)

Ce provider fonctionne avec **tout serveur exposant l'API `/v1/chat/completions`** : OpenAI officiel, [LM Studio](https://lmstudio.ai), [Groq](https://groq.com), [Mistral](https://mistral.ai), [Together AI](https://together.ai), etc.

**OpenAI**
```json
"llm": {
  "provider": "openai",
  "endpoint": "https://api.openai.com",
  "apiKey": "sk-...",
  "model": "gpt-4o"
}
```

**LM Studio** (local, pas de clé API)
```json
"llm": {
  "provider": "openai",
  "endpoint": "http://localhost:1234",
  "model": "local-model"
}
```

**Groq** (ultra-rapide, gratuit avec limites)
```json
"llm": {
  "provider": "openai",
  "endpoint": "https://api.groq.com/openai",
  "apiKey": "gsk_...",
  "model": "llama3-70b-8192"
}
```

**Mistral**
```json
"llm": {
  "provider": "openai",
  "endpoint": "https://api.mistral.ai",
  "apiKey": "...",
  "model": "mistral-large-latest"
}
```

---

### Anthropic Claude

```json
"llm": {
  "provider": "anthropic",
  "apiKey": "sk-ant-...",
  "model": "claude-sonnet-4-6",
  "maxTokens": 1024
}
```

> Le champ `endpoint` est ignoré pour Anthropic (l'URL est fixe : `https://api.anthropic.com/v1/messages`).

Modèles disponibles au moment de l'écriture :
- `claude-opus-4-6` — Le plus puissant
- `claude-sonnet-4-6` — Équilibre vitesse/qualité (recommandé)
- `claude-haiku-4-5-20251001` — Le plus rapide et économique

---

## Système de triggers

### Ordre d'exécution

Pour chaque message reçu :

```
1. Le message est ignoré si l'expéditeur est dans ignoredNicks
   ou si ignoreOwnMessages = true et c'est le bot lui-même
   ↓
2. Les triggers sont testés dans l'ordre du tableau JSON
   → Premier match : réponse statique OU dispatch LLM avec préfixe
   → Fin du traitement
   ↓
3. Si respondToAll = true OU (respondToMentions = true ET mention détectée)
   → Dispatch LLM avec le message complet
   ↓
4. Sinon : silence
```

### Expressions régulières

Les patterns utilisent la syntaxe **POSIX étendue** (NSRegularExpression).
Par défaut les patterns sont **insensibles à la casse** (`caseSensitive: false`).

Ancres utiles :
- `^` début du message, `$` fin
- `(.+)` capture un ou plusieurs caractères
- `\s` espace, `\w` alphanumérique
- `(a|b)` alternative

Exemples :

```json
{ "pattern": "^!ping$" }                       // exactement "!ping"
{ "pattern": "^!ask (.+)" }                    // commence par "!ask "
{ "pattern": "bonjour|salut|hello" }           // n'importe où dans le message
{ "pattern": "^!(help|aide|\\?)" }             // !help ou !aide ou !?
{ "pattern": "\\bwired\\b" }                   // mot "wired" isolé
```

### Cooldowns

Le cooldown s'applique **par utilisateur** (pas globalement). Si `cooldownSeconds: 10` est défini sur un trigger `!blague`, chaque utilisateur peut déclencher ce trigger au plus une fois toutes les 10 secondes, mais plusieurs utilisateurs différents peuvent le faire simultanément.

### Dispatch LLM avec préfixe

`llmPromptPrefix` est concaténé au message de l'utilisateur **avant** envoi au LLM, mais le message original reste dans le contexte de conversation.

```json
{
  "name": "resume",
  "pattern": "^!résume (.+)",
  "useLLM": true,
  "llmPromptPrefix": "Résume ce texte en une phrase : "
}
```

Si l'utilisateur envoie `!résume Lorem ipsum dolor sit amet...`, le LLM reçoit :
`"Résume ce texte en une phrase : Lorem ipsum dolor sit amet..."`

---

## Variables de template

Les templates `{variable}` sont disponibles dans `response`, `greetMessage`, `farewellMessage`, `announceNewThreadMessage` et `announceFileMessage`.

| Variable | Disponible dans | Description |
|----------|----------------|-------------|
| `{nick}` | tous | Pseudonyme de l'utilisateur concerné |
| `{input}` | `response` | Texte original du message ayant déclenché le trigger |
| `{chatID}` | `response`, `greetMessage`, `farewellMessage` | ID numérique du canal |
| `{subject}` | `announceNewThreadMessage` | Sujet du nouveau thread |
| `{board}` | `announceNewThreadMessage` | Nom du board |
| `{filename}` | `announceFileMessage` | Nom du fichier (sans chemin) |
| `{path}` | `announceFileMessage` | Chemin complet du fichier |

---

## Mode daemon Linux

En mode daemon (défaut quand `foreground: false`), le processus :

1. Effectue un double `fork()` pour se détacher du terminal
2. Crée une nouvelle session (`setsid`)
3. Redirige stdin/stdout/stderr vers `/dev/null`
4. Écrit son PID dans `pidFile`

**Signaux supportés :**

| Signal | Action |
|--------|--------|
| `SIGTERM` | Arrêt propre : ferme la connexion, supprime le PID file |
| `SIGINT` | Idem (Ctrl+C en mode foreground) |
| `SIGHUP` | Notification de rechargement (log uniquement — un redémarrage est nécessaire pour appliquer les changements de config) |

```bash
# Arrêter proprement
kill $(cat /tmp/wiredbot.pid)

# Signaler un rechargement
kill -HUP $(cat /tmp/wiredbot.pid)
```

---

## Systemd

Un fichier unit d'exemple est fourni dans `Examples/wiredbot.service`.

Installation :

```bash
# Créer l'utilisateur système dédié
sudo useradd --system --no-create-home --shell /usr/sbin/nologin wiredbot

# Créer les répertoires nécessaires
sudo mkdir -p /etc/wiredbot /var/log/wiredbot /var/run/wiredbot
sudo chown wiredbot:wiredbot /var/log/wiredbot /var/run/wiredbot

# Copier les fichiers
sudo cp .build/release/WiredChatBot /usr/local/bin/wiredbot
sudo cp Sources/WiredSwift/wired.xml /usr/share/wiredbot/
sudo cp Examples/wiredbot-example.json /etc/wiredbot/wiredbot.json
sudo cp Examples/wiredbot.service /etc/systemd/system/

# Adapter la configuration
sudo nano /etc/wiredbot/wiredbot.json

# Activer et démarrer
sudo systemctl daemon-reload
sudo systemctl enable --now wiredbot

# Vérifier l'état
sudo systemctl status wiredbot
sudo journalctl -u wiredbot -f
```

Pour systemd, utiliser `Type=forking` avec le mode daemon activé, ou `Type=simple` avec `foreground: true` dans la config (et supprimer `PIDFile` de l'unit).

---

## Wrapper SwiftUI macOS

`BotController` est conçu pour être facilement observable depuis SwiftUI :

```swift
import SwiftUI
import WiredSwift

// Wrapping observable
class BotViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastMessage: String = ""

    let controller: BotController

    init(config: BotConfig) {
        self.controller = BotController(config: config)
    }
}

struct ContentView: View {
    @StateObject private var vm = BotViewModel(config: loadConfig())

    var body: some View {
        VStack {
            Text(vm.isConnected ? "Connecté" : "Déconnecté")
            Button("Démarrer") {
                Task.detached {
                    try? vm.controller.start(specPath: specPath)
                }
            }
        }
    }
}
```

Toutes les mutations d'état dans `BotController` se font sur le `main queue` (les callbacks `ConnectionDelegate` y sont dispatché par WiredSwift), ce qui les rend compatibles avec `@Published` sans `DispatchQueue.main.async` supplémentaire.

---

## Dépannage

**Le bot ne trouve pas `wired.xml`**
```bash
wiredbot run --spec /chemin/vers/wired.xml --foreground --verbose
```
Vérifier aussi `server.specPath` dans la config.

**Connexion refusée**
- Vérifier l'URL (`wired://login:password@host:port`)
- Le compte doit exister sur le serveur et avoir les droits de connexion
- Le port 4871 doit être ouvert (firewall, NAT)

**Le LLM ne répond pas**
- Tester l'endpoint manuellement :
  ```bash
  curl http://localhost:11434/api/chat -d '{"model":"llama3","messages":[{"role":"user","content":"test"}],"stream":false}'
  ```
- Augmenter `timeoutSeconds` si le modèle est lent
- Vérifier `apiKey` pour les providers cloud

**Le bot répond en boucle**
- S'assurer que `ignoreOwnMessages: true` (défaut)
- Ajouter le nick du bot dans `ignoredNicks` sur les autres instances

**Logs**
```bash
# Voir les logs en temps réel (mode daemon)
tail -f /tmp/wiredbot.log

# Niveau DEBUG pour tout voir
wiredbot run --foreground --verbose
```
