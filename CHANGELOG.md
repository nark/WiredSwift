# Changelog

All notable changes to WiredSwift are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
## [3.0-beta.17+33] — 2026-04-02

### Bug Fixes
- Align server version path with Core layout ([`afee8c1`](https://github.com/nark/WiredSwift/commit/afee8c16a678a9a50acb4cd5252150a876badaf9))

- Preserve wired3 service state across upgrades ([`2f68374`](https://github.com/nark/WiredSwift/commit/2f6837416c68f7e360429777465feb723f0405c3))

- Stabilize accounts-changed integration broadcast assertion ([`f101f87`](https://github.com/nark/WiredSwift/commit/f101f87a4da2be7850a6fc2099bb2b2d9745ffae))

- Cast shutdown mode to Int32 in server stop ([`27356b1`](https://github.com/nark/WiredSwift/commit/27356b11a4daa17981fa57405482fa4f73d06230))

- Stabilize paths, index file size, and server shutdown ([`9480546`](https://github.com/nark/WiredSwift/commit/94805460610a9fc2f68d98261aa3d393cd05cd2c))

- Remove legacy LinuxMain test entrypoint ([`13d6bf0`](https://github.com/nark/WiredSwift/commit/13d6bf09788acc63cc83bca43a7b4e03ddd88cac))

- Use platform-safe SOCK_STREAM type on Linux ([`987a2fe`](https://github.com/nark/WiredSwift/commit/987a2fe4d4945659d9835c3c588c3e943851ad58))

- Exclude WiredServerApp target and product on Linux ([`2ead167`](https://github.com/nark/WiredSwift/commit/2ead167e6afa2c1156e2a2ff073c213e3ff27a82))

- Install full linux native deps for wired3 build ([`cfc8f66`](https://github.com/nark/WiredSwift/commit/cfc8f66ec481c06911dfe5fdb0e156f66e1917bc))

- Run linux dependency install step with bash ([`2454ee1`](https://github.com/nark/WiredSwift/commit/2454ee10f59ba370a4fd8e390b0fc335f6d2ff0e))

- Install sqlite dev and enable GRDBCUSTOMSQLITE on linux ([`3700b1f`](https://github.com/nark/WiredSwift/commit/3700b1fbf0c44e4cd751864784302097119af88a))

- Resolve SwiftLint CI errors after ServerController split ([`bdd0b51`](https://github.com/nark/WiredSwift/commit/bdd0b51274225b2fc827208b90f323926ced71e9))

- Fix two regressions introduced during warning cleanup ([`3cd6f07`](https://github.com/nark/WiredSwift/commit/3cd6f073fd12dae250ef81e00a4fa8b48c377c84))


### Documentation
- Simplify feature matrix wording ([`25b7040`](https://github.com/nark/WiredSwift/commit/25b7040a0e7914f7744bb94ef4a38d070d4782df))

- Improve feature matrix with visual status markers ([`9ffe82e`](https://github.com/nark/WiredSwift/commit/9ffe82ee83aa573d21f36d2c0a04ae4de0ab43ea))

- Fix symbol heading rendering in connection patterns ([`00ca8d5`](https://github.com/nark/WiredSwift/commit/00ca8d5b96750bfed2f1cf93fe6fd45ab1339736))

- Consolidate integration guides into a compact structure ([`77bbaa0`](https://github.com/nark/WiredSwift/commit/77bbaa0fc69bd790fa82cce7e710c75b19d578b1))

- Add catalog, CI generation, and pages publishing ([`4329c24`](https://github.com/nark/WiredSwift/commit/4329c242bd146b3592ec658ec23d3ffcc442296e))

- Add CODE_OF_CONDUCT.md and cliff.toml ([`b19dc08`](https://github.com/nark/WiredSwift/commit/b19dc08951dd9314ddb35d8648f76234bac87888))

- Add SECURITY.md with vulnerability reporting policy ([`ffdb991`](https://github.com/nark/WiredSwift/commit/ffdb9919feb6960fef4b6d061c80f5f5a8f4657d))

- Add /// documentation to all public API ([`e79afd0`](https://github.com/nark/WiredSwift/commit/e79afd00a84fffd48265dfc66dc1013ff5bee1db))

- Add /// documentation to all public API ([`f21420c`](https://github.com/nark/WiredSwift/commit/f21420cc96510bac29565b48b0539539f2c3d3ab))


### Features
- Implement quota fields — max_file_size_bytes, max_tree_size_bytes, exclude_patterns ([`361a214`](https://github.com/nark/WiredSwift/commit/361a214b1421c083b65adacf8048ffd5fcf8e047))

- Add SwiftLint 0.63 with zero-error baseline ([`ccd160d`](https://github.com/nark/WiredSwift/commit/ccd160daa46415079025007240e97392dc70f476))


### Refactoring
- Unify wired protocol spec ([`9e95dfb`](https://github.com/nark/WiredSwift/commit/9e95dfb967ce813dc8551a4041200c803720369a))

- Split ServerController into domain-specific extensions ([`c2e84f5`](https://github.com/nark/WiredSwift/commit/c2e84f5ea9ecdb7ca766a3382eeee1b9d7ed09c7))

- Reorganize sources into Core/, Models/, Controllers/, Database/ ([`914ddb9`](https://github.com/nark/WiredSwift/commit/914ddb9a90f39fee492fe4dc90885acefe503e75))


### Testing
- Harden macOS pipeline against flaky integration timing ([`1e3caa1`](https://github.com/nark/WiredSwift/commit/1e3caa1cd34a6524d588b6b77b68393f800649c8))

- Fix race condition in sendAndWaitMany tests ([`c2cea3b`](https://github.com/nark/WiredSwift/commit/c2cea3b5b5460c0632552d2b47798fee61f74e1f))

- Expand wired3 controller coverage for bootstrap clients logs ([`86cc30e`](https://github.com/nark/WiredSwift/commit/86cc30e5e0d29bfc99da9b66931711ea4a07ebf6))

- Expand file model and async connection coverage ([`f4ec7ab`](https://github.com/nark/WiredSwift/commit/f4ec7abed0a83255be1d910a7c7b3875a78e26f4))

- Harden flaky chat integration and expand connection coverage ([`8b7a504`](https://github.com/nark/WiredSwift/commit/8b7a5048a576aef9d149ce4eb570beb083bc0b1d))

- Deepen connection and p7 socket coverage ([`0289b7a`](https://github.com/nark/WiredSwift/commit/0289b7a1f0f4b4744974ce64c56402192da6080c))

- Expand coverage for connection and p7 socket io ([`8e3a2f1`](https://github.com/nark/WiredSwift/commit/8e3a2f144cc850dcb32d61b9cd814f9bdd136298))

- Extend coverage for logger, p7 message, file manager and chats controller ([`7122e74`](https://github.com/nark/WiredSwift/commit/7122e743315717bb34ef70815fe15ffa23a7aa39))

- Harden and massively expand coverage ([`86fd747`](https://github.com/nark/WiredSwift/commit/86fd74787a758b16e9a77806441c64ab5ada93cb))

- Add IndexController unit coverage ([`3afb8e0`](https://github.com/nark/WiredSwift/commit/3afb8e0afe2616f05bf00d52af61d6a8c2b18f80))

- Expand integration coverage for user status and board reactions ([`5330e2d`](https://github.com/nark/WiredSwift/commit/5330e2db0e9ca816b5708eac9c94caad73b22405))

- Harden transfer integration coverage for upload/download flows ([`338d66a`](https://github.com/nark/WiredSwift/commit/338d66abfac0ff7506e9121139097ae8cb91316d))

- Expand network coverage and enforce project-only coverage gate ([`fe27916`](https://github.com/nark/WiredSwift/commit/fe27916588962430e1be67f05363c5bdc7dc3cf0))

- Expand TransfersController queue and run coverage ([`4ce8403`](https://github.com/nark/WiredSwift/commit/4ce8403230c21e2376f58aec900448d05fa484c9))

## [3.0-beta.14+27] — 2026-03-25

### Bug Fixes
- Enforce one reaction per user, fix persistence ([`ddcbf41`](https://github.com/nark/WiredSwift/commit/ddcbf41f9ea68919042cb7b777eb124286913bd7))

- Correct migration SQL for add_reactions privilege ([`563a483`](https://github.com/nark/WiredSwift/commit/563a4831f78e947dbe5de04e61f3f67b32c78a4b))

- Migrate add_reactions privilege for existing accounts ([`54d1b2b`](https://github.com/nark/WiredSwift/commit/54d1b2b4b8befc4b43838b2686cdc7846ba5b763))


### Features
- Emoji reaction system for board threads and posts ([`1c39f86`](https://github.com/nark/WiredSwift/commit/1c39f86a16e3533cefa700795f2de09efafc70af))

- Add reaction.emojis and reaction.nicks fields (6029, 6030) ([`c79e44d`](https://github.com/nark/WiredSwift/commit/c79e44d0fe6d096da311c6b67f729c0e33489867))

- Include reactor nicks in reaction_list response ([`3d19c1a`](https://github.com/nark/WiredSwift/commit/3d19c1a0619fe1a0297d58377701825dad0287ac))

- Include thread emoji summary in thread_list protocol message ([`c1e3375`](https://github.com/nark/WiredSwift/commit/c1e337591db68be25ed7d8ec5c339ba187c97a7e))

- Implement emoji reaction system for board threads and posts ([`900b324`](https://github.com/nark/WiredSwift/commit/900b3244df80fea4528d248ef3128b5d738afef9))

## [3.0-beta.13+25] — 2026-03-24

### Bug Fixes
- Use stored errno from Socket.Error instead of global errno ([`07d50e6`](https://github.com/nark/WiredSwift/commit/07d50e6a69afa72b088405f3cc85f755661aa3dd))


### Features
- Add emoji reaction system to boards ([`15d9309`](https://github.com/nark/WiredSwift/commit/15d9309db0ef23693f2866eec6100da20d4c9d54))

- Implement wired.log.* protocol + fix Logger re-entrancy deadlock ([`30e78f1`](https://github.com/nark/WiredSwift/commit/30e78f158f3c32f8e25a510527cc923469bae9fc))

## [3.0-beta.12+24] — 2026-03-23

### Documentation
- Split Wired 3.0 into features and security ([`8a8413a`](https://github.com/nark/WiredSwift/commit/8a8413a4841e6f0397dee433d1ea8101753e5596))

## [3.0-beta.10+22] — 2026-03-19

### Bug Fixes
- Persist and reload strict identity toggle ([`e161366`](https://github.com/nark/WiredSwift/commit/e1613666552080a051266d341a8f45513c36f466))

- Preserve strict_identity in generated configs ([`59a8ecc`](https://github.com/nark/WiredSwift/commit/59a8eccf2bc6b4b2aff31dfae354fd8dc760a684))

## [3.0-beta.9+21] — 2026-03-18

### Bug Fixes
- Include stored password hash in read_user response ([`3d09753`](https://github.com/nark/WiredSwift/commit/3d097539034b27149099377d35f823cd6dcf006f))

- Don't regenerate salt on permissions-only account edits ([`afe1286`](https://github.com/nark/WiredSwift/commit/afe128688bffdbef93bc49c52dd2752cebafeac5))

- Guest login fails after permission edit (double-salted password bug) ([`f48bef1`](https://github.com/nark/WiredSwift/commit/f48bef18449a6f071c23c43b90b0b535d466a152))


### Features
- Implement wired.account.change_password on server ([`b3400ec`](https://github.com/nark/WiredSwift/commit/b3400ec49706565bf3ef2c9b81e9c8f023ae7c52))

## [3.0-beta.8+18] — 2026-03-17

### Bug Fixes
- Refine GeneralTabView — split versions into own section, fix labels and window height ([`a3257c9`](https://github.com/nark/WiredSwift/commit/a3257c906f348f9b1d158afdf4d082bf0243c2d4))

- Restrict wired-identity.key to 0600, harden packaging ([`5e6e2af`](https://github.com/nark/WiredSwift/commit/5e6e2afc594cda2e0bad8e14d39b518a21d71236))

- FINDING_F_016 — close TOCTOU window in delete/move/setPermissions ([`2db894f`](https://github.com/nark/WiredSwift/commit/2db894fc5bb0098d356049d855846e8bfe72ab5e))

- Address FUZZ_001, FUZZ_002; close A_012 and A_013 ([`988eefc`](https://github.com/nark/WiredSwift/commit/988eefc5cc0e099f75dc88df8b5723519de7bf23))

- Send builtinProtocolVersion in handshake instead of hardcoded "1.0" ([`52fe9a3`](https://github.com/nark/WiredSwift/commit/52fe9a3fb4b312ef734c82d47a1477f6ac7d75a6))

- Remove double-swap on enum field deserialization ([`8d8fcaa`](https://github.com/nark/WiredSwift/commit/8d8fcaa1cedaef3a8b2203913d7fb27ce39b2078))

- Revert auto-rehash that broke P7 key exchange ([`8e6530c`](https://github.com/nark/WiredSwift/commit/8e6530c4bc18eef713f9df7f1be80d6cc80f0386))


### Documentation
- Document admin password setup and server identity (TOFU) in README ([`d734074`](https://github.com/nark/WiredSwift/commit/d734074d9c2de965846434ee380ed19961cbc5ac))

- Add final security audit report — 72 findings, 65 patched ([`d35084e`](https://github.com/nark/WiredSwift/commit/d35084e3a1470e44d90890d2578ad9f5191f438f))


### Features
- Add serverTrustHandler for P7 v1.3 TOFU compatibility ([`2f688f7`](https://github.com/nark/WiredSwift/commit/2f688f7c6e7aa19b99d7e68b5fb89bc3221dca48))

- Display P7 and Wired protocol versions in GeneralTabView ([`1a6ef8a`](https://github.com/nark/WiredSwift/commit/1a6ef8aa283319bc7e33973c6302218644f7c492))

- Add server identity section to AdvancedTabView (TOFU) ([`c4a772f`](https://github.com/nark/WiredSwift/commit/c4a772fe52677d48df25aba77feed9844d036ed8))

- Forward serverTrustHandler to P7Socket in Connection ([`a62ea68`](https://github.com/nark/WiredSwift/commit/a62ea68d1f2deb3cdbb5de6ba9ee3c54ae27dcb1))

- FINDING_A_009 — implement TOFU server identity (P7 v1.3) ([`7808961`](https://github.com/nark/WiredSwift/commit/78089611a179e913b3c70773b1e2bfa6fae1fd8b))

- Implement per-user stored salt key exchange (breaking, P7 v1.2) ([`f806993`](https://github.com/nark/WiredSwift/commit/f8069939fe3c69795d532f03b551493762e242d1))

- Add per-session password salt to key exchange (breaking, P7 v1.1) ([`ccfed72`](https://github.com/nark/WiredSwift/commit/ccfed726c1f5241826fe98203605af4d113f40be))

## [3.0-beta.7+15] — 2026-03-13

### Features
- Add search_files privilege, migration, and auto-sync wired.xml ([`b962d37`](https://github.com/nark/WiredSwift/commit/b962d37f83220c7c59dc49a37a52f7d3a6abc64a))

- Add FTS5 file search index with periodic reindex and CLI flag ([`175ecfd`](https://github.com/nark/WiredSwift/commit/175ecfd3ed998b34c61578074d9990be6a3f6515))

- Add --reload flag and hot-reload config support ([`70398ef`](https://github.com/nark/WiredSwift/commit/70398ef1a9be9a2143700b5fbb5fc67be23d0be4))

## [3.0-beta.5+13] — 2026-03-13

### Documentation
- Add Linux RPM and Docker usage/build guides ([`87bea5e`](https://github.com/nark/WiredSwift/commit/87bea5efbeb030d3077751fadcf5e6a3c90b51b7))


### Features
- Add multi-stage image for wired3 runtime ([`fc5ab0d`](https://github.com/nark/WiredSwift/commit/fc5ab0d0e8d6857cbff79c8c1c210c13ea013506))

## [3.0-beta.4+12] — 2026-03-13

### Bug Fixes
- Prevent auto-install on refresh and keep uninstall effective ([`96a9daf`](https://github.com/nark/WiredSwift/commit/96a9dafa92f0c1ed59a27833c67a3f0dda7441d0))

## [3.0-beta.2+10] — 2026-03-12

### Bug Fixes
- Fallback to bundled wired3 hash when metadata hash drifts ([`d607fa1`](https://github.com/nark/WiredSwift/commit/d607fa1afbe7f752b52229544a3d569e5adb529d))

- Hash plaintext password updates and normalize SHA-256 ([`de2e99f`](https://github.com/nark/WiredSwift/commit/de2e99f0efb296983e82c380c5a06bd8328b321c))


### Features
- Auto-update bundled wired3 with hash verification and rollback ([`3550ef3`](https://github.com/nark/WiredSwift/commit/3550ef3b910f80a1c5faed8e9de384c68d5b16de))

- Migrate from Fluent/NIO to GRDB v6 ([`81d46c8`](https://github.com/nark/WiredSwift/commit/81d46c82c3c5f8ddddecf4f958f150f681a37dd0))

## [3.0-beta.1+8] — 2026-03-10

### Bug Fixes
- Prevent LLM from echoing nick: prefix in chat responses ([`a8023f7`](https://github.com/nark/WiredSwift/commit/a8023f7742462f162948f325a3bbd6f2c6c18f18))

- Add explicit CodingKeys enums to fix build error in BotConfig ([`538fecc`](https://github.com/nark/WiredSwift/commit/538fecc157eb9355bd4c5faac6b7efbb56241d0a))

- Encode nil optionals as null in generate-config output ([`7acaf70`](https://github.com/nark/WiredSwift/commit/7acaf70e0e1b5ace6d4ca8ca9d4e271943cee312))

- Don't prepend nick to LLM input for board events ([`0527ead`](https://github.com/nark/WiredSwift/commit/0527eadb07729c52ff6d658fd2d371599e565e88))

- Format llmPromptPrefix variables before LLM dispatch ([`095a353`](https://github.com/nark/WiredSwift/commit/095a353a506971c07db6292dc7b165f1019c9487))

- Add useLLM branch and debug logs in BoardEventHandler ([`b4bbd46`](https://github.com/nark/WiredSwift/commit/b4bbd461d4ce05dc5cc3ea0e9898dc2cc6a65502))

- Route wired.board.thread_changed instead of post_added ([`851d70e`](https://github.com/nark/WiredSwift/commit/851d70e0590afd906573cd338810dbbda388c97c))

- Subscribe to board broadcasts after login ([`8da6e5f`](https://github.com/nark/WiredSwift/commit/8da6e5fddc0176297e19c026a89d6e5dff5caa2e))

- Import FoundationNetworking in all LLM providers ([`ce14369`](https://github.com/nark/WiredSwift/commit/ce14369aaf27058c6f2048ddd4bacb876cce1dd3))


### Documentation
- Update README with respondToConversation and respondInUserLanguage ([`e4ab71e`](https://github.com/nark/WiredSwift/commit/e4ab71e3ed8a06a6a2ab2699c124e174778cf370))


### Features
- Configurable identity preamble via identity.identityPreamble ([`872dd41`](https://github.com/nark/WiredSwift/commit/872dd412fd8ab1085efb0dc91808485dd2a5e57e))

- Structured identity preamble in system prompt (self-awareness) ([`04dbe7f`](https://github.com/nark/WiredSwift/commit/04dbe7fdd20e791bbf1add6da425bf804ae1965a))

- Respond naturally after bot-initiated messages (respondAfterBotPost) ([`30cc00f`](https://github.com/nark/WiredSwift/commit/30cc00fb843add439ec7a7fdbb5ca13dadb33c82))

- Inject board threads into channel context for follow-up chat ([`94feed2`](https://github.com/nark/WiredSwift/commit/94feed20a219f3c7e77adb7d25762512558332dd))

- Replace announceNewThreads with trigger-based board events ([`92e8449`](https://github.com/nark/WiredSwift/commit/92e8449d18e6a99ff36cfb8eaa9628e35fce4314))

- Add board_post trigger support with example ([`b24321d`](https://github.com/nark/WiredSwift/commit/b24321d3273b86aac909085716d4cebdd763d4a4))

- Add respondToConversation — follow active conversations ([`f09a7be`](https://github.com/nark/WiredSwift/commit/f09a7bec7161bd829de5ea002beb4f64e588363d))

- Bootstrap default Upload/DropBox and Welcome board content ([`1c4deeb`](https://github.com/nark/WiredSwift/commit/1c4deebd3022e984ac7158fd8401998696392e1b))

## [3.0+5] — 2026-03-07

### Documentation
- Adopt unified 3.0+N versioning across targets ([`fec893f`](https://github.com/nark/WiredSwift/commit/fec893fb1e59bd7e8092b796b4381b9a30e527c4))

## [3.0+999] — 2026-03-06

### Documentation
- Rewrite onboarding and clarify library/server version tags ([`88cf8be`](https://github.com/nark/WiredSwift/commit/88cf8bede716cc5dcc15e7a7a23491f3c9d53969))

## [3.0+4] — 2026-03-06

