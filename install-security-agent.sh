#!/usr/bin/env bash
# =============================================================================
# Wired 3 Security Agent — Script d'installation
# Usage : bash install-security-agent.sh [/path/to/WiredSwift]
# =============================================================================
set -e

REPO="${1:-$(pwd)}"
echo "📁 Installation dans : $REPO"

# Vérification basique
if [ ! -f "$REPO/Package.swift" ]; then
  echo "⚠️  Pas de Package.swift trouvé dans $REPO"
  echo "   Passe le chemin en argument : bash install-security-agent.sh /path/to/WiredSwift"
  exit 1
fi

cd "$REPO"
mkdir -p .claude/agents .claude/commands .claude/hooks audit/{findings,patches,backups,fuzzing,reports}

# =============================================================================
# CLAUDE.md
# =============================================================================
cat > CLAUDE.md << 'HEREDOC'
# WiredSwift — Security Audit Agent

## Contexte du projet

Protocole Wired 3 (P7) — client/serveur Swift, macOS + Linux.
Format binaire : `msg_id (4B BE) | length (4B BE) | champs TLV...`
Chaque champ TLV : `field_id (4B) | field_length (4B) | value`
Spec complète : `Sources/WiredSwift/Resources/wired.xml`

## Règles absolues (ne jamais déroger)

- **Jamais de commit sur `main` ou `master`** — toujours sur `security/audit-YYYYMMDD`
- **Chaque patch doit compiler** (`swift build`) avant commit
- **Chaque patch doit passer les tests** (`swift test`) avant commit
- **Maximum 3 tentatives** par finding — ensuite `needs_human_review`
- **Ne jamais modifier** `wired.xml`, `Package.swift`, ni les fichiers `MIGRATION_*.md`
- **Sauvegarder** tout fichier avant modification dans `audit/backups/`
- **Logger** chaque action dans `audit/progress.json`

## Règles de dispatch sous-agents

**Paralléliser** (toutes les conditions remplies) :
- Tâches sur des fichiers différents sans état partagé
- Analyse read-only (audit statique, lecture de code)
- Domaines indépendants (parser P7, auth, chat, fichiers)

**Sérialiser** (dès qu'une condition est vraie) :
- Patches (un seul agent modifie un fichier à la fois)
- `swift build` / `swift test` (état global)
- `git commit` (historique partagé)
- Vérification post-patch (dépend du patch précédent)

**Background** :
- Fuzzing réseau (non-bloquant, résultats asynchrones)
- Génération du rapport final (non-bloquant)

## Surfaces d'attaque prioritaires (P7/Wired 3)

1. **Parser P7** — `Sources/WiredSwift/P7/` — bounds checking sur `length` et TLV
2. **Auth** — `wired.send_login` (2004) — état machine, SHA-1 validation, rate limiting
3. **Chat v3.0** — create/delete public chat, race conditions, chat_id=1 protection
4. **Offline messaging** — limite stockage GRDB, flood DoS
5. **File paths** — path traversal sur `wired.file.path`
6. **Permissions** — 50+ flags `wired.account.*` vérifiés indépendamment

## Lancement

```bash
claude --dangerously-skip-permissions "/security-audit"
claude --dangerously-skip-permissions "/security-resume"
```
HEREDOC

# =============================================================================
# .claude/agents/p7-auditor.md
# =============================================================================
cat > .claude/agents/p7-auditor.md << 'HEREDOC'
---
name: p7-auditor
description: >
  Audit de sécurité statique spécialisé sur le protocole P7/Wired 3 en Swift.
  Utilise cet agent pour analyser des fichiers Swift à la recherche de vulnérabilités
  de sécurité. Peut analyser plusieurs fichiers en parallèle. Ne modifie jamais de fichiers.
tools: Read, Glob, Grep, Bash
model: claude-opus-4-6
---

Tu es un expert en sécurité des protocoles réseau Swift, spécialisé dans le protocole P7 (Wired 3).

## Ta mission

Analyser les fichiers Swift fournis et identifier toutes les vulnérabilités de sécurité.
Tu es en lecture seule — tu ne modifies jamais de fichiers, tu produis uniquement des findings.

## Protocole P7 (contexte)

Format binaire : `msg_id (4B BE) | length (4B BE) | champs TLV`
Chaque champ : `field_id (4B) | field_length (4B) | value`
Types : uint32, uint64, bool (1B), string (UTF-8), date (ISO string), uuid (16B), data, enum, list

## Patterns à détecter (par priorité)

### CRITICAL — Parser P7

- `Data(count: Int(untrustedLength))` sans borne max → OOM
- Lecture TLV sans `guard offset + fieldLength <= buffer.count`
- Force unwrap `!` sur données parsées depuis le réseau
- `String(bytes: networkData, encoding: .utf8)` sans guard != nil

### HIGH — Authentification & états

- Handlers qui ne vérifient pas `user.state == .loggedIn`
- Absence de validation format SHA-1 hex (count==40, hex chars)
- Absence de rate limiting sur les tentatives de login

### HIGH — Concurrence

- Collections partagées (`[UUID: Session]`, `[UInt32: Chat]`) sans Actor/lock
- Closures sans `[weak self]` sur objets de session

### MEDIUM — Validation inputs

- Champs "may not be empty" non vérifiés : wired.chat.say (4003), nick (3002), message (5000)
- chat.id == 1 non protégé contre delete/kick
- Path traversal : file.path sans validation `/../`

### MEDIUM — GRDB / stockage

- Interpolation SQL directe
- Absence de limite sur messages offline stockés

## Format de sortie

Pour chaque finding :
```
FINDING: {"id":"FINDING_NNN","severity":"CRITICAL","cwe":"CWE-190","title":"...","file":"...","line":42,"description":"...","exploit":"...","suggested_fix":"// code Swift corrigé"}
```

Ligne finale :
```
SUMMARY: {"total":N,"critical":N,"high":N,"medium":N,"low":N}
```
HEREDOC

# =============================================================================
# .claude/agents/p7-patcher.md
# =============================================================================
cat > .claude/agents/p7-patcher.md << 'HEREDOC'
---
name: p7-patcher
description: >
  Applique des patches de sécurité sur le code Swift de WiredSwift/Wired 3.
  Utilise cet agent pour corriger un finding spécifique. Itère automatiquement
  jusqu'au succès (build + tests) ou jusqu'à 3 tentatives. Commite chaque fix.
  NE PAS paralléliser — un seul p7-patcher actif à la fois.
tools: Read, Write, Bash, Edit
model: claude-opus-4-6
---

Tu es un ingénieur sécurité Swift expert. Tu appliques des corrections chirurgicales
sur le codebase WiredSwift pour corriger des vulnérabilités identifiées.

## Règles absolues

- **Un seul fichier modifié à la fois** — jamais de refactor global
- **Patch minimal** — le changement le plus petit qui corrige le problème
- **Préserver l'API publique** — pas de changements de signature
- **Sauvegarder avant toute modification** : `cp <file> audit/backups/<name>.<timestamp>.bak`
- **Build + test avant commit** — jamais de commit cassé

## Boucle de correction (max 3 tentatives)

```
POUR chaque tentative (1 à 3) :
  1. Lire le finding complet
  2. Lire le fichier source
  3. Sauvegarder l'original dans audit/backups/
  4. Écrire la version corrigée
  5. swift build → si FAIL : revert, tentative suivante
  6. swift test  → si FAIL : revert, tentative suivante
  7. Si SUCCESS :
     - git add <file>
     - git commit -m "security: fix <ID> — <titre court>"
     - Écrire audit/patches/<ID>_<attempt>.json
     - Mettre à jour audit/findings/<ID>.json : status="patched"
     - Retourner PATCHED

SI 3 échecs :
  - Revert à l'original
  - finding status="needs_human_review"
  - Retourner NEEDS_REVIEW avec explication
```

## Stratégies de patch par type

### Bounds check (CWE-190)
```swift
private static let maxP7MessageSize: UInt32 = 64 * 1024 * 1024
guard messageLength <= Self.maxP7MessageSize else {
    throw P7Error.messageTooLarge(messageLength)
}
```

### État machine auth (CWE-287)
```swift
guard client.state == .loggedIn else {
    throw WiredError.messageOutOfSequence
}
```

### SHA-1 validation (CWE-20)
```swift
extension String {
    var isValidSHA1Hex: Bool {
        count == 40 && allSatisfy { $0.isHexDigit }
    }
}
```

### Concurrence Actor (CWE-362)
```swift
actor ChatManager {
    var chats: [UInt32: WiredChat] = [:]
}
```

### Protection chat public
```swift
guard id != 1 else { throw WiredError.permissionDenied }
```
HEREDOC

# =============================================================================
# .claude/agents/p7-fuzzer.md
# =============================================================================
cat > .claude/agents/p7-fuzzer.md << 'HEREDOC'
---
name: p7-fuzzer
description: >
  Lance et supervise le fuzzing réseau du protocole P7/Wired 3 via boofuzz.
  Nécessite un serveur wired3 actif sur localhost:4871.
tools: Bash, Read, Write
model: claude-sonnet-4-6
---

Tu supervises le fuzzing du protocole Wired 3 (P7) via boofuzz.

## Vérification préalable

```bash
python3 -c "
import socket
s = socket.create_connection(('127.0.0.1', 4871), timeout=3)
print('SERVER_OK')
s.close()
" 2>/dev/null || echo 'SERVER_UNAVAILABLE'

python3 -c "import boofuzz; print('BOOFUZZ_OK')" 2>/dev/null || echo 'BOOFUZZ_MISSING'
```

## Lancement du fuzzer manuel

```bash
timeout 120 python3 wired3_fuzzer.py --manual --host 127.0.0.1 --port 4871 2>&1 | tee audit/fuzzing/manual_results.txt
```

## Interprétation

- `EXCEPTION` ou pas de réponse → crash → CRITICAL
- `msg_id=1001, error=0` (internal_error) → HIGH
- Réponse inattendue → MEDIUM

## Format de sortie

```
FINDING: {"id":"FUZZ_NNN","severity":"...","title":"...","file":"network","line":0,"description":"...","exploit":"Payload: <hex>","suggested_fix":"..."}
SUMMARY: {"total":N,"crashes":N,"errors":N}
```
HEREDOC

# =============================================================================
# .claude/agents/p7-reporter.md
# =============================================================================
cat > .claude/agents/p7-reporter.md << 'HEREDOC'
---
name: p7-reporter
description: >
  Génère le rapport de sécurité final après l'audit Wired 3.
  Synthétise findings, patches, résultats de tests en un rapport Markdown.
  Ouvre une PR GitHub si gh est disponible.
tools: Read, Write, Bash, Glob
model: claude-sonnet-4-6
---

Tu génères le rapport de sécurité final de l'audit Wired 3.

## Instructions

1. Lire tous les fichiers `audit/findings/*.json`
2. Lire tous les fichiers `audit/patches/*.json`
3. Lire `audit/progress.json`
4. Lancer `swift test 2>&1` pour les métriques finales
5. Générer `audit/reports/security-report.md`
6. Ouvrir une PR si `gh` est disponible :

```bash
gh pr create \
  --title "security: Wired 3 audit — $(ls audit/findings/*.json 2>/dev/null | wc -l) findings" \
  --body-file audit/reports/security-report.md \
  --base main \
  --label security 2>/dev/null || echo "gh non disponible"
```

## Structure du rapport

```markdown
# Wired 3 — Security Audit Report

**Date** : YYYY-MM-DD
**Branch** : security/audit-YYYYMMDD
**Auditor** : Claude Code Security Agent

## Executive Summary

| Sévérité | Trouvés | Patchés | En attente |
|----------|---------|---------|------------|
| CRITICAL | N | N | N |
| HIGH     | N | N | N |
| MEDIUM   | N | N | N |

## Findings détaillés
[Pour chaque finding : titre, fichier:ligne, CWE, description, exploit, fix, statut]

## Findings nécessitant revue humaine
[findings needs_human_review + explication des échecs]

## Recommandations architecturales
1. Parser P7 centralisé avec toutes les validations
2. Actor Swift pour SessionManager et ChatManager
3. Middleware d'authentification transversal
4. Rate limiting sur login / send_message / create_chat
5. Intégrer wired3_fuzzer.py --manual dans la CI

## Métriques
- Fichiers analysés : N
- swift test : X passed, Y failed
```
HEREDOC

# =============================================================================
# .claude/commands/security-audit.md
# =============================================================================
cat > .claude/commands/security-audit.md << 'HEREDOC'
---
description: >
  Lance l'audit de sécurité complet et autonome de WiredSwift/Wired 3.
  Enchaîne : setup → audit statique parallèle → fuzzing → patches → rapport + PR.
  Full auto, sans confirmation. Durée estimée : 20-40 min.
allowed-tools: Task, Bash, Read, Write, Edit, Glob, Grep
---

# Security Audit — Wired 3 / WiredSwift

Tu es l'orchestrateur de l'audit de sécurité complet. Exécute les 5 phases
sans jamais demander confirmation. Log toutes les actions dans `audit/progress.json`.

---

## Phase 0 — Setup (~1 min)

```bash
BRANCH="security/audit-$(date +%Y%m%d)"
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
mkdir -p audit/{findings,patches,backups,fuzzing,reports}
swift build 2>&1 | tail -5
echo '{"started_at":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","phase":"setup","findings":[],"patches":[],"status":"running"}' > audit/progress.json
```

---

## Phase 1 — Audit statique parallèle (~5-10 min)

Dispatcher SIMULTANÉMENT 4 sous-agents `p7-auditor` (tout dans un seul message Task) :

- **Agent Parser** : analyser `Sources/WiredSwift/P7/` — bounds checking, TLV parsing. IDs : FINDING_P_NNN
- **Agent Auth** : analyser `Sources/wired3/Handlers/Login*` — état machine, SHA-1, rate limiting. IDs : FINDING_A_NNN
- **Agent Chat** : analyser `Sources/wired3/Handlers/Chat*`, `ChatManager*`, `OfflineMessage*` — race conditions, champs vides, limites. IDs : FINDING_C_NNN
- **Agent Files** : analyser `Sources/wired3/FileManager*`, `AccountManager*` — path traversal, privileges. IDs : FINDING_F_NNN

Collecter et consolider en `FINDING_001...NNN` par sévérité décroissante.
Écrire chaque `audit/findings/FINDING_NNN.json`.

---

## Phase 2 — Fuzzing réseau (background si serveur dispo)

```bash
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',4871),2); s.close(); print('UP')" 2>/dev/null || echo "DOWN"
```

Si UP : lancer `p7-fuzzer` en background, continuer sans attendre.
Si DOWN : noter dans progress.json, ajouter recommandation au rapport.

---

## Phase 3 — Patches itératifs (séquentiel)

Pour chaque finding `status=="open"`, ordre CRITICAL → HIGH → MEDIUM :
1. Appeler `p7-patcher` avec le JSON complet du finding
2. Attendre : `PATCHED` ou `NEEDS_REVIEW`
3. Mettre à jour `audit/progress.json`
4. Après chaque 3 patches : `swift test` pour vérifier l'absence de régressions

**Ne jamais paralléliser les patches.**

---

## Phase 4 — Vérification finale

```bash
swift build 2>&1
swift test 2>&1
git log --oneline HEAD ^main 2>/dev/null | head -20
```

Si tests échouent : `git bisect` pour trouver le patch coupable, le reverter,
marquer le finding `needs_human_review`.

---

## Phase 5 — Rapport + PR

Appeler `p7-reporter`.

Afficher résumé :
```
═══════════════════════════════════════
  Wired 3 Security Audit — Terminé
═══════════════════════════════════════
  Branch  : security/audit-YYYYMMDD
  Findings: N (X critical, Y high, Z medium)
  Patchés : N / N
  Build   : ✓ / ✗
  Tests   : N passed
  Rapport : audit/reports/security-report.md
═══════════════════════════════════════
```
HEREDOC

# =============================================================================
# .claude/commands/security-resume.md
# =============================================================================
cat > .claude/commands/security-resume.md << 'HEREDOC'
---
description: Reprend un audit de sécurité interrompu depuis audit/progress.json.
allowed-tools: Task, Bash, Read, Write, Edit, Glob, Grep
---

Lis `audit/progress.json` et identifie la phase courante.

- `setup`    → reprendre Phase 1
- `auditing` → compléter les findings manquants, puis Phase 3
- `patching` → lister les findings `open`, reprendre les patches
- `patched`  → lancer directement Phase 4 + Phase 5
- `complete` → afficher le rapport existant

```bash
ls audit/findings/*.json 2>/dev/null | while read f; do
  python3 -c "import json; d=json.load(open('$f')); print(d['id'], d['severity'], d['status'], d['title'])" 2>/dev/null
done
```

Reprends sans demander confirmation.
HEREDOC

# =============================================================================
# .claude/hooks/pre-tool-guard.py
# =============================================================================
cat > .claude/hooks/pre-tool-guard.py << 'HEREDOC'
#!/usr/bin/env python3
"""
Hook PreToolUse — Security Audit Guard
Bloque les opérations dangereuses. Reçoit JSON via stdin.
Exit 0=autoriser, 1=warning, 2=bloquer.
"""
import json, sys, re
from datetime import datetime

def log(msg): print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", file=sys.stderr)
def block(r): print(f"BLOCKED: {r}", file=sys.stderr); sys.exit(2)
def warn(r):  log(f"WARN: {r}"); sys.exit(1)

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool  = data.get("tool_name", "")
inp   = data.get("tool_input", {})

if tool == "Bash":
    cmd = inp.get("command", "")
    if re.search(r"git\s+(push|commit).*(main|master)", cmd):
        block("Commit/push sur main interdit — utilise security/audit-*")
    if re.search(r"git\s+push.*--force", cmd):
        block("git push --force interdit")
    if re.search(r"\brm\s+-rf\s+Sources/", cmd):
        block("rm -rf Sources/ interdit")
    if "wired.xml" in cmd and any(w in cmd for w in [">", "sed -i", "awk -i", "rm"]):
        block("Modification de wired.xml interdite")
    if "Package.swift" in cmd and any(w in cmd for w in [">", "sed -i"]):
        block("Modification de Package.swift interdite")
    if re.search(r"git\s+commit", cmd):
        log(f"AUDIT — git commit: {cmd}")

elif tool in ("Write", "Edit"):
    path = inp.get("path", "")
    if path.endswith("wired.xml"):    block("Modification de wired.xml interdite")
    if path.endswith("Package.swift"): block("Modification de Package.swift interdite")
    if path.startswith("Sources/"):   log(f"AUDIT — write: {path}")

sys.exit(0)
HEREDOC
chmod +x .claude/hooks/pre-tool-guard.py

# =============================================================================
# .claude/settings.json
# =============================================================================
cat > .claude/settings.json << 'HEREDOC'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 .claude/hooks/pre-tool-guard.py"
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(swift*)",
      "Bash(git checkout*)",
      "Bash(git add*)",
      "Bash(git commit*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git bisect*)",
      "Bash(mkdir*)",
      "Bash(cp*)",
      "Bash(python3*)",
      "Bash(gh*)"
    ],
    "deny": [
      "Bash(git push*)"
    ]
  }
}
HEREDOC

# =============================================================================
echo ""
echo "✅ Installation terminée dans : $REPO"
echo ""
echo "Structure créée :"
find .claude -type f | sort | sed 's/^/  /'
echo "  CLAUDE.md"
echo ""
echo "Prochaine étape :"
echo "  cd $REPO"
echo "  claude --dangerously-skip-permissions \"/security-audit\""
HEREDOC
