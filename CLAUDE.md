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
