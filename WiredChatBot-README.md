# WiredChatBot

A fully configurable chatbot daemon for the **Wired 3** protocol, written in Linux-compatible Swift. The bot leverages LLM backends (Ollama, OpenAI, Anthropic) to respond to messages, react to server events, and execute custom commands.

- Full POSIX daemon (fork, PID file, SIGTERM/SIGHUP)
- JSON configuration, reloadable without recompilation
- Three ready-to-use LLM backends (self-hosted or cloud)
- Regex triggers with cooldowns, templates and LLM dispatch
- Per-channel and per-DM conversation context
- Modular architecture prepared for a macOS SwiftUI wrapper

---

## Table of Contents

1. [Requirements](#requirements)
2. [Building](#building)
3. [CLI Usage](#cli-usage)
4. [Configuration Reference](#configuration-reference)
   - [server](#server)
   - [identity](#identity)
   - [llm](#llm)
   - [behavior](#behavior)
   - [triggers](#triggers)
   - [daemon](#daemon)
5. [LLM Providers](#llm-providers)
   - [Ollama (self-hosted)](#ollama)
   - [OpenAI-compatible](#openai-compatible-lm-studio-groq-)
   - [Anthropic Claude](#anthropic-claude)
6. [Trigger System](#trigger-system)
7. [Template Variables](#template-variables)
8. [Linux Daemon Mode](#linux-daemon-mode)
9. [Systemd](#systemd)
10. [macOS SwiftUI Wrapper](#macos-swiftui-wrapper)
11. [Troubleshooting](#troubleshooting)

---

## Requirements

**Linux**
- Swift 5.9+
- `zlib1g-dev`, `liblz4-dev`
- For self-hosted LLM: [Ollama](https://ollama.com) or any OpenAI-compatible server

**macOS**
- Xcode 15+ or Swift 5.9+ command line tools
- macOS 13+ recommended for stable `async/await`

---

## Building

```bash
# Clone the repository
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift

# Build the bot only
swift build --product WiredChatBot -c release

# Binary is located at
.build/release/WiredChatBot
```

Copy the binary and the protocol spec file:

```bash
sudo cp .build/release/WiredChatBot /usr/local/bin/wiredbot
sudo mkdir -p /usr/share/wiredbot
sudo cp Sources/WiredSwift/Resources/wired.xml /usr/share/wiredbot/
```

---

## CLI Usage

```
USAGE
  wiredbot <subcommand>

SUBCOMMANDS
  run               Start the chatbot (default)
  generate-config   Write a default configuration to disk

GLOBAL OPTIONS
  --help            Show help
```

### `wiredbot run`

```
OPTIONS
  -c, --config <path>   JSON configuration file         (default: wiredbot.json)
  -s, --spec <path>     Path to wired.xml               (default: auto-detected)
  -f, --foreground      Force foreground mode            (default: false)
      --verbose         Enable DEBUG level               (default: false)
```

Examples:

```bash
# Simple start (reads wiredbot.json from current directory)
wiredbot run

# Explicit config, foreground for Docker/debugging
wiredbot run --config /etc/wiredbot/bot.json --spec /usr/share/wiredbot/wired.xml --foreground

# Verbose mode to diagnose connection issues
wiredbot run --foreground --verbose
```

### `wiredbot generate-config`

```
OPTIONS
  -o, --output <path>   Output file   (default: wiredbot.json)
```

```bash
# Generates a wiredbot.json with all default values
wiredbot generate-config --output /etc/wiredbot/wiredbot.json
```

---

## Configuration Reference

The configuration is a **JSON** file read at startup. Minimal example:

```json
{
  "server":   { "url": "wired://mybot:password@wired.example.com:4871" },
  "identity": { "nick": "MyBot" },
  "llm":      { "provider": "ollama", "model": "llama3" },
  "behavior": {},
  "triggers": [],
  "daemon":   { "foreground": true }
}
```

Any missing keys use their default value.

---

### `server`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `url` | string | `"wired://guest@localhost:4871"` | Full Wired server URL. Format: `wired://login:password@host:port` |
| `channels` | [uint] | `[1]` | Channel IDs to join after connecting. `1` = public chat. |
| `reconnectDelay` | float | `30.0` | Seconds to wait between reconnection attempts. |
| `maxReconnectAttempts` | int | `0` | Max number of attempts. `0` = unlimited. |
| `specPath` | string? | `null` | Path to `wired.xml`. `null` = auto-detection (see below). |

**`wired.xml` auto-detection** — The bot searches in this order:

1. `specPath` value in config
2. `--spec` command-line flag
3. Same directory as the binary
4. `./wired.xml`, `./Resources/wired.xml`
5. `/etc/wiredbot/wired.xml`
6. `/usr/share/wiredbot/wired.xml`
7. `/usr/local/share/wiredbot/wired.xml`

```json
"server": {
  "url": "wired://botaccount:s3cr3t@chat.myserver.com:4871",
  "channels": [1, 5, 12],
  "reconnectDelay": 15.0,
  "maxReconnectAttempts": 10,
  "specPath": "/opt/wired/wired.xml"
}
```

---

### `identity`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `nick` | string | `"WiredBot"` | Bot nickname on the server. |
| `status` | string | `"Powered by AI"` | Status message visible in the user list. |
| `icon` | string? | `null` | Base64-encoded icon (same format as Wired). `null` = default icon. |
| `idleTimeout` | float | `0` | Seconds before going idle. `0` = never. |

```json
"identity": {
  "nick": "HAL9000",
  "status": "I'm sorry, I can't do that.",
  "icon": null,
  "idleTimeout": 0
}
```

To encode an icon in base64:

```bash
base64 -w 0 my-icon.png
```

---

### `llm`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `provider` | string | `"ollama"` | LLM backend: `"ollama"`, `"openai"`, `"anthropic"` |
| `endpoint` | string | `"http://localhost:11434"` | API base URL (without `/v1` or `/api`). |
| `apiKey` | string? | `null` | API key. Required for `openai` and `anthropic`. |
| `model` | string | `"llama3"` | Model name. Examples: `"llama3"`, `"gpt-4o"`, `"claude-sonnet-4-6"` |
| `systemPrompt` | string | *(see default)* | System prompt injected at the top of each conversation. Supports `{nick}`, `{server}` variables. |
| `temperature` | float | `0.7` | Response creativity. `0.0` = deterministic, `1.0` = very creative. |
| `maxTokens` | int | `512` | Maximum number of tokens in an LLM response. |
| `contextMessages` | int | `10` | Number of conversation turns remembered per user conversation. |
| `timeoutSeconds` | float | `30.0` | HTTP request timeout for LLM calls. |
| `contextMaxAgeSeconds` | float | `7200.0` | Messages older than this (seconds) are excluded from context. `0` = keep all. Default: 2 hours. |
| `enableSummarization` | bool | `false` | When the context window fills up, summarise the oldest half via LLM instead of silently dropping it. Costs one extra LLM call but gives the bot long-term memory. |

```json
"llm": {
  "provider": "ollama",
  "endpoint": "http://localhost:11434",
  "apiKey": null,
  "model": "mistral",
  "systemPrompt": "You are a helpful assistant on a Wired server. Be concise, limit your answers to 2-3 sentences. No markdown — plain text only.",
  "temperature": 0.5,
  "maxTokens": 256,
  "contextMessages": 8,
  "timeoutSeconds": 20.0
}
```

---

### `behavior`

Controls when and how the bot reacts to events.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `respondToMentions` | bool | `true` | Reply when the bot's nick (or a `mentionKeyword`) is detected in a message. |
| `respondToAll` | bool | `false` | Reply to **all** public messages. Use with caution and a high `rateLimitSeconds`. |
| `respondToPrivateMessages` | bool | `true` | Reply to private messages (DMs). |
| `respondToConversation` | bool | `false` | Once a user has started a conversation (by mention or trigger), keep replying to their subsequent messages **without requiring a new mention**, as long as the silence gap is below `threadTimeoutSeconds`. |
| `respondInUserLanguage` | bool | `true` | Detect the language of each user message and always reply in the same language. The instruction is injected into the system prompt so the LLM handles detection natively. |
| `greetOnJoin` | bool | `true` | Send a welcome message when a user joins a channel. |
| `greetMessage` | string | `"Welcome, {nick}!"` | Welcome message template. Supports `{nick}`, `{chatID}`. |
| `farewellOnLeave` | bool | `false` | Send a farewell message when a user leaves. |
| `farewellMessage` | string | `"Goodbye, {nick}!"` | Farewell message template. |
| `announceNewThreads` | bool | `true` | Announce new board posts. |
| `announceNewThreadMessage` | string | `"New board post: \"{subject}\" by {nick}"` | Announcement template. Supports `{nick}`, `{subject}`, `{board}`. |
| `announceFileUploads` | bool | `false` | Announce files uploaded to the server. |
| `announceFileMessage` | string | `"{nick} uploaded: {filename}"` | Announcement template. Supports `{nick}`, `{filename}`, `{path}`. |
| `rateLimitSeconds` | float | `2.0` | Minimum delay (seconds) between two bot responses. Prevents spam. |
| `maxResponseLength` | int | `500` | Maximum response length (characters). Longer responses are truncated with `…`. |
| `ignoreOwnMessages` | bool | `true` | Ignore messages sent by the bot itself (prevents loops). |
| `ignoredNicks` | [string] | `[]` | List of nicknames that will always be ignored. |
| `mentionKeywords` | [string] | `[]` | Additional keywords that count as a bot mention (in addition to the nick). |
| `threadTimeoutSeconds` | float | `300.0` | Seconds of silence after which the bot considers a new conversation has begun and injects a `--- New conversation after a break ---` separator into the context. `0` = disabled. |
| `spontaneousReply` | bool | `false` | Allow the bot to join conversations naturally without being mentioned. The LLM itself decides whether to interject by replying `RESPOND: <msg>` or `SILENT`. |
| `spontaneousCheckInterval` | int | `5` | Check for an interjection opportunity every N messages in a channel. Lower = more reactive, higher = quieter. |
| `spontaneousCooldownSeconds` | float | `120.0` | Minimum seconds between two spontaneous replies in the same channel. Prevents the bot from dominating the conversation. |

```json
"behavior": {
  "respondToMentions": true,
  "respondToAll": false,
  "respondToPrivateMessages": true,
  "respondToConversation": true,
  "respondInUserLanguage": true,
  "greetOnJoin": true,
  "greetMessage": "Hey {nick}, welcome to the server!",
  "farewellOnLeave": true,
  "farewellMessage": "See you, {nick}!",
  "announceNewThreads": true,
  "announceNewThreadMessage": "New board post: \"{subject}\" by {nick}",
  "announceFileUploads": false,
  "announceFileMessage": "{nick} uploaded: {filename}",
  "rateLimitSeconds": 3.0,
  "maxResponseLength": 400,
  "ignoreOwnMessages": true,
  "ignoredNicks": ["Spambot", "OldBot"],
  "mentionKeywords": ["!bot", "@bot", "hey bot"],
  "spontaneousReply": true,
  "spontaneousCheckInterval": 6,
  "spontaneousCooldownSeconds": 180.0
}
```

#### Context architecture

Each user in a public channel gets their own isolated conversation context (keyed by stable `userID`, not nick). Two layers coexist:

```
┌─────────────────────────────────────────────────────┐
│  AWARENESS LAYER  (read-only, injected as system)   │
│  Last 10 messages from everyone in the channel      │
│  "[Alice] Anyone know a good Swift library?"        │
│  "[Bob] I use Vapor for networking"                 │
├─────────────────────────────────────────────────────┤
│  CONVERSATION LAYER  (per user, bot↔user only)      │
│  The actual dialogue between this user and the bot  │
│  Keyed: "channel-<chatID>-<userID>"                 │
└─────────────────────────────────────────────────────┘
```

This means Alice asking about Python and Bob asking about the weather don't pollute each other's context — but the bot still knows what's happening in the channel.

**Thread timeout:** after `threadTimeoutSeconds` of silence from a user, the bot injects a separator marker so the LLM understands the previous topic is closed.

**Context summarisation:** when `enableSummarization` is true and the context window fills up, the oldest half is summarised into a single compact entry instead of being discarded. This gives the bot effective long-term memory at the cost of one extra LLM call per overflow.

**Temporal expiry:** messages older than `contextMaxAgeSeconds` are excluded at call time, so stale context from hours ago doesn't influence current replies.

#### How spontaneous interjection works

When `spontaneousReply` is enabled, the bot silently accumulates every public message in a rolling buffer (up to 20 messages). Every `spontaneousCheckInterval` messages — and only if `spontaneousCooldownSeconds` have elapsed since the last spontaneous reply — the bot sends the recent chat log to the LLM with this meta-prompt:

> *"You are WiredBot, observing a public chat. Reply with RESPOND: \<your message\> or SILENT."*

The LLM decides entirely on its own whether to join the conversation. No keyword, no trigger, no mention required. If the LLM replies `SILENT`, nothing is sent. This mechanism runs in addition to (not instead of) mentions and explicit triggers.

**Tuning tips:**
- `spontaneousCheckInterval: 3` + `spontaneousCooldownSeconds: 60` → chatty bot, joins frequently
- `spontaneousCheckInterval: 10` + `spontaneousCooldownSeconds: 300` → reserved bot, only speaks when clearly relevant
- Your LLM's system prompt influences how selective the bot is — add *"Only interject when you are confident you add value"* to keep it quiet.

---

### `triggers`

Array of custom triggers. Each trigger is a JSON object.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | yes | Unique identifier (used for logs and cooldowns). |
| `pattern` | string | yes | Regular expression (POSIX extended) tested against the message text. |
| `eventTypes` | [string] | no | Activating event types: `"chat"`, `"private"`, `"all"`. Default: `["chat", "private"]`. |
| `response` | string? | no | Static response. Takes priority over `useLLM`. Supports `{variable}` templates. |
| `useLLM` | bool | no | If `true` and `response` is absent, sends the input to the LLM. Default: `false`. |
| `llmPromptPrefix` | string? | no | Text prepended to user input before sending to the LLM. |
| `caseSensitive` | bool | no | Is the regex case-sensitive? Default: `false`. |
| `cooldownSeconds` | float | no | Delay between two firings of the same trigger **per user**. `0` = no cooldown. |

**Priority order:** Triggers are tested in array order. The **first match** wins. If no trigger matches, the bot checks for a mention before calling the LLM.

```json
"triggers": [
  {
    "name": "ping",
    "pattern": "^!ping$",
    "eventTypes": ["chat", "private"],
    "response": "Pong!",
    "caseSensitive": false,
    "cooldownSeconds": 0
  },
  {
    "name": "weather",
    "pattern": "^!weather (.+)",
    "eventTypes": ["chat"],
    "useLLM": true,
    "llmPromptPrefix": "Give the current weather for this city (answer in 1-2 sentences): ",
    "cooldownSeconds": 10
  },
  {
    "name": "joke",
    "pattern": "^!joke",
    "eventTypes": ["chat", "private"],
    "useLLM": true,
    "llmPromptPrefix": "Tell a short, funny joke: ",
    "cooldownSeconds": 15
  },
  {
    "name": "help",
    "pattern": "^!(help|\\?)",
    "eventTypes": ["chat", "private"],
    "response": "Commands: !ping, !help, !ask <question>, !joke | Mention the bot to chat.",
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

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `foreground` | bool | `false` | Do not fork into the background. Useful for Docker, systemd with `Type=simple`, or debugging. |
| `pidFile` | string | `"/tmp/wiredbot.pid"` | Path of the PID file written at startup and removed at shutdown. |
| `logFile` | string? | `null` | Log file path. `null` = stdout only. |
| `logLevel` | string | `"INFO"` | Log level: `"DEBUG"`, `"INFO"`, `"WARNING"`, `"ERROR"`. |

```json
"daemon": {
  "foreground": false,
  "pidFile": "/var/run/wiredbot/wiredbot.pid",
  "logFile": "/var/log/wiredbot/wiredbot.log",
  "logLevel": "INFO"
}
```

> **Note:** The `--verbose` command-line flag forces `DEBUG` level regardless of `logLevel`.

---

## LLM Providers

### Ollama

Ideal for a fully local deployment. No API key required.

```bash
# Install Ollama and pull a model
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

Ollama on a remote host (e.g. dedicated GPU server):

```json
"llm": {
  "provider": "ollama",
  "endpoint": "http://192.168.1.50:11434",
  "model": "llama3:70b"
}
```

---

### OpenAI-compatible (LM Studio, Groq…)

This provider works with **any server exposing the `/v1/chat/completions` API**: official OpenAI, [LM Studio](https://lmstudio.ai), [Groq](https://groq.com), [Mistral](https://mistral.ai), [Together AI](https://together.ai), etc.

**OpenAI**
```json
"llm": {
  "provider": "openai",
  "endpoint": "https://api.openai.com",
  "apiKey": "sk-...",
  "model": "gpt-4o"
}
```

**LM Studio** (local, no API key)
```json
"llm": {
  "provider": "openai",
  "endpoint": "http://localhost:1234",
  "model": "local-model"
}
```

**Groq** (ultra-fast, free with limits)
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

> The `endpoint` field is ignored for Anthropic (the URL is fixed: `https://api.anthropic.com/v1/messages`).

Available models:
- `claude-opus-4-6` — Most powerful
- `claude-sonnet-4-6` — Best speed/quality balance (recommended)
- `claude-haiku-4-5-20251001` — Fastest and most economical

---

## Trigger System

### Execution Order

For each received message:

```
1. Message is ignored if sender is in ignoredNicks
   or if ignoreOwnMessages = true and it's the bot itself
   ↓
2. Triggers are tested in JSON array order
   → First match: static response OR LLM dispatch with prefix
   → Processing ends
   ↓
3. If respondToAll = true
   OR (respondToMentions = true AND mention detected)
   OR (respondToConversation = true AND user has an active context)
   → LLM dispatch with full message
   ↓
4. Otherwise: silence
```

### Regular Expressions

Patterns use **POSIX extended** syntax (NSRegularExpression).
By default patterns are **case-insensitive** (`caseSensitive: false`).

Useful anchors:
- `^` start of message, `$` end
- `(.+)` capture one or more characters
- `\s` whitespace, `\w` alphanumeric
- `(a|b)` alternation

Examples:

```json
{ "pattern": "^!ping$" }                       // exactly "!ping"
{ "pattern": "^!ask (.+)" }                    // starts with "!ask "
{ "pattern": "hello|hi|hey" }                  // anywhere in the message
{ "pattern": "^!(help|\\?)" }                  // !help or !?
{ "pattern": "\\bwired\\b" }                   // standalone word "wired"
```

### Cooldowns

Cooldowns apply **per user** (not globally). If `cooldownSeconds: 10` is set on a `!joke` trigger, each user can fire that trigger at most once every 10 seconds, but multiple different users can fire it simultaneously.

### LLM Dispatch with Prefix

`llmPromptPrefix` is concatenated to the user's message **before** sending to the LLM, but the original message remains in the conversation context.

```json
{
  "name": "summarize",
  "pattern": "^!summarize (.+)",
  "useLLM": true,
  "llmPromptPrefix": "Summarize this text in one sentence: "
}
```

If the user sends `!summarize Lorem ipsum dolor sit amet...`, the LLM receives:
`"Summarize this text in one sentence: Lorem ipsum dolor sit amet..."`

---

## Template Variables

`{variable}` templates are available in `response`, `greetMessage`, `farewellMessage`, `announceNewThreadMessage` and `announceFileMessage`.

| Variable | Available in | Description |
|----------|-------------|-------------|
| `{nick}` | all | Nickname of the user involved |
| `{input}` | `response` | Original message text that triggered the trigger |
| `{chatID}` | `response`, `greetMessage`, `farewellMessage` | Numeric channel ID |
| `{subject}` | `announceNewThreadMessage` | Subject of the new thread |
| `{board}` | `announceNewThreadMessage` | Board name |
| `{filename}` | `announceFileMessage` | Filename (without path) |
| `{path}` | `announceFileMessage` | Full file path |

---

## Linux Daemon Mode

In daemon mode (default when `foreground: false`), the process:

1. Performs a double `fork()` to detach from the terminal
2. Creates a new session (`setsid`)
3. Redirects stdin/stdout/stderr to `/dev/null`
4. Writes its PID to `pidFile`

**Supported signals:**

| Signal | Action |
|--------|--------|
| `SIGTERM` | Clean shutdown: closes connection, removes PID file |
| `SIGINT` | Same (Ctrl+C in foreground mode) |
| `SIGHUP` | Reload notification (log only — a restart is required to apply config changes) |

```bash
# Clean shutdown
kill $(cat /tmp/wiredbot.pid)

# Signal a reload
kill -HUP $(cat /tmp/wiredbot.pid)
```

---

## Systemd

A sample unit file is provided in `Examples/wiredbot.service`.

Installation:

```bash
# Create a dedicated system user
sudo useradd --system --no-create-home --shell /usr/sbin/nologin wiredbot

# Create required directories
sudo mkdir -p /etc/wiredbot /var/log/wiredbot /var/run/wiredbot
sudo chown wiredbot:wiredbot /var/log/wiredbot /var/run/wiredbot

# Copy files
sudo cp .build/release/WiredChatBot /usr/local/bin/wiredbot
sudo cp Sources/WiredSwift/Resources/wired.xml /usr/share/wiredbot/
sudo cp Examples/wiredbot-example.json /etc/wiredbot/wiredbot.json
sudo cp Examples/wiredbot.service /etc/systemd/system/

# Edit configuration
sudo nano /etc/wiredbot/wiredbot.json

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now wiredbot

# Check status
sudo systemctl status wiredbot
sudo journalctl -u wiredbot -f
```

For systemd, use `Type=forking` with daemon mode enabled, or `Type=simple` with `foreground: true` in the config (and remove `PIDFile` from the unit).

---

## macOS SwiftUI Wrapper

`BotController` is designed to be easily observable from SwiftUI:

```swift
import SwiftUI
import WiredSwift

// Observable wrapper
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
            Text(vm.isConnected ? "Connected" : "Disconnected")
            Button("Start") {
                Task.detached {
                    try? vm.controller.start(specPath: specPath)
                }
            }
        }
    }
}
```

All state mutations in `BotController` happen on the main queue (`ConnectionDelegate` callbacks are dispatched there by WiredSwift), making them compatible with `@Published` without additional `DispatchQueue.main.async`.

---

## Troubleshooting

**Bot cannot find `wired.xml`**
```bash
wiredbot run --spec /path/to/wired.xml --foreground --verbose
```
Also check `server.specPath` in the config.

**Connection refused**
- Check the URL (`wired://login:password@host:port`)
- The account must exist on the server and have connection privileges
- Port 4871 must be open (firewall, NAT)

**LLM not responding**
- Test the endpoint manually:
  ```bash
  curl http://localhost:11434/api/chat -d '{"model":"llama3","messages":[{"role":"user","content":"test"}],"stream":false}'
  ```
- Increase `timeoutSeconds` if the model is slow
- Check `apiKey` for cloud providers

**Bot responds in a loop**
- Make sure `ignoreOwnMessages: true` (default)
- Add the bot's nick to `ignoredNicks` on other instances

**Logs**
```bash
# Watch logs in real time (daemon mode)
tail -f /tmp/wiredbot.log

# DEBUG level to see everything
wiredbot run --foreground --verbose
```
