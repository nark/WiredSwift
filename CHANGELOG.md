# Changelog

All notable changes to WiredSwift are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
## [3.0-beta.24+50] — 2026-05-05

### Features
- Chat reactions and server-stamped message IDs (Wired 3.2) ([`786893c`](https://github.com/nark/WiredSwift/commit/786893c8261962331adf20f49ea5e2f856c611d2))

- Backward/forward compatibility between minor versions ([`411273d`](https://github.com/nark/WiredSwift/commit/411273d3f13d96414cbd92cadde9a623aa15b4a6))


### Other
- Revert "Merge pull request #91 from nark/feature/issue-90-chat-reactions" ([`2b0aeba`](https://github.com/nark/WiredSwift/commit/2b0aeba9a3ef91b7ffeb0da02822c478860ebbe9))


### Testing
- Bump expected handshake remoteVersion to 3.2 ([`05727ef`](https://github.com/nark/WiredSwift/commit/05727efa260409845ddd8fb4134cd7de8e3f2322))

## [3.0-beta.23+49] — 2026-05-05

### Bug Fixes
- Stop main-thread hang in appendLog during server startup ([`09a1acc`](https://github.com/nark/WiredSwift/commit/09a1accc2e680b8a3b96a1710bb66273491dd377))

- Hide macOS Icon\r sidecar from directory listings ([`42ba97c`](https://github.com/nark/WiredSwift/commit/42ba97c8ff0b5cce101136df27fce9384b3a1c3b))

- Declare wired.account.user.list_offline_users field ([`5f2e4e4`](https://github.com/nark/WiredSwift/commit/5f2e4e42782a3196c972cfc66303b38602b33651))

- Return permission_denied for unknown recipient ([`a02c9fe`](https://github.com/nark/WiredSwift/commit/a02c9feee430f25c346d05954abd09a401622cdd))

- Restrict list_offline_users migration to admin accounts only ([`568e35c`](https://github.com/nark/WiredSwift/commit/568e35c9fefde6420fc585dbdcb94542cab385fc))

- Walk up from executable to find resource bundle in tests ([`223317e`](https://github.com/nark/WiredSwift/commit/223317e3b4f396bca14fd5ba154436d473f7d3d5))

- Use bundleURL not deletingLastPathComponent for xctest discovery ([`af62836`](https://github.com/nark/WiredSwift/commit/af628369afbb71fc695cb5dd8f86a097e7df4501))

- Add Bundle(for:) candidate to fix test bundle discovery on CI ([`2ce4f4f`](https://github.com/nark/WiredSwift/commit/2ce4f4f6c0ac4d5f026153eb9ebe6d373616a68e))

- Restore wired.xml discovery for macOS and Linux SPM tests ([`15bd982`](https://github.com/nark/WiredSwift/commit/15bd982d34726bd64ee8982562d558c6215873d1))

- Use wired.message.offline.recipient_login instead of wired.user.login ([`d13bf47`](https://github.com/nark/WiredSwift/commit/d13bf474323b90b9e430ee5e1663eca94e3532a4))

- Add wired.account.user.list_offline_users privilege ([`d416f9b`](https://github.com/nark/WiredSwift/commit/d416f9b260507b79a2ae58d50a8745bf0ec12e8a))

- Address Nark's security review findings ([`eba3460`](https://github.com/nark/WiredSwift/commit/eba346068d327358abb05d545d994ac2fa6f1de2))

- Set is_legacy=1 in Python migration script ([`f24c32e`](https://github.com/nark/WiredSwift/commit/f24c32e0603f9946e954bc019e00236f87758280))

- Require E2E encryption unconditionally ([`6aa1ed5`](https://github.com/nark/WiredSwift/commit/6aa1ed5073fa80e1b094495310b62b78be03488c))

- Avoid Bundle.module crash when SPM resource bundle is missing ([`995bee3`](https://github.com/nark/WiredSwift/commit/995bee368e21fa0bce61437091508d7a2467ed4a))

- Use GRDB native Date decoding for sent_at column ([`79151a3`](https://github.com/nark/WiredSwift/commit/79151a3bfa13ba04cf280a0edf690242d66deb82))

- Only show last_nick in offline list, never login or full_name ([`845f410`](https://github.com/nark/WiredSwift/commit/845f41086d74330df772fd55a94e826c144d85de))

- Exclude never-logged-in accounts from offline user list ([`43b8028`](https://github.com/nark/WiredSwift/commit/43b80287ac05c9c6896e6f6e3e72ffdc5b261f4a))

- Always drop index_ad trigger before bulk delete ([`bb93e63`](https://github.com/nark/WiredSwift/commit/bb93e635c51f5499311a41e5314dac333ee70321))

- Allow pre-release suffixes in WIRED_MARKETING_VERSION ([`c20a8b3`](https://github.com/nark/WiredSwift/commit/c20a8b331e1c04ccc21a6c36193c6b3291e95ef2))

- Checkpoint WAL on startup and add FTS5 integrity probe ([`ddf444d`](https://github.com/nark/WiredSwift/commit/ddf444dd3071f2f285925a1dd1c88479d458bf24))

- Avoid SQLITE_IOERR on FTS5 cleanup after crash restart ([`8b63515`](https://github.com/nark/WiredSwift/commit/8b635152a95c059454faec246c6f5d76f06ec1dd))

- Report actual CPU architecture instead of hardcoded x86_64 ([`2cd615e`](https://github.com/nark/WiredSwift/commit/2cd615e68a7b0cd5ff4e6f8accf2a766aa426e90))

- Handle .idle case in PortStatus color switch ([`537fa73`](https://github.com/nark/WiredSwift/commit/537fa738703a558299e66b3e45f17f7a8513fa00))

- Restore wired.xml discovery for macOS and Linux SPM tests ([`6afaa5b`](https://github.com/nark/WiredSwift/commit/6afaa5b1fea0985c061241f2a4adcad46c0c675a))

- Avoid Bundle.module crash when SPM resource bundle is missing ([`15bde0f`](https://github.com/nark/WiredSwift/commit/15bde0f30977b1501cfaee349bcf8a1f5c980479))

- Align consent dialog keys with main, add idle port status ([`74edb99`](https://github.com/nark/WiredSwift/commit/74edb994582655f43616646b0dfa6644037d569a))

- Clear newAdminPassword after use in all paths ([`bc04f0b`](https://github.com/nark/WiredSwift/commit/bc04f0b666e794443f120818186559f0d6c973ec))

- Fix port TextField resetting to '4' while typing ([`2fb07cb`](https://github.com/nark/WiredSwift/commit/2fb07cb3074982baadc6c58bdaffdbaf401fa7dd))

- Remove persistent consent — port check asks every time, no auto-check ([`e7f4f16`](https://github.com/nark/WiredSwift/commit/e7f4f16bcc3fbd0bb16ba76ade1d7696c5e48c8a))

- Replace check-host.net with EU-hosted portchecker.co, add opt-in consent ([`6f54c88`](https://github.com/nark/WiredSwift/commit/6f54c889d0b902397e6430d7cb2eee05ed431ecb))

- Strip LaunchDaemon/TouchID code from Tabs.swift not in upstream ([`b6fa1ae`](https://github.com/nark/WiredSwift/commit/b6fa1aea2bceb2149fa4abafc2a7d734ca7a7569))

- Make admin password field visible with roundedBorder style ([`b44297d`](https://github.com/nark/WiredSwift/commit/b44297d83c015bf1c70422ec5a184764f62bbf65))

- Use local @State buffer for admin password field ([`940902c`](https://github.com/nark/WiredSwift/commit/940902c1f0d67da3ed7141f963952d14e5052de0))

- Use Locale.preferredLanguages only for language resolution ([`9726178`](https://github.com/nark/WiredSwift/commit/97261781c854ce43372ebaf9ffd8e666f3afc025))

- Use Bundle.module to find localized strings ([`61e190f`](https://github.com/nark/WiredSwift/commit/61e190ffc9b4e1f4a97f234dad3c240599b510b3))

- Use 3 probe nodes for external port check reliability ([`808ba62`](https://github.com/nark/WiredSwift/commit/808ba62064df5fbf4b289a0f2b11e45e0afb33fa))

- Address review feedback on migration robustness ([`3af6210`](https://github.com/nark/WiredSwift/commit/3af62104a42fe13c7dbf5630952d5564b8c5a9cd))

- Don't assign password salt during legacy login ([`b0bc197`](https://github.com/nark/WiredSwift/commit/b0bc197ece171383912f56ddcbe397ec1c7a1682))

- Avoid SQLITE_IOERR on FTS5 cleanup after crash restart ([`2e3a9ac`](https://github.com/nark/WiredSwift/commit/2e3a9acb49e02136e8563a3da3136a106c8ff7d3))


### Documentation
- Update README offline messaging docs ([`2f81483`](https://github.com/nark/WiredSwift/commit/2f8148336f1bf1b6048330270578a497301853a2))

- Note that Wired 3.0 is not compatible with Wired 2.x clients ([`e77e7f6`](https://github.com/nark/WiredSwift/commit/e77e7f69d43d15ca8050729becf7e7da54dbfc32))


### Features
- Broadcast offline_list updates on disconnect and on privilege grant ([`84b06f0`](https://github.com/nark/WiredSwift/commit/84b06f081f6f5221075e96e1b0bad1bee18f0a9a))

- End-to-end encrypted offline messages via X25519+ChaCha20-Poly1305 ([`8c0096b`](https://github.com/nark/WiredSwift/commit/8c0096b62bd711269913a68046c092016f9fc78e))

- Include sender nick in offline message delivery ([`ea17072`](https://github.com/nark/WiredSwift/commit/ea17072ad83a6f9bb622976eff77348233f4cb14))

- Persist last_nick and use it in offline user list ([`1a4dfcb`](https://github.com/nark/WiredSwift/commit/1a4dfcb7832971cf7c5bfa43913ea034da4494b9))

- Fix click handling, 30-day filter, full name, privilege backfill ([`5093249`](https://github.com/nark/WiredSwift/commit/50932495c9fd1147bd637f3267ffa851b732ea4c))

- Implement server-side offline messaging and offline user list ([`0d8713a`](https://github.com/nark/WiredSwift/commit/0d8713afb153b5bf6380b422ebab24ee9067a2ca))

- Warn when files directory is under /Users/ in daemon mode ([`1195dc6`](https://github.com/nark/WiredSwift/commit/1195dc64b0cc4214e017e8b83779cdee934b0781))

- Add German localization support ([`6323528`](https://github.com/nark/WiredSwift/commit/632352832008550eaf323a79344d0055f341ee80))

- External port reachability check + Network tab UI ([`a195460`](https://github.com/nark/WiredSwift/commit/a195460a9e86211d718b404f69d5a54d3645bf70))

- Replace brittle SHA1-detection heuristic with is_legacy DB column ([`6106eeb`](https://github.com/nark/WiredSwift/commit/6106eebae49d26916e81ff5caf556b2cae71d0d1))

- Support legacy SHA1 passwords from Wired 2.5 migration ([`4d599c7`](https://github.com/nark/WiredSwift/commit/4d599c710f7663acf712c89ec5855573a02dfa93))

- Add Wired 2.5 → Wired 3 database migration ([`1791aa6`](https://github.com/nark/WiredSwift/commit/1791aa66d85dd2737ed6ce72d2a54db9980849ce))


### Other
- Retry notarization on transient network errors ([`537b249`](https://github.com/nark/WiredSwift/commit/537b249b55458cdc9a608e8543de3ba6372759b8))

- Use bash in Docker runtime stage ([`eebcf94`](https://github.com/nark/WiredSwift/commit/eebcf947c51a478773293adee743d8b72788b853))

- Make Docker apt mirror configurable ([`44ec664`](https://github.com/nark/WiredSwift/commit/44ec6645fea0132315f79abed88d75133ffa00bb))


### Testing
- Resolve wired.xml from #filePath instead of Bundle.module ([`6fd836c`](https://github.com/nark/WiredSwift/commit/6fd836c6b80aca4b7302acef09193544d0920e3d))

## [3.0-beta.22+42] — 2026-04-20

### Bug Fixes
- Minor ajustments ([`e53ee9e`](https://github.com/nark/WiredSwift/commit/e53ee9e6c8c92a5e81a1bf2bd1536f7e2f65babb))


### Documentation
- Rename WiredBot changelog references ([`0982bfa`](https://github.com/nark/WiredSwift/commit/0982bfabd5d58d785b12c0adcd97006ac5c7e1dc))


### Refactoring
- Move WiredChatBot in separated repo ([`6166223`](https://github.com/nark/WiredSwift/commit/6166223b5feaef77d760884d4c0718ee73216d1f))

## [3.0-beta.21+38] — 2026-04-13

### Bug Fixes
- Fix WiredServerApp lint violations ([`198b849`](https://github.com/nark/WiredSwift/commit/198b849385530a0a8a23d5b8a4abb365b37c76db))


### Features
- Persist tracker registry and watch external changes ([`fc4c602`](https://github.com/nark/WiredSwift/commit/fc4c602c7459d4703f8d92e60ff576b4f2e8a01f))

- Add dashboard overview to WiredServerApp ([`a57e9d2`](https://github.com/nark/WiredSwift/commit/a57e9d2ebe29b206074d8b3ae7b6c01427aa5f03))

- Add database settings UI and auto event retention reload ([`4c5388d`](https://github.com/nark/WiredSwift/commit/4c5388d08af46ee38e70d6ae53d6e18d1b0ff72a))

- Implement file executable handling ([`d051a1c`](https://github.com/nark/WiredSwift/commit/d051a1c464b5f0932e7e0a5f96ba46ba6bd1363a))

- Add wired.file.link support on the server ([`56eb59d`](https://github.com/nark/WiredSwift/commit/56eb59d71d6fc9bee88af8640361ab23375a5b82))


### Other
- Document attachment behavior and quotas in README ([`62adcdf`](https://github.com/nark/WiredSwift/commit/62adcdf8a70e72e173413287818cd38d22c42af2))

- Mirror modern Finder color tags on macOS ([`23d7cd2`](https://github.com/nark/WiredSwift/commit/23d7cd2c33974c796add2ec89032d86704cda8be))


### Refactoring
- Split FilesController metadata helpers ([`db3e3f8`](https://github.com/nark/WiredSwift/commit/db3e3f811e538aae8033195cb072aa5a84532ce2))

## [3.0-beta.20+37] — 2026-04-11

### Bug Fixes
- Fix IndexController build error after wiredFileLabel removal ([`43536de`](https://github.com/nark/WiredSwift/commit/43536def46980f588b7bb83f4c1599c81208c5a0))

- Fix Finder label color mapping and reliable xattr update ([`359c32b`](https://github.com/nark/WiredSwift/commit/359c32b9d76c40e9ec02f95edca46be561ef2c3b))

- Fix attachment controller lint issues ([`827fc09`](https://github.com/nark/WiredSwift/commit/827fc09bcca649d0183b6548e2f27c5256a0fd57))

- Fix board post attachment edit broadcasts ([`2f409cc`](https://github.com/nark/WiredSwift/commit/2f409cc5b1ab36a7f2b5c217bda066581abfa346))


### Features
- Add file comment and label metadata support ([`02ce2fa`](https://github.com/nark/WiredSwift/commit/02ce2fac0352352b3b2bb6081f095cc2bd042f19))

- Add English translation of Wired 2/3 feature comparison document ([`7f2fc16`](https://github.com/nark/WiredSwift/commit/7f2fc16cac94156aceeb7729261738b380e5e46d))

- Persist private message attachments across reconnects ([`69dc1c4`](https://github.com/nark/WiredSwift/commit/69dc1c473053a39af86ae27d79b14324faa485e8))

- Add generic message attachments ([`3d7c046`](https://github.com/nark/WiredSwift/commit/3d7c046464a6b47df5bb18a7ce12efb950b7cc42))

- Align managed directory counts with classic Wired behavior ([`1cc7259`](https://github.com/nark/WiredSwift/commit/1cc72596a97374fc53419868ec489b1d52c4d6f8))


### Refactoring
- Reduce FilesController below 1200-line SwiftLint limit ([`a8cb0c1`](https://github.com/nark/WiredSwift/commit/a8cb0c1a16c3eba255f9d418ebf5f55c9e1ffbf4))

- Inline Finder label mapping to stay under 1200-line SwiftLint limit ([`08547d7`](https://github.com/nark/WiredSwift/commit/08547d77b8839a38af1ad8c674bb893f957aebb9))

- Replace absolute paths with relative paths in feature comparison doc ([`1f71144`](https://github.com/nark/WiredSwift/commit/1f7114497fb6df230b36e019fb25073169a56a99))


### Testing
- Double server startup timeout in integration tests (10s → 20s) ([`79ca7be`](https://github.com/nark/WiredSwift/commit/79ca7be2d8baeaaa83fb72f91e110b139b3e1811))

## [3.0-beta.19+36] — 2026-04-08

### Bug Fixes
- Fix Debian config write permissions ([`8810d66`](https://github.com/nark/WiredSwift/commit/8810d668f8de4e4b2e0a20d5b07d0321b7b83626))


### Documentation
- Update README ([`8220900`](https://github.com/nark/WiredSwift/commit/8220900c7d287b7863cd1971b38942837395e133))

- Update README ([`debb760`](https://github.com/nark/WiredSwift/commit/debb7609babaff3c441cafa4af92438e43fcd3c5))


### Features
- Add remote file preview support ([`9228526`](https://github.com/nark/WiredSwift/commit/9228526f5fafd448a4a254fce66ab29ea64a7c56))

## [3.0-beta.18+35] — 2026-04-06

### Bug Fixes
- Fix remaining swiftlint blockers ([`b1d9d54`](https://github.com/nark/WiredSwift/commit/b1d9d54ee825fca9bdd3d0d94d7fe37f85192c3f))

- Fix symlink path resolution and transfer queue hangs ([`64cbb48`](https://github.com/nark/WiredSwift/commit/64cbb482b6165ebafa13a40b7517d837de95e466))

- Fix idle status in user join broadcast ([`cd5e974`](https://github.com/nark/WiredSwift/commit/cd5e9747e5f4efb89766667f5a861ddc368bd2cd))


### Documentation
- Update README to remove --root option from commands ([`d0f0e84`](https://github.com/nark/WiredSwift/commit/d0f0e847f5f63d99734a0327484c9d4bd3e37d67))


### Features
- Add outgoing tracker registration ([`16b79e8`](https://github.com/nark/WiredSwift/commit/16b79e8c08defaf793d8d32264af0d43b0fe3a17))

- Implement incoming tracker server support ([`9be9d06`](https://github.com/nark/WiredSwift/commit/9be9d06094b58fc1b4111fbf3681409eba103242))

- Implement monitor user listing ([`8dcddf4`](https://github.com/nark/WiredSwift/commit/8dcddf475e1b2d2bb3103715d4b110221822ff64))

- Add active transfer status to user info ([`486bef7`](https://github.com/nark/WiredSwift/commit/486bef79d9ccb674569aaa8883c101072e500862))


### Other
- Suppress transfer controller type length lint ([`ec3644e`](https://github.com/nark/WiredSwift/commit/ec3644efd41386f8eb422cfc8e9106d405ec8ae6))

- Match legacy idle behavior on server ([`d769a4b`](https://github.com/nark/WiredSwift/commit/d769a4b3025b1ae30a58ea0fbef5ab5759dafa0e))

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

- Stabilize integration tests with distinct admin sessions ([`54b1faf`](https://github.com/nark/WiredSwift/commit/54b1fafce27da84b56b5d7a05f781fd0424b3d0b))

- Fix integration flake: idempotent disconnect and stronger CI diagnostics ([`160abe3`](https://github.com/nark/WiredSwift/commit/160abe34fcf3817c20d7079c143142c307a88d68))

- Stabilize integration socket reads against transient timeouts ([`fcba51d`](https://github.com/nark/WiredSwift/commit/fcba51d858f524c1baea750357d169db5c56b1ec))

- Fix WiredServerApp actor-safe self captures ([`646ec2a`](https://github.com/nark/WiredSwift/commit/646ec2ad6e20226825a6eeff839ff9a411932f45))

- Fix upload message initialization in TransfersController ([`730575a`](https://github.com/nark/WiredSwift/commit/730575a7a005bbbc04168e73a905762f49098328))


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
- Add sync concurrency integration tests ([`b906365`](https://github.com/nark/WiredSwift/commit/b90636594497ffdf28488cf4efacb41477642e3c))

- Align client identity metadata across targets ([`901c5e6`](https://github.com/nark/WiredSwift/commit/901c5e69e44ea98b184ed350ad5b2c9e6768e3c6))

- Implement quota fields — max_file_size_bytes, max_tree_size_bytes, exclude_patterns ([`361a214`](https://github.com/nark/WiredSwift/commit/361a214b1421c083b65adacf8048ffd5fcf8e047))

- Implement sync folder permissions and admin sync management fixes ([`ace9b1c`](https://github.com/nark/WiredSwift/commit/ace9b1caf5e143c5e870d0e6b4334601ccf4a3cc))

- Add sync folder type with server invariants, ACL, and upload conflict handling ([`4749c99`](https://github.com/nark/WiredSwift/commit/4749c9940f1c5ed1182217a590cc028ede618733))

- Add SwiftLint 0.63 with zero-error baseline ([`ccd160d`](https://github.com/nark/WiredSwift/commit/ccd160daa46415079025007240e97392dc70f476))

- Add coverage-driven unit tests for events, spec metadata, and resource fork helpers ([`4a400aa`](https://github.com/nark/WiredSwift/commit/4a400aa355c62cc30a11c15d767427230005d394))

- Add integration test suite and GitHub Actions CI pipeline ([`1607c18`](https://github.com/nark/WiredSwift/commit/1607c18d3ff967eb91f53c869987c521d9cb0560))


### Other
- Document continuous folder sync ([`f60ebca`](https://github.com/nark/WiredSwift/commit/f60ebca9eb57cabb41c4f2a6311524e7f0535e20))

- Handle wired send ping on server ([`9f3f657`](https://github.com/nark/WiredSwift/commit/9f3f6578baa18c9695a2ebcaba611792e5ca6f6f))

- Finish async ping transactions ([`44b6aeb`](https://github.com/nark/WiredSwift/commit/44b6aeb8420cdf7f22fa32308b8c183f39e48d42))

- Refresh connection activity on incoming messages ([`2a33e78`](https://github.com/nark/WiredSwift/commit/2a33e78961426fe89e5abd8356bf403bb3149f5b))

- Refine sync policy and server sync uploads ([`fea96a0`](https://github.com/nark/WiredSwift/commit/fea96a07470ec9394215660cdb4ed8280997f795))

- Add git-cliff CHANGELOG.md to the repository ([`f1e8237`](https://github.com/nark/WiredSwift/commit/f1e82378e120a2b85150432b3c9428b6d65023f6))

- Expand boards/transfers unit coverage and harden flaky chat integration test ([`8af8ac1`](https://github.com/nark/WiredSwift/commit/8af8ac133ef374af86af092b5d8adacbc4aeb926))

- Expand integration coverage for boards files messages and transfers ([`c7141e2`](https://github.com/nark/WiredSwift/commit/c7141e2891a022690a88c22121444a6f6f0f798a))

- Expand wired3 unit coverage for users and banlist controllers ([`caa22bb`](https://github.com/nark/WiredSwift/commit/caa22bbed51c09be464cb932785d8b1a196952e4))

- Use static BSD license badge ([`45e372f`](https://github.com/nark/WiredSwift/commit/45e372fc9930dfc0a88b097ca85731fac2d8b031))

- Add CI, platform, version, license, and coverage badges ([`1431e03`](https://github.com/nark/WiredSwift/commit/1431e0353c4c79f55e7b23ba620081eedd7f6d35))

- Fix llvm-cov test binary detection and make summary non-blocking ([`b45a578`](https://github.com/nark/WiredSwift/commit/b45a5780e85167696f153c7e63467e7d020e400c))

- Publish llvm-cov coverage summary in job output ([`4da4861`](https://github.com/nark/WiredSwift/commit/4da486133ebd609024cefcd0b2ada0f268cf7246))

- Harden chat integration test against nil chat ID ([`46680d5`](https://github.com/nark/WiredSwift/commit/46680d5811882c66a657ba139db96b084342c367))

- Expand integration coverage for groups, banlist listing, events, and file change notifications ([`df53991`](https://github.com/nark/WiredSwift/commit/df5399132bdf10a0ab0b07776f50fb3de683403f))

- Expand integration coverage, enable CI code coverage, and harden event broadcast teardown ([`1ba4d41`](https://github.com/nark/WiredSwift/commit/1ba4d4113e9992cb2172e8876118ba7e6ec93120))

- Expand integration coverage for auth/subscriptions/accounts and harden event teardown ([`c80db93`](https://github.com/nark/WiredSwift/commit/c80db93bd1fe24d100747061345eba0b94719ce9))

- Remove unsupported no-parallel and upload test diagnostics ([`01f0869`](https://github.com/nark/WiredSwift/commit/01f0869c96b56e21ac88caabaaa8400140d6c93a))

- Simplify test execution to single swift test run ([`2efaab6`](https://github.com/nark/WiredSwift/commit/2efaab602628649b42efd827f960bacb62880d2d))

- Run tests sequentially by suite to reduce integration flakes ([`d7c962c`](https://github.com/nark/WiredSwift/commit/d7c962ce9c5d363d0fd57571456945b515f2d58f))

- Guard disconnect path against App teardown in integration runs ([`d1ba7a0`](https://github.com/nark/WiredSwift/commit/d1ba7a0c76804077f31f4ee31e2aaf1a3cd27083))

- Avoid building WiredServerApp in default workflow ([`8705f10`](https://github.com/nark/WiredSwift/commit/8705f10cd8a598e378564e1669e562ffa4e2928c))


### Refactoring
- Split sync reservation helpers from transfers controller ([`fb5adf9`](https://github.com/nark/WiredSwift/commit/fb5adf91c53de7d26740d773936949972505705a))

- Unify wired protocol spec ([`9e95dfb`](https://github.com/nark/WiredSwift/commit/9e95dfb967ce813dc8551a4041200c803720369a))

- Split ServerController into domain-specific extensions ([`c2e84f5`](https://github.com/nark/WiredSwift/commit/c2e84f5ea9ecdb7ca766a3382eeee1b9d7ed09c7))

- Reorganize sources into Core/, Models/, Controllers/, Database/ ([`914ddb9`](https://github.com/nark/WiredSwift/commit/914ddb9a90f39fee492fe4dc90885acefe503e75))

- Improve coverage with focused core and domain model tests ([`f341597`](https://github.com/nark/WiredSwift/commit/f34159771c536feeaad4c4dcae6b862b9a076093))

- Reduce chat integration race by delaying second client login ([`c83abce`](https://github.com/nark/WiredSwift/commit/c83abce510edc2b4452d963067b8563115a08a62))

- Reduce integration teardown races by disabling auto cleanup ([`17a6f0e`](https://github.com/nark/WiredSwift/commit/17a6f0e413a2237699b50f11a2d52d5aaf188663))


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


### Other
- Update issue templates ([`b2ff405`](https://github.com/nark/WiredSwift/commit/b2ff405b64b2680f9f306119180cd0f1fb1918a8))

## [3.0-beta.12+24] — 2026-03-23

### Documentation
- Split Wired 3.0 into features and security ([`8a8413a`](https://github.com/nark/WiredSwift/commit/8a8413a4841e6f0397dee433d1ea8101753e5596))


### Features
- Add chat typing indicator support ([`e18bf0e`](https://github.com/nark/WiredSwift/commit/e18bf0e912464acf5ce827062d02c74d60f48d2f))

- Add prefix matching to board and file search ([`a9ff661`](https://github.com/nark/WiredSwift/commit/a9ff6615f17451a0f68a71de1c725b923e69c4ba))

## [3.0-beta.11+23] — 2026-03-20

### Features
- Implement server-side events and exhaustive event logging ([`ff4454a`](https://github.com/nark/WiredSwift/commit/ff4454ac8683cdf9e0bc6dfc8b3b62d53bc85a3a))

- Add moderation actions and persistent ban list ([`7e467b4`](https://github.com/nark/WiredSwift/commit/7e467b424ba9e2a54b647a0ec9e65e070b47d406))

- Add server-side board search protocol support ([`c47d594`](https://github.com/nark/WiredSwift/commit/c47d594daeae03f24c4c0d91017f3a0526663a3f))

## [3.0-beta.10+22] — 2026-03-19

### Bug Fixes
- Persist and reload strict identity toggle ([`e161366`](https://github.com/nark/WiredSwift/commit/e1613666552080a051266d341a8f45513c36f466))

- Preserve strict_identity in generated configs ([`59a8ecc`](https://github.com/nark/WiredSwift/commit/59a8eccf2bc6b4b2aff31dfae354fd8dc760a684))

- Fix chat synchronization and ID handling ([`a98eae8`](https://github.com/nark/WiredSwift/commit/a98eae8ed21635a181ddae10c8aa1e6fb6d6d1a6))

## [3.0-beta.9+21] — 2026-03-18

### Bug Fixes
- Fix board bootstrap seeding and global thread loading ([`ac03be1`](https://github.com/nark/WiredSwift/commit/ac03be1443df06daac7fdef8fd675d6102570055))

- Fix public chat create/delete to reply wired.okay per spec ([`b0a291a`](https://github.com/nark/WiredSwift/commit/b0a291ab4584b15bbdc4d701031000f9d0f02f82))

- Include stored password hash in read_user response ([`3d09753`](https://github.com/nark/WiredSwift/commit/3d097539034b27149099377d35f823cd6dcf006f))

- Don't regenerate salt on permissions-only account edits ([`afe1286`](https://github.com/nark/WiredSwift/commit/afe128688bffdbef93bc49c52dd2752cebafeac5))

- Guest login fails after permission edit (double-salted password bug) ([`f48bef1`](https://github.com/nark/WiredSwift/commit/f48bef18449a6f071c23c43b90b0b535d466a152))


### Features
- Add restart prompt after binary update and initial admin password alert ([`ef065e2`](https://github.com/nark/WiredSwift/commit/ef065e228fe4aad8d6c01d1ba207d26cd91ab3ea))

- Implement wired.account.change_password on server ([`b3400ec`](https://github.com/nark/WiredSwift/commit/b3400ec49706565bf3ef2c9b81e9c8f023ae7c52))


### Other
- Added german language ([`a629e8e`](https://github.com/nark/WiredSwift/commit/a629e8e5104684f7ab6d89fa8e12a43936ab6bcc))

- Update audit progress ([`1a7dc7f`](https://github.com/nark/WiredSwift/commit/1a7dc7fae16cfcfce3e2c2eb6246fd461f737aa5))


### Refactoring
- Rewrite README with user-friendly structure, security comparison, and protocol overview ([`b414848`](https://github.com/nark/WiredSwift/commit/b4148484b1ef778b1c408bf1f533a4e1638cc5be))

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


### Other
- Fix A_015 regression — reject NONE cipher clients with clear error instead of silent fallback ([`1664c40`](https://github.com/nark/WiredSwift/commit/1664c405f698cb7d32b6da7875565466199f11b2))

- Fix FINDING_A_004 — salted SHA-256 for password storage ([`8732836`](https://github.com/nark/WiredSwift/commit/873283677bc252536a76ea2e559b1e40100fed43))

- Fix FINDING_A_014 — use dummy password on unknown user in key exchange ([`fcdf0d4`](https://github.com/nark/WiredSwift/commit/fcdf0d4d575e968c27ab244b3605477e4887488e))

- Fix FINDING_A_014 — prevent username enumeration via timing ([`374f887`](https://github.com/nark/WiredSwift/commit/374f88719f6d0c232248bd2c553226571b585a1f))

- Fix FINDING_Z_003 — enforce handshake read deadline to prevent thread-pool exhaustion ([`76c8182`](https://github.com/nark/WiredSwift/commit/76c8182f598a3d5b5d494ea73b8e9b6eb6a78370))

- Update audit metadata for A_010, C_007, C_011, F_008, F_017, P_019, A_014, C_014, F_016 ([`76130e5`](https://github.com/nark/WiredSwift/commit/76130e5e799dc54395a8fba1adcb10f7c36011fc))

- Fix A_010/C_011/F_008, C_007, F_017, P_019 ([`6018a6e`](https://github.com/nark/WiredSwift/commit/6018a6ec791812eb1a1c3b6447ab5242cbf613c3))

- Update audit metadata for A_006, A_009, A_012, A_013 ([`dd485ac`](https://github.com/nark/WiredSwift/commit/dd485ac9ba522910d1d2bc059cc68eecb59e23fb))

- Fix FINDING_A_006 — protect nextUserID() with NSLock ([`38b848b`](https://github.com/nark/WiredSwift/commit/38b848b1ee031fc4b9074c295bc8c76ef3e31eb9))

- Fix FINDING_P_017 — return nil for unknown P7 spec types ([`80ee91a`](https://github.com/nark/WiredSwift/commit/80ee91a11a1623fdb04d8ed182a6fcccb885ccb0))

- Fix FINDING_P_010 and FINDING_P_015 — safe unwrap in P7Spec ([`14d8649`](https://github.com/nark/WiredSwift/commit/14d86492402dca72840369973cfeb548b40e041d))

- Fix FINDING_P_008 — recompute length header after compression in writeOOB() ([`ec43e07`](https://github.com/nark/WiredSwift/commit/ec43e0711af3359b9bd854033a1dd10fd762ae3a))

- Fix FINDING_C_012 — broadcast rate limiting (5/min per user) ([`9a26632`](https://github.com/nark/WiredSwift/commit/9a26632932db1c4cbaa72a55ee6ef1da453c78e1))

- Fix FINDING_C_002, FINDING_C_006, FINDING_C_013 — chat input validation and rate limiting ([`a7a20cc`](https://github.com/nark/WiredSwift/commit/a7a20cc8ae8c023712731703cd440825b17bc13e))

- Fix FINDING_P_011 — replace force unwraps with nil-coalescing in logging ([`dbb02f2`](https://github.com/nark/WiredSwift/commit/dbb02f21fcf29408fda1bd530c40212e121ed1a5))

- Fix FINDING_P_009 — log warning when P7Message name not found in spec ([`1bd4fd6`](https://github.com/nark/WiredSwift/commit/1bd4fd65e7111450fb12b00695f83d05cc2d1437))

- Fix FINDING_F_014 — reorder deletePublicChat to DB-delete-first ([`2c4bd41`](https://github.com/nark/WiredSwift/commit/2c4bd41fa97175149f022de5f4c9ae30d731a240))

- Fix FINDING_F_012 — add maxDepth and maxEntries limits to recursive directory listing ([`83f43dc`](https://github.com/nark/WiredSwift/commit/83f43dc7a7b0716deed0423dae42c9aef4be66e5))

- Fix FINDING_F_010, FINDING_F_011 — directory permissions and dropbox check ([`eb8192e`](https://github.com/nark/WiredSwift/commit/eb8192e2f76d051afb4ae57eb45fcddd7e413c07))

- Fix FINDING_F_009 — bounds check in FilePrivilege.init?(path:) ([`ae5ea85`](https://github.com/nark/WiredSwift/commit/ae5ea850e4ba98ce35d3489ae3af545b15618ed4))

- Fix FINDING_A_015 — reject NONE cipher to prevent plaintext credentials ([`e4651c7`](https://github.com/nark/WiredSwift/commit/e4651c70ff5acf7e0d37f90b4cfcf70f11cc84ad))

- Fix FINDING_C_010 — add per-recipient offline message limit trigger to legacy migration ([`b569d8b`](https://github.com/nark/WiredSwift/commit/b569d8bb0392bdab54661ad9803d4261f580a0a3))

- Fix FINDING_P_013 — implement receiveCompatibilityCheck() validation ([`25be9df`](https://github.com/nark/WiredSwift/commit/25be9df3229128734636e9fad01cde556207a3dc))

- Fix FINDING_P_012 — implement version validation in isCompatibleWithProtocol() ([`37732a0`](https://github.com/nark/WiredSwift/commit/37732a0a6d01abb6c86b9c5f3f29f721a849aa2d))

- Fix FINDING_C_008 FINDING_C_009 — private chat limits and nextChatID race condition ([`01b62ca`](https://github.com/nark/WiredSwift/commit/01b62cad763c6f1ba9350d5833d9d6732177fc43))

- Fix FINDING_A_005 — replace hardcoded admin password with random generation ([`ca09f77`](https://github.com/nark/WiredSwift/commit/ca09f7779047ec977d85a516f86a3e44ff150abe))

- Fix FINDING_F_015 — filter search results inside dropboxes ([`7befced`](https://github.com/nark/WiredSwift/commit/7befcedd5597b0d25fa85bc85869e63147c94427))

- Fix FINDING_F_013 — prevent root directory deletion ([`74c1aeb`](https://github.com/nark/WiredSwift/commit/74c1aebaa545377eac43135f4de8d66e773b8e81))

- Fix FINDING_A_016 — invalidate sessions on password change ([`581709e`](https://github.com/nark/WiredSwift/commit/581709e2828b207cee2a94b1bf7b602c8f0d0245))

- Fix FINDING_F_003, FINDING_F_004 — symlink resolution and root-path jail check ([`827ccc0`](https://github.com/nark/WiredSwift/commit/827ccc038d5f1576c6af75348e4db0aafd3b4c61))

- Fix FINDING_P_016 — safe unwrap XMLParser init ([`af985d6`](https://github.com/nark/WiredSwift/commit/af985d626c05a5d6886c4e1750c59753b4734036))

- Fix FINDING_P_006 — bound OOB read message length ([`66321fd`](https://github.com/nark/WiredSwift/commit/66321fde5444cbd6bf4f54d2b57f6104935003b4))

- Fix FINDING_P_005 and FINDING_P_014 ([`c0435d4`](https://github.com/nark/WiredSwift/commit/c0435d423ab6662c1c091b3c42964bbe66eb7519))

- Fix FINDING_A_002 — guard against nil client.user force unwrap crash ([`2a76c6a`](https://github.com/nark/WiredSwift/commit/2a76c6ae58a6491a75c4084cfae5c35aec3996a1))

- Fix FINDING_A_001 — rate limit login attempts per IP ([`b074806`](https://github.com/nark/WiredSwift/commit/b07480677e2dd97015dfacd659647596490b8d9a))

- Fix FINDING_P_007, FINDING_P_020 — safe unwrap response.name and propagate cipher errors ([`0ababa1`](https://github.com/nark/WiredSwift/commit/0ababa18120720a6d410a4cfa86f5607f7181a2a))

- Fix FINDING_F_006 — prevent privilege escalation via receiveAccountEditUser ([`7dd47be`](https://github.com/nark/WiredSwift/commit/7dd47be7ee682c31e732066ee0cbc61acb2142c8))

- Fix FINDING_F_005 — replace 25+ client.user! force unwraps with guard let ([`231309a`](https://github.com/nark/WiredSwift/commit/231309aee89c948b3d01a1944ceb8ca7fd53d1c4))

- Fix FINDING_C_001 — add lock to PrivateChat.invitedClients ([`c79eca0`](https://github.com/nark/WiredSwift/commit/c79eca026a70bbc0ecf0a5edcf6acffbaac344be))

- Fix FINDING_C_003, FINDING_C_004, FINDING_C_005 — eliminate force-unwrap crashes and race condition in ChatsController ([`6f17e44`](https://github.com/nark/WiredSwift/commit/6f17e445bcc77f04c3e3e1eafe907926e4685a79))

- Fix FINDING_A_003 — remove password hashes from account listing responses ([`b91e453`](https://github.com/nark/WiredSwift/commit/b91e45345d0aa4485f8f0be68daebc1524d5da3b))

- Fix FINDING_A_007 — block re-authentication when already logged in ([`f1ad3c8`](https://github.com/nark/WiredSwift/commit/f1ad3c8d460c94a0eccd230769c687261f4b0d14))

- Fix FINDING_F_001 + FINDING_F_002 — path traversal hardening ([`cc54315`](https://github.com/nark/WiredSwift/commit/cc54315a3acf3f7702fef940b24fffe8f537e9bc))

- Fix FINDING_P_002 + FINDING_P_003 — bounds checks and max field size in TLV parser ([`c3b7906`](https://github.com/nark/WiredSwift/commit/c3b79061d61b064f789394ef02d2f0975d3d87c5))

- Fix FINDING_P_001 — bound check on P7 message length to prevent OOM DoS ([`7c1fa79`](https://github.com/nark/WiredSwift/commit/7c1fa79a7ce45581516556ab192fd8eaad64e92f))

## [3.0-beta.7+15] — 2026-03-13

### Features
- Add search_files privilege, migration, and auto-sync wired.xml ([`b962d37`](https://github.com/nark/WiredSwift/commit/b962d37f83220c7c59dc49a37a52f7d3a6abc64a))

- Add FTS5 file search index with periodic reindex and CLI flag ([`175ecfd`](https://github.com/nark/WiredSwift/commit/175ecfd3ed998b34c61578074d9990be6a3f6515))

- Add --reload flag and hot-reload config support ([`70398ef`](https://github.com/nark/WiredSwift/commit/70398ef1a9be9a2143700b5fbb5fc67be23d0be4))


### Other
- Ensure wired.xml is updated when package copy differs ([`7dd228e`](https://github.com/nark/WiredSwift/commit/7dd228e116a690726c419357a75fdb609df61c63))

## [3.0-beta.5+13] — 2026-03-13

### Bug Fixes
- Fix port parsing and enforce integer-only validation ([`4c18d85`](https://github.com/nark/WiredSwift/commit/4c18d85ca2b43dd5ce04a7ac662dc579455e816b))


### Documentation
- Add Linux RPM and Docker usage/build guides ([`87bea5e`](https://github.com/nark/WiredSwift/commit/87bea5efbeb030d3077751fadcf5e6a3c90b51b7))


### Features
- Add multi-stage image for wired3 runtime ([`fc5ab0d`](https://github.com/nark/WiredSwift/commit/fc5ab0d0e8d6857cbff79c8c1c210c13ea013506))

## [3.0-beta.4+12] — 2026-03-13

### Bug Fixes
- Fix amd64 RPM architecture validation pattern ([`c03f675`](https://github.com/nark/WiredSwift/commit/c03f675928d5a05a7dd7f07d7ef3270814660c6f))

- Prevent auto-install on refresh and keep uninstall effective ([`96a9daf`](https://github.com/nark/WiredSwift/commit/96a9dafa92f0c1ed59a27833c67a3f0dda7441d0))

- Fix RPM workflow script generation without nested heredocs ([`6404685`](https://github.com/nark/WiredSwift/commit/6404685164c52f3391a26a51f7060e5c923b93aa))


### Features
- Add optional RPM packaging artifacts to Linux CI workflow ([`93458e3`](https://github.com/nark/WiredSwift/commit/93458e36fdec80e2a9f1f0670c6e1be296508c20))


### Other
- Use server version constants in wired.server_info ([`9615c22`](https://github.com/nark/WiredSwift/commit/9615c22ac989c47064282670fd999eede4a36291))

- Document GRDB custom SQLite build flag for Linux ([`777f5d9`](https://github.com/nark/WiredSwift/commit/777f5d9be307adcf16280b04e87f7cad7d5359a7))

## [3.0-beta.2+10] — 2026-03-12

### Bug Fixes
- Fix sqlite3 nil contextual type errors in legacy migrations ([`32d958f`](https://github.com/nark/WiredSwift/commit/32d958fc365b01d9bf2e082143985caaf9b41782))

- Fallback to bundled wired3 hash when metadata hash drifts ([`d607fa1`](https://github.com/nark/WiredSwift/commit/d607fa1afbe7f752b52229544a3d569e5adb529d))

- Hash plaintext password updates and normalize SHA-256 ([`de2e99f`](https://github.com/nark/WiredSwift/commit/de2e99f0efb296983e82c380c5a06bd8328b321c))


### Features
- Auto-update bundled wired3 with hash verification and rollback ([`3550ef3`](https://github.com/nark/WiredSwift/commit/3550ef3b910f80a1c5faed8e9de384c68d5b16de))

- Migrate from Fluent/NIO to GRDB v6 ([`81d46c8`](https://github.com/nark/WiredSwift/commit/81d46c82c3c5f8ddddecf4f958f150f681a37dd0))


### Other
- Work around missing sqlite snapshot symbols in Linux CI ([`1221a7a`](https://github.com/nark/WiredSwift/commit/1221a7a3c68cda263357298be33d6ded79032cde))

- Remove obsolete sqlite-nio Linux compatibility shim ([`c6dcfd2`](https://github.com/nark/WiredSwift/commit/c6dcfd2901a0ad8f74c4f6cc06cf51cf3a59a8b7))

## [3.0-beta.1+8] — 2026-03-10

### Bug Fixes
- Fix build script ([`bf5f222`](https://github.com/nark/WiredSwift/commit/bf5f22232fb4dbdfb6b420a04a0f706cb389173e))

- Prevent LLM from echoing nick: prefix in chat responses ([`a8023f7`](https://github.com/nark/WiredSwift/commit/a8023f7742462f162948f325a3bbd6f2c6c18f18))

- Add explicit CodingKeys enums to fix build error in BotConfig ([`538fecc`](https://github.com/nark/WiredSwift/commit/538fecc157eb9355bd4c5faac6b7efbb56241d0a))

- Encode nil optionals as null in generate-config output ([`7acaf70`](https://github.com/nark/WiredSwift/commit/7acaf70e0e1b5ace6d4ca8ca9d4e271943cee312))

- Don't prepend nick to LLM input for board events ([`0527ead`](https://github.com/nark/WiredSwift/commit/0527eadb07729c52ff6d658fd2d371599e565e88))

- Format llmPromptPrefix variables before LLM dispatch ([`095a353`](https://github.com/nark/WiredSwift/commit/095a353a506971c07db6292dc7b165f1019c9487))

- Add useLLM branch and debug logs in BoardEventHandler ([`b4bbd46`](https://github.com/nark/WiredSwift/commit/b4bbd461d4ce05dc5cc3ea0e9898dc2cc6a65502))

- Route wired.board.thread_changed instead of post_added ([`851d70e`](https://github.com/nark/WiredSwift/commit/851d70e0590afd906573cd338810dbbda388c97c))

- Subscribe to board broadcasts after login ([`8da6e5f`](https://github.com/nark/WiredSwift/commit/8da6e5fddc0176297e19c026a89d6e5dff5caa2e))

- Import FoundationNetworking in all LLM providers ([`ce14369`](https://github.com/nark/WiredSwift/commit/ce14369aaf27058c6f2048ddd4bacb876cce1dd3))

- Fix build: restore parameterless init() on all config structs ([`afee059`](https://github.com/nark/WiredSwift/commit/afee059e06bb06b173126faaabf14641e0e54084))

- Fix two compilation errors ([`d53ed10`](https://github.com/nark/WiredSwift/commit/d53ed10dff14d9cb2383c6c80c55105956876d71))


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

- Add respondInUserLanguage option ([`ab728a4`](https://github.com/nark/WiredSwift/commit/ab728a42cd9cb401283ab7e60fe80445d8464e28))

- Add comprehensive debug logging across the LLM pipeline ([`d88c2cd`](https://github.com/nark/WiredSwift/commit/d88c2cd075b0cc413d49673c768e7021f8d6baa8))

- Implement multi-user context strategy (6 improvements) ([`c6ab807`](https://github.com/nark/WiredSwift/commit/c6ab807b52dce3ea049c8a640d69c61a760d9cc6))

- Add WiredChatBot-README.md — documentation complète ([`2dd1c05`](https://github.com/nark/WiredSwift/commit/2dd1c054adedfc2393850e6be0163d71e7dd1411))

- Add WiredChatBot — AI-powered chatbot daemon for Wired 3 ([`bd8065c`](https://github.com/nark/WiredSwift/commit/bd8065c92977da35f53d6e426b2780485ae7953b))

- Bootstrap default Upload/DropBox and Welcome board content ([`1c4deeb`](https://github.com/nark/WiredSwift/commit/1c4deebd3022e984ac7158fd8401998696392e1b))


### Other
- Make config Codable resilient to missing/unknown fields ([`97e2ec8`](https://github.com/nark/WiredSwift/commit/97e2ec8e4cad41688e800021a1e7c4f419a9effd))

- Translate WiredChatBot-README.md to English ([`276ecac`](https://github.com/nark/WiredSwift/commit/276ecac693752df5b3758b637d07244b74fe1dac))

## [3.0+5] — 2026-03-07

### Bug Fixes
- Fix git safe.directory in containerized deb workflow ([`a31b303`](https://github.com/nark/WiredSwift/commit/a31b30354fee0bc46b77245a8987a0153edcd9d6))

- Fix Swift dependency copy in Linux deb workflow ([`1b591b5`](https://github.com/nark/WiredSwift/commit/1b591b50639bd8d39fd672e28bdb27824e8fb9bd))

- Fix Swift runtime lib path detection in Linux deb workflow ([`8cc2272`](https://github.com/nark/WiredSwift/commit/8cc22728f2a85de6547daa0ed533dc2e7cd80833))

- Fix missing libswiftCore in deb package ([`ae2c7c0`](https://github.com/nark/WiredSwift/commit/ae2c7c0abbb399ec129f51334a7e1865930fb3e3))


### Documentation
- Update README with Swiftly installation steps ([`5a0ad19`](https://github.com/nark/WiredSwift/commit/5a0ad198d2cd7ab8ec3177de2d0070442ea996f7))

- Adopt unified 3.0+N versioning across targets ([`fec893f`](https://github.com/nark/WiredSwift/commit/fec893fb1e59bd7e8092b796b4381b9a30e527c4))


### Other
- Package default runtime files and bootstrap Linux paths ([`f637561`](https://github.com/nark/WiredSwift/commit/f6375619e49a1b5319af1c33d49a21a82f8ad412))

- Remove legacy Linux deb workflow ([`85f5ef1`](https://github.com/nark/WiredSwift/commit/85f5ef12aa92ffa9872d43b5422c4364e5eb08b5))

- Harden Debian service user and working directory ([`4097dac`](https://github.com/nark/WiredSwift/commit/4097dac0f97e01ff574af96b2bdcc9772f5d38aa))

- Force bash shell in containerized deb jobs ([`6e7dbbc`](https://github.com/nark/WiredSwift/commit/6e7dbbc2ca2738b602e6de27e0129160777c52a0))

- Build Linux deb packages in jammy Swift container ([`d8f56f8`](https://github.com/nark/WiredSwift/commit/d8f56f89719cad9b9038c2f97d6696ec93e77f36))

## [3.0+999] — 2026-03-06

### Documentation
- Rewrite onboarding and clarify library/server version tags ([`88cf8be`](https://github.com/nark/WiredSwift/commit/88cf8bede716cc5dcc15e7a7a23491f3c9d53969))


### Other
- Update REAME ([`b805400`](https://github.com/nark/WiredSwift/commit/b805400e5d4cc67b659cc1d563bb0d1430ad88ae))

## [3.0+4] — 2026-03-06

### Bug Fixes
- Fix GitHub Action workflow for Linux distribution ([`83e1fd7`](https://github.com/nark/WiredSwift/commit/83e1fd730ae3a22c596d0325ab4a58e717fd6eb7))

- Fix GitHub Action workflow for Linux distribution ([`4cd0d2a`](https://github.com/nark/WiredSwift/commit/4cd0d2afca67d3cade3c10eca43dd870987f6092))

- Fix GitHub Action workflow for Linux distribution ([`45358a6`](https://github.com/nark/WiredSwift/commit/45358a6deca4402a5824ae74e8e530cb91f68855))

- Fix GitHub Action workflow for Linux distribution ([`accc5e8`](https://github.com/nark/WiredSwift/commit/accc5e88195744a49604b6e2a2e3bccf570a58f3))

- Fix GitHub Action workflow for Linux distribution ([`5b376e3`](https://github.com/nark/WiredSwift/commit/5b376e3c535f78904a2a0f93894fc51dfc25084f))

- Fix Linux SQLite symbol mapping for CSQLite ([`e4e87f3`](https://github.com/nark/WiredSwift/commit/e4e87f304ee174fd911d762ebe4233de049654ba))

- Fix Linux SQLite module conflict with sqlite-nio ([`cc8fd98`](https://github.com/nark/WiredSwift/commit/cc8fd98848c648268fd58c34154780a799de4409))

- Fix SQLite3 dependency for Linux ([`3b784b1`](https://github.com/nark/WiredSwift/commit/3b784b13369baf43b75241ae4a6b58d4b985acfa))

- Fix build script ([`b9450bf`](https://github.com/nark/WiredSwift/commit/b9450bf4fd93dad8308dc7939a6da0588b0ec5bf))

- Fix privilege refresh broadcast matching for logged-in users ([`ee64fd0`](https://github.com/nark/WiredSwift/commit/ee64fd0c738912986e1836cc1a882c18fa9f42ae))

- Preserve empty string fields when decoding P7 messages ([`268bf27`](https://github.com/nark/WiredSwift/commit/268bf276cbd71235e972013c3af116a23ad1a40a))

- Fix upload queue stalls and enforce transfer I/O deadlines ([`32bb16c`](https://github.com/nark/WiredSwift/commit/32bb16c97fd3d902d9d0db0855a879dfbb649149))

- Fix LZ4F version type for Linux build ([`9609d36`](https://github.com/nark/WiredSwift/commit/9609d36a8823c243d780f1783ec4865043d7b41e))

- Fix compression pipeline order for LZ4/LZFSE and DEFLATE ([`fc3841e`](https://github.com/nark/WiredSwift/commit/fc3841e2f0ee31ddfdc00a0f2689ef44d3d7bec8))

- Fix Linux build: use POSIX write in TransfersController ([`e395dc3`](https://github.com/nark/WiredSwift/commit/e395dc384979ca9ba0aea8bbda48889157be4986))

- Fix NSInterger issue ([`0d38bc2`](https://github.com/nark/WiredSwift/commit/0d38bc21259476c7da54ba6c3c330f17708862f2))

- Fix github CI build action (80) ([`5f681a4`](https://github.com/nark/WiredSwift/commit/5f681a4aa53d30af720d50d1fd2f935caa6c5302))

- Fix github CI build action (79) ([`a5b733e`](https://github.com/nark/WiredSwift/commit/a5b733e5b3b74a37bfe1837e00f59997cff69131))

- Fix github CI build action (77) ([`615027f`](https://github.com/nark/WiredSwift/commit/615027fe25b8e29e706f6439c34a28d1bbc24eef))

- Fix github CI build action (77) ([`196beab`](https://github.com/nark/WiredSwift/commit/196beab41a9633a10591938898082b004cd78053))

- Fix github CI build action (76) ([`13e5ba4`](https://github.com/nark/WiredSwift/commit/13e5ba45fe8079775df39c167eb2e7a115d8e10a))

- Fix github CI build action (75) ([`2929edd`](https://github.com/nark/WiredSwift/commit/2929edd0d8239efa3e7fd469f204e6080613a545))

- Fix github CI build action (75) ([`812fbcb`](https://github.com/nark/WiredSwift/commit/812fbcb0a298a0bfef275eb7b9fca889ac9b4123))

- Fix github CI build action (74) ([`0a2a882`](https://github.com/nark/WiredSwift/commit/0a2a8829c110e85f10810c08a53f6703afb664a7))

- Fix github CI build action (73) ([`de71408`](https://github.com/nark/WiredSwift/commit/de71408f132133f6835a1e1d9e7fbced0d6e5a08))

- Fix github CI build action (72) ([`761ea9b`](https://github.com/nark/WiredSwift/commit/761ea9b627ac9f2547dc0a9d47bd05382d5f6809))

- Fix github CI build action (2) ([`36c5222`](https://github.com/nark/WiredSwift/commit/36c5222ac45636cc835ae7974225368a48e16ab8))

- Fix github CI build action (2) ([`cd0d391`](https://github.com/nark/WiredSwift/commit/cd0d391e6c07ae6fec712c2ba723d80da47cfbc2))

- Fix github CI build action (2) ([`c8a0157`](https://github.com/nark/WiredSwift/commit/c8a0157bc33fd49fdab09226e35f09add4445b1b))

- Fix github CI build action (2) ([`3697544`](https://github.com/nark/WiredSwift/commit/369754412d81690a90d83aa8da54b572c59660f5))

- Fix github CI build action (2) ([`64ac0a6`](https://github.com/nark/WiredSwift/commit/64ac0a600fcfe071b0ef5730d963a2a03342678b))

- Fix github CI build action ([`da24849`](https://github.com/nark/WiredSwift/commit/da24849f2381ed93901af53212247ddb632c692b))

- Fix files index (2) ([`8a63b05`](https://github.com/nark/WiredSwift/commit/8a63b053cecdaef03368f32896af833cfdc37bec))

- Fix files index ([`c755538`](https://github.com/nark/WiredSwift/commit/c7555380ef8c05b52f9c0707138b6985a2e5f29f))

- Fix handshake encryption negociation and add new digest (HMAC, Poly1305) (2) ([`7c74623`](https://github.com/nark/WiredSwift/commit/7c74623ec9626f7a75d7325401126e03f473ee04))

- Fix handshake encryption negociation and add new digest (HMAC, Poly1305) ([`909abe1`](https://github.com/nark/WiredSwift/commit/909abe1e983e8c99391b56166f2f40d62e2ddf7a))

- Fix executable package for wired3 ([`07f9688`](https://github.com/nark/WiredSwift/commit/07f9688ad7cf5086e2295254347d9315bb886718))

- Fix package ([`e7d63ff`](https://github.com/nark/WiredSwift/commit/e7d63fff33cc089b45d48df8f23ccaf2db5e9692))

- Fix ping timer ([`971f667`](https://github.com/nark/WiredSwift/commit/971f667b8d7081495df61fc7bd364b145130432a))

- Fix test URL ([`bdaec62`](https://github.com/nark/WiredSwift/commit/bdaec6247b62e726c72b3ad93cd1d1b6bb9424a4))

- Fix clientInfo() ([`b607e55`](https://github.com/nark/WiredSwift/commit/b607e55da7d1db9eaba3a8a50850b738bccad212))

- Fix version in Xcode project ([`fb389d7`](https://github.com/nark/WiredSwift/commit/fb389d7e39582aa90596c4e7b7020bf2d65df1a6))

- Fix XMLParser init ([`96f86be`](https://github.com/nark/WiredSwift/commit/96f86bec07e07482277339c4128a0e650df84b1e))

- Fix namespace error ([`e0be92b`](https://github.com/nark/WiredSwift/commit/e0be92b18cda7c40295f5a0b4ae913a58d091b70))

- Fix namespace error ([`4c6b817`](https://github.com/nark/WiredSwift/commit/4c6b817859b3e71c7ac64e4d41cd8c962270649f))

- Fix SPM deployment targets ([`9dad2d5`](https://github.com/nark/WiredSwift/commit/9dad2d5ac2d57f0375812d10445e648e062b8fb7))

- Fix display bug on iPhone 6 ([`78d6e64`](https://github.com/nark/WiredSwift/commit/78d6e648f4600172bc404e7559714865fc73ff96))

- Fix wired.chat.me message ([`b35c171`](https://github.com/nark/WiredSwift/commit/b35c171ae7b86c1fc340d40e2475fccc1d522f33))

- Correct some typos ([`f48495a`](https://github.com/nark/WiredSwift/commit/f48495a47cff2d811ee23127a33b9a88d2d35898))

- Fix compatibility check ([`551e462`](https://github.com/nark/WiredSwift/commit/551e462062b428245ebc8a43c3d94b10593e4825))

- Fix project setting (signing) ([`d0387d7`](https://github.com/nark/WiredSwift/commit/d0387d70bf2ca5c38bbc5798313bd92fc053461c))

- Fix fix fix fix ([`9be81b1`](https://github.com/nark/WiredSwift/commit/9be81b1e07f91bafe42bc9e758bfe8b8bd9f85c5))

- Fix fix fix ([`81711bb`](https://github.com/nark/WiredSwift/commit/81711bb4c35a440d887d784d4e7cafb237fa7546))

- Fix Xcode issue ([`4e64bd8`](https://github.com/nark/WiredSwift/commit/4e64bd844029df3815d4991c688df8e33c88d1ba))

- Fix race condition in Boards/threads loading? ([`888d192`](https://github.com/nark/WiredSwift/commit/888d192de0a6e08dfae2e87198d4e81b0c6e1f34))

- Fix remove transfer from context menu ([`0ebf337`](https://github.com/nark/WiredSwift/commit/0ebf3379d71db5bc35628b19f588605da54f21cf))

- Fix github CI ([`ce3cc0a`](https://github.com/nark/WiredSwift/commit/ce3cc0a4a9169301efaaa2fbe0a0a68a1ca8605d))

- Fix message view bug with initials text color ([`1b4d77b`](https://github.com/nark/WiredSwift/commit/1b4d77bd20907e773d4e22b46ba1fc47d6f8fa9a))

- Fix user idle status in chat list ([`6cc3637`](https://github.com/nark/WiredSwift/commit/6cc3637d8b6f8ea20a66c54e0ec929486a549ff5))

- Fix transfer progress ([`9044f02`](https://github.com/nark/WiredSwift/commit/9044f025fdecf2ae0f10b643048429008587b56e))

- Fix missing MessageKit framework in build dependencies ([`553ff0f`](https://github.com/nark/WiredSwift/commit/553ff0f36fbbd88a62fe905978b5d1eaaf6c7a69))

- Fix socket read (yay) ([`72a9d10`](https://github.com/nark/WiredSwift/commit/72a9d10a5c8b2dbe52627951d2eb0b414e466af7))

- Fix connection close when closing tab ([`266925d`](https://github.com/nark/WiredSwift/commit/266925d71d49298ee643fe3750c15edce4438990))

- Fix plist ([`7612675`](https://github.com/nark/WiredSwift/commit/7612675f97f2e257ea9245c92b5a8b7eb3d5c170))


### Documentation
- Update README ([`47a3c73`](https://github.com/nark/WiredSwift/commit/47a3c738de5424324ed8f6237304e78cf33d19fa))

- Update README about BlockConnection ([`cbdbf37`](https://github.com/nark/WiredSwift/commit/cbdbf37cab976d45647e37450f40642553a8b3b4))

- Update README about BlockConnection ([`42f6e32`](https://github.com/nark/WiredSwift/commit/42f6e326d117fa54c64f6935011cb084d6f2595c))

- Update README ([`7f0692b`](https://github.com/nark/WiredSwift/commit/7f0692b100155646f7d78795efe54398187a71db))

- Update README ([`0413d1a`](https://github.com/nark/WiredSwift/commit/0413d1abe5994a02a0afd2f06db6da5568d7bdde))

- Update README ([`fe74553`](https://github.com/nark/WiredSwift/commit/fe74553c68b893d54d7086f02b2eae568cd36ccf))

- Update README ([`5e9523a`](https://github.com/nark/WiredSwift/commit/5e9523a92ba4a83c9ec1f058558c0c5815f4091d))

- Update README ([`75f0d17`](https://github.com/nark/WiredSwift/commit/75f0d173853e80556702ed7b26030d6432a14a4f))

- Update README ([`5a34411`](https://github.com/nark/WiredSwift/commit/5a344119951e1c57c8593a17b8188eab86ca67f3))

- Update README with minimal instructions about WiredSwift ([`dbf8966`](https://github.com/nark/WiredSwift/commit/dbf8966be72e6eec09cc8ac101a0ec5f7be0824a))

- Update README ([`e462649`](https://github.com/nark/WiredSwift/commit/e462649250181067922f7b3e1b2d67cfa3600b5d))

- Update README ([`6197f07`](https://github.com/nark/WiredSwift/commit/6197f075bad1963a810ba7443a2e34238557a939))


### Features
- Add GitHub Action workflow for Linux distribution ([`547a047`](https://github.com/nark/WiredSwift/commit/547a047a9fe099ddc685b270e7fccc9d0d3ea74b))

- Add WiredServerApp and switch advanced crypto config to text modes ([`9114c07`](https://github.com/nark/WiredSwift/commit/9114c0790829f715787abb3f2a0ac37bdce69c53))

- Implement boards server-side handlers and stability fixes ([`0aa95e8`](https://github.com/nark/WiredSwift/commit/0aa95e859e8b015659437543e3b66229e8b23f44))

- Add boards data models (WiredBoard, WiredThread, WiredPost, BoardsManager) ([`4f8e61a`](https://github.com/nark/WiredSwift/commit/4f8e61a39d06b340ad157cc11085171453973607))

- Persist group account color and expose it in account messages ([`ff3a4c8`](https://github.com/nark/WiredSwift/commit/ff3a4c8d0c7b2d14986987c986487a0e592eed95))

- Implement private chat invitation/decline flow and tighten chat membership checks ([`05d57f5`](https://github.com/nark/WiredSwift/commit/05d57f5da330b81d8b1865ea4e5add1cd835060c))

- Implement account change broadcasts and privilege reloads ([`a89be53`](https://github.com/nark/WiredSwift/commit/a89be5376ac788b726bab6429492b9d5b10d8306))

- Implement account management and transfer error handling ([`45991f6`](https://github.com/nark/WiredSwift/commit/45991f653915eb2517c30010a8bbcf59fea5fb26))

- Implement recursive file listing for folder downloads ([`db20073`](https://github.com/nark/WiredSwift/commit/db20073fbb58800dbc8b3d196c880184bcd1d977))

- Implement directory subscribe/unsubscribe and change notifications ([`8851c31`](https://github.com/nark/WiredSwift/commit/8851c3136d1e9fa9008946b7421a43b5799e3351))

- Support Apple bv4* LZ4 header variants on Linux ([`5e8b0c1`](https://github.com/nark/WiredSwift/commit/5e8b0c1ff9144a7a73f1f1ba235de9de70a76dac))

- Add detailed LZ4/compression debug logging ([`039777f`](https://github.com/nark/WiredSwift/commit/039777fa09e9c63ef0adbe92f5661cd17f2ed0b9))

- Align Linux LZ4 format with Apple Compression ([`ab8e436`](https://github.com/nark/WiredSwift/commit/ab8e436d8c4005ef9cd7e275a9908872d16a2490))

- Add Linux support for P7 compression algorithms ([`383d2f5`](https://github.com/nark/WiredSwift/commit/383d2f5b1d036a36dc00b66a9d78c4a02253a55a))

- Add config and persistent server settings ([`a052da4`](https://github.com/nark/WiredSwift/commit/a052da409b7da2d13446bb92044bdaaeb2ef3f0d))

- Add ECDSA password challenge support ([`5dd8398`](https://github.com/nark/WiredSwift/commit/5dd83980c1af827fc7a9bb3002e994bcc6af39b4))

- Add SHA3-256 support ([`6e3d307`](https://github.com/nark/WiredSwift/commit/6e3d307c28164e156e82da8d062efe76f7530fe2))

- Add ChaCha20 cipher support ([`86c424a`](https://github.com/nark/WiredSwift/commit/86c424a9ea2965765062aa45cf58b078c1938352))

- Add missing swift-argument-parser in package (3) ([`c3119bd`](https://github.com/nark/WiredSwift/commit/c3119bd93ee2eab8a20df0366c0317e62e3bf9db))

- Add missing swift-argument-parser in package (2) ([`cac8540`](https://github.com/nark/WiredSwift/commit/cac8540fe19e9ffeb6e8d36983aa371bef51f12a))

- Add missing swift-argument-parser in package ([`ac069eb`](https://github.com/nark/WiredSwift/commit/ac069eb67fb8332c77af8fd9f484e3bed7f61091))

- Add wired3 to SPM ([`e8c76ea`](https://github.com/nark/WiredSwift/commit/e8c76eaf0984cd140747c3b9e30bfda320115fc6))

- Add wired3 to SPM ([`747caa8`](https://github.com/nark/WiredSwift/commit/747caa87fd5689e091b92d5ae703b6ce95bc3093))

- Add simple send method to BlockConnection ([`3028dd4`](https://github.com/nark/WiredSwift/commit/3028dd4fdad0ea2a34501605acbaca3496741d02))

- Add reconnect method (public) ([`a676a54`](https://github.com/nark/WiredSwift/commit/a676a54ba828d061127221d70bf3d5a4752dfde8))

- Add reconnect method ([`28ee3a4`](https://github.com/nark/WiredSwift/commit/28ee3a4085583193c5936f93bed9fd1a90683546))

- Add test for block connections ([`092f9e3`](https://github.com/nark/WiredSwift/commit/092f9e3b848c1b6f6f52bbca4f32120e12ce000a))

- Add block connections based on wired.transaction ([`9e17d20`](https://github.com/nark/WiredSwift/commit/9e17d2038f922c143404f2aaf880ea5257e927e3))

- Add checksum support to P7Socket (oob data) ([`f051b0b`](https://github.com/nark/WiredSwift/commit/f051b0b7a4a81d7bf713d2cc97d7164552c662f8))

- Add checksum support to P7Socket (fix cipher config) ([`53d9645`](https://github.com/nark/WiredSwift/commit/53d9645a26e052d04a90952902659a5a474fbe74))

- Add checksum support to P7Socket ([`1acbf78`](https://github.com/nark/WiredSwift/commit/1acbf7844be848f4beebfbf91e7d0cb1464aa721))

- Add support for left/join messages ([`add22f1`](https://github.com/nark/WiredSwift/commit/add22f153691efa85ff15474014ef208fce30707))

- Add camera support ([`a4585de`](https://github.com/nark/WiredSwift/commit/a4585de927e087cea06bcea570fd24f29f4c70ac))

- Add iOS support to WiredSwift framework ([`4aecaee`](https://github.com/nark/WiredSwift/commit/4aecaee90418e226adedc4d7381502e00dcf0f97))

- Add user info panel ([`83ac5d0`](https://github.com/nark/WiredSwift/commit/83ac5d00a279d37b47c28b177877b4d3cd2d9a81))

- Add UUID support ([`7b5b0df`](https://github.com/nark/WiredSwift/commit/7b5b0df7b9d5b42489e384592bcb6adf93e24747))

- Support for ieee754 double ([`d0c0b96`](https://github.com/nark/WiredSwift/commit/d0c0b96815b6ae5ca02ffd0202cd13fb9ed25660))

- Add message time in conversations list ([`34eb71d`](https://github.com/nark/WiredSwift/commit/34eb71dfef90f228836696916aa17dc5c29a533b))

- Add transfer buttons ([`acd5bce`](https://github.com/nark/WiredSwift/commit/acd5bce74c52c6f6506cc22796e55a8b9fa9bdcf))

- Add transfers controller and view ([`a211af5`](https://github.com/nark/WiredSwift/commit/a211af556757c61be8c16bf8fec8c835548617ac))

- Add minimal files browser ([`7589e85`](https://github.com/nark/WiredSwift/commit/7589e859b5337f18b241eeea9567ef0c5f53a750))

- Add Tab support for messages, boards, files, etc. views ([`f3b8255`](https://github.com/nark/WiredSwift/commit/f3b825546b934b9adfcfa12e1f273a6ac92123e0))

- Add resources split view + icon ([`9453d3c`](https://github.com/nark/WiredSwift/commit/9453d3cdab1fea5f8bb48308e3fb45001d24b613))

- Add Preferences window (empty) ([`a7e33ed`](https://github.com/nark/WiredSwift/commit/a7e33edb788fd93a946f71dc025b21cc980a6fe2))

- Add minimal Wired error support ([`864b84c`](https://github.com/nark/WiredSwift/commit/864b84cf01e78ffac1593921704f2a5166fe3e17))

- Add gitignore ([`142e2cb`](https://github.com/nark/WiredSwift/commit/142e2cbb5c49556715aa82bc43fa806d73bab091))

- Add LICENSE & minimal README ([`c7a922c`](https://github.com/nark/WiredSwift/commit/c7a922c4318954a92d0272a316f8bbaf82c690ae))


### Other
- Update Package.resolved lockfile ([`6d763f1`](https://github.com/nark/WiredSwift/commit/6d763f17edfd8964f2dd438d1240af1303f569ba))

- Better UI layout ([`527a899`](https://github.com/nark/WiredSwift/commit/527a899c57b3ba599d5c9696b2d8c897cd9708cd))

- Adopt macOS Settings-style split view for WiredServerApp ([`e488fc2`](https://github.com/nark/WiredSwift/commit/e488fc2ecb54e0e1294f770e3fe613074b88b570))

- Bundle original Wired Server icon into app package ([`b93f741`](https://github.com/nark/WiredSwift/commit/b93f741293019b138bee79d8b74923a0f58389a2))

- Bootstrap runtime working directory and server settings paths ([`42d180f`](https://github.com/nark/WiredSwift/commit/42d180f487e538fe41c0b63ba827ec978da424bc))

- Send account colors in list messages and set bootstrap defaults ([`47f1fd6`](https://github.com/nark/WiredSwift/commit/47f1fd62a62e5ceb038b44aff8f9049aabd474a6))

- Harden P7 numeric serialization to avoid UInt32 cast crash ([`6cd32ec`](https://github.com/nark/WiredSwift/commit/6cd32ecf2364c6d0f9f58ca5b48836466145660f))

- Always include account color in privileges payloads ([`4f33bb5`](https://github.com/nark/WiredSwift/commit/4f33bb5511c4a8835b999317976d9d5a587c6da0))

- Handle account color enum and broadcast user colors ([`f4e3680`](https://github.com/nark/WiredSwift/commit/f4e3680a52a5d0dd04a177a97b11ae532c6530fb))

- Fix create_directory permissions and behavior ([`e5fa501`](https://github.com/nark/WiredSwift/commit/e5fa5013842a85f7cc7324060b36402a6251c114))

- Update READEME ([`9d9b8be`](https://github.com/nark/WiredSwift/commit/9d9b8beb7cd0fd03ec85f02f61ebdb6bb2698b2d))

- Remove unused SWCompression dependency ([`eb98d9f`](https://github.com/nark/WiredSwift/commit/eb98d9fda6ef946799e011ca42bc7196e638af4d))

- Clean temporary LZ4 debug logs ([`69efd12`](https://github.com/nark/WiredSwift/commit/69efd1204761628e5cc3e9bec9f6cc10665035f5))

- Force deterministic LZ4 store framing across platforms ([`6ea8a65`](https://github.com/nark/WiredSwift/commit/6ea8a6595016c96dd1e71fbe7e18e691323066d2))

- Use Apple-compatible stored LZ4 framing on Linux ([`729bb50`](https://github.com/nark/WiredSwift/commit/729bb50ccf6e7be9efb6faf5acf849f45832d654))

- Update gitignore ([`e549c74`](https://github.com/nark/WiredSwift/commit/e549c7406f0682e2ddbc71103f3251d446a90632))

- Make Linux LZFSE optional via runtime detection ([`9c89de9`](https://github.com/nark/WiredSwift/commit/9c89de9b57462394598f7866b0911e820a8904a7))

- Vendor SocketSwift no-TLS fork for Linux ([`ae02d20`](https://github.com/nark/WiredSwift/commit/ae02d206b8e6a9c1b8c6d4768bf29cf8121f3b9b))

- Minor fixes ([`272d4b7`](https://github.com/nark/WiredSwift/commit/272d4b77ca2d8a3c5ebb1519181edf456c90f10d))

- Clean ignore ([`683ed65`](https://github.com/nark/WiredSwift/commit/683ed65a377e3dd536bfee7859567c1bb441f5f3))

- Update gitignore ([`91bc46a`](https://github.com/nark/WiredSwift/commit/91bc46aa040e7cbacb88f23d6f49a180a9c48dff))

- Before transfers queue ([`c7ca90d`](https://github.com/nark/WiredSwift/commit/c7ca90ddd6d917ec0ea37fc4c58eee7caebf890d))

- Server settings ([`22ad318`](https://github.com/nark/WiredSwift/commit/22ad3185ea783c476c50cfc988fe5b04e6dce9d1))

- Before lock ([`44dc146`](https://github.com/nark/WiredSwift/commit/44dc146142866dc2f607795160e426e69c81b228))

- Remove useless print ([`55c87ad`](https://github.com/nark/WiredSwift/commit/55c87adccfb707e9880549be7477d28a7e97f886))

- Testing basic semaphores (3) ([`810ac7e`](https://github.com/nark/WiredSwift/commit/810ac7e53d2d406ab655573ad718beb1917cc378))

- Testing basic semaphores (2) ([`bb9b3a8`](https://github.com/nark/WiredSwift/commit/bb9b3a89c4a751b1d864cc6610256372e617b130))

- Testing basic semaphores ([`1271055`](https://github.com/nark/WiredSwift/commit/12710551d1d567f08d2638aa0b00fc5d9fbfaa66))

- Transfer round trip OK ([`c4beaf0`](https://github.com/nark/WiredSwift/commit/c4beaf0299049b0a9a8f8bb53e041a64c9e292a4))

- Upload support ([`274c737`](https://github.com/nark/WiredSwift/commit/274c7379d64a912e147ba53bc95a29a2211b40e1))

- AES IV is also derived from ECDH key ([`31e5202`](https://github.com/nark/WiredSwift/commit/31e52020c4b374b31b262639d4ef45af261d24ef))

- Update Xcode project required settings ([`f33803d`](https://github.com/nark/WiredSwift/commit/f33803d65841f2e459c69ea727cb878e8fc63347))

- Clean project from warnings ([`f0f0e39`](https://github.com/nark/WiredSwift/commit/f0f0e3976472e0b49c52fd3927c2f02bb943758e))

- Wrap ECDSA in a class and clean key exchange ([`22b17e6`](https://github.com/nark/WiredSwift/commit/22b17e66a82ed9c0127f95b9c10b73380b041704))

- Clear SPM package ([`9d91066`](https://github.com/nark/WiredSwift/commit/9d910665522ddcb6f78a774cb405976bb50add9c))

- Try to replace RSA/AES by ECDH/AES (3) ([`b27c094`](https://github.com/nark/WiredSwift/commit/b27c0947ee661ae2225082c312ce092c5d9a45bc))

- Try to replace RSA/AES by ECDH/AES (2) ([`0f96c11`](https://github.com/nark/WiredSwift/commit/0f96c11529e337054d56249e2410ce3d3fb525f2))

- Try to replace RSA/AES by ECDH/AES ([`de77576`](https://github.com/nark/WiredSwift/commit/de775768ce3769cc76d49c1ef865d30629b3e2cf))

- Switch from GRDB to Fluent ORM for Linux support (3) ([`1a2abf1`](https://github.com/nark/WiredSwift/commit/1a2abf1d65883c4543e39b1145ce615855e9f7d3))

- Switch from GRDB to Fluent ORM for Linux support (2) ([`453c9ed`](https://github.com/nark/WiredSwift/commit/453c9edc305e78ccf1ede73eb9aa4205903c3fac))

- Switch from GRDB to Fluent ORM for Linux support ([`6de38fa`](https://github.com/nark/WiredSwift/commit/6de38fac18d70ba3b71be4850600b9a40dec5735))

- Updated wired3 server + a lot of fixes ([`1e95763`](https://github.com/nark/WiredSwift/commit/1e95763fa2597adbdc0a1a3cb544c8d184c5fb09))

- Enforce SHA256 usage for password hashing ([`2d9f272`](https://github.com/nark/WiredSwift/commit/2d9f2723e0c3cfeff358f06af164369e36780d6b))

- Make Wired macOS Swift client a test platform ([`f8a63c8`](https://github.com/nark/WiredSwift/commit/f8a63c8053c1d76c6b6051f6d76ce0d57c9b273b))

- Remove banner from server_info for now ([`80595b3`](https://github.com/nark/WiredSwift/commit/80595b309741ebcd356b334823785ecd2fb27efe))

- Maybe Wired 3 ([`effaab1`](https://github.com/nark/WiredSwift/commit/effaab1a7cca09ecdee96ae203c5c42021589c5a))

- Reconnect test passed ([`da5a28c`](https://github.com/nark/WiredSwift/commit/da5a28c4367a201ea7f9e87e2a77ed20aac32de0))

- Better socket diconnect ([`baa716e`](https://github.com/nark/WiredSwift/commit/baa716e1bc02ec508138aefd61455f492cace45f))

- Make BlockConnection class public ([`4ef1650`](https://github.com/nark/WiredSwift/commit/4ef1650d606e3fdfbf79d71c84879bae7766f6f5))

- Continue relay message to delegates ([`b694dcf`](https://github.com/nark/WiredSwift/commit/b694dcf3ad1ea49c5056ca316d829c0c7fef3cc2))

- Thread safe block connection ([`755792f`](https://github.com/nark/WiredSwift/commit/755792fa97ea02caa162af5a8297a1863726011e))

- New delegate methods in Connection class to handle app name, version and build number ([`95cf5c1`](https://github.com/nark/WiredSwift/commit/95cf5c113602f38a1d2d64d24a158d768bc813e9))

- Load spec from URL (fix typo) ([`da05d03`](https://github.com/nark/WiredSwift/commit/da05d039bb2a9922e07f832fb8f20ffcada23d54))

- Load spec from URL ([`b9ce9ed`](https://github.com/nark/WiredSwift/commit/b9ce9ed2d211d30fbd21d59df34f3da37d1df869))

- Update github workflow (6) ([`18f39f7`](https://github.com/nark/WiredSwift/commit/18f39f731cedd43f4fb1b3839481af813b83350b))

- Update github workflow (5) ([`0d2a153`](https://github.com/nark/WiredSwift/commit/0d2a1532c3dc8dc49e7c30c3120d49b97e511593))

- Update github workflow (4) ([`30a1602`](https://github.com/nark/WiredSwift/commit/30a1602f741d004e9662deef801208b1c3fe02cd))

- Update github workflow (3) ([`1277c2a`](https://github.com/nark/WiredSwift/commit/1277c2aae4d30e1c37189e5ad2ae0fc8c730f3bb))

- Update github workflow (2) ([`53464fd`](https://github.com/nark/WiredSwift/commit/53464fdedeaa43720948515ab959dae8e7512423))

- Update github workflow ([`b59fa06`](https://github.com/nark/WiredSwift/commit/b59fa0633eadc500019f09408380203bb6500428))

- Better package structure ([`feb7ea9`](https://github.com/nark/WiredSwift/commit/feb7ea97ef3cb5e1f78eaa266ddd11c36af9151f))

- Organize somes files ([`0f23665`](https://github.com/nark/WiredSwift/commit/0f2366597d90a49148064059bdeeea38b3bd6f46))

- Better debug scenario ([`72fa244`](https://github.com/nark/WiredSwift/commit/72fa2449112c27c7ea9440d31a321bcd59539395))

- Try to use CryptorRSA (only on Linux) ([`31e727c`](https://github.com/nark/WiredSwift/commit/31e727c11f6fe308c0eb47ae0c44d50713d6ecb6))

- Clean some cached files ([`3f0f062`](https://github.com/nark/WiredSwift/commit/3f0f062fac0d86d8d521218922f33eadb41b9cfe))

- Update Xcode project version to 1.0.5 ([`a3609b1`](https://github.com/nark/WiredSwift/commit/a3609b18e444e647039a4f0a0f16f505247a1d6b))

- Clean repo and remove macOS and iOS targets ([`b05beda`](https://github.com/nark/WiredSwift/commit/b05beda3262698e1c685164306d38f89176b3b11))

- Import FoundationXML ([`a1db61d`](https://github.com/nark/WiredSwift/commit/a1db61da86ebe0e7c9b0688768d4de65593edb24))

- Remove CommonCrypto (seems unused) ([`1ea6f29`](https://github.com/nark/WiredSwift/commit/1ea6f298755cbda9444c6f3846e867c361a9d6a3))

- Remove BBCodeString ([`2605769`](https://github.com/nark/WiredSwift/commit/2605769349fd10f088d65012b0bfec0f700ffa1d))

- Big cleaning: remove the Wired macOS target ([`456ec5f`](https://github.com/nark/WiredSwift/commit/456ec5fbf2903be4d649564a366c932c3f4d0341))

- Minimal boards + WiredSwift fixes and SPM ([`f6fe458`](https://github.com/nark/WiredSwift/commit/f6fe458ff0d87319f89e9204ffa2cdde37404ade))

- Rollback and remove Linux platform ([`e05fc8b`](https://github.com/nark/WiredSwift/commit/e05fc8b2ac91ccc4e0703bdf62daab1a78efe462))

- Rollback and and Linux platform ([`470168a`](https://github.com/nark/WiredSwift/commit/470168ab2556c7be91449e10b62d958f82c81a5a))

- Try without any platforms in SPM manifest ([`6f37bf1`](https://github.com/nark/WiredSwift/commit/6f37bf1cc47a42808e0834b0e1f80a8422c86239))

- Try to add SPM support ([`9ee3712`](https://github.com/nark/WiredSwift/commit/9ee3712301e10efd7cb9e7f01138f6985c61159c))

- Full fr localisation + fixes ([`6c8040e`](https://github.com/nark/WiredSwift/commit/6c8040e346678c7bf645a7683423b7fe308b1d3e))

- Fr localisation + new send button ([`7b09f2f`](https://github.com/nark/WiredSwift/commit/7b09f2f4dcb97f05218d1ba0c572f6e093c16b7d))

- Wired iOS: Add onboarding and review design ([`f16daa5`](https://github.com/nark/WiredSwift/commit/f16daa53968096d4007c272fea84ca4755793c00))

- Wired iOS: prevent sending empty message with text attachment ([`cf57e59`](https://github.com/nark/WiredSwift/commit/cf57e596792921e6c8eb64d8bc7f1efe485fdac6))

- Reimplement P7Message.xml() method with AEXML library (very handy to debug messages in console) ([`a8a4475`](https://github.com/nark/WiredSwift/commit/a8a44758181f7c46b01614c314b7017171c75c6b))

- Wired iOS: fix image picker for user icon and split view on iPad ([`222c9e4`](https://github.com/nark/WiredSwift/commit/222c9e49387568086fa9ec0e8fc46e7f6fd221c4))

- Wired iOS: support idle status in users list ([`b087fd5`](https://github.com/nark/WiredSwift/commit/b087fd59d7f0e16d79fcab33339bea63cb34552a))

- Wired iOS: support disconnect, kick and ban messages in chat ([`15a6fbd`](https://github.com/nark/WiredSwift/commit/15a6fbd05578363e0671be961dda35d0df4d9b9c))

- Wired iOS: support topic ([`9f4890d`](https://github.com/nark/WiredSwift/commit/9f4890d30271f4afe22c245847817fd242e4c9f0))

- Wired iOS: clean and refactor ([`372a112`](https://github.com/nark/WiredSwift/commit/372a112420c4a4fb96852e3a760aaa2d9ff8af85))

- Find a lot of strings that was not translated. ([`a83ae9b`](https://github.com/nark/WiredSwift/commit/a83ae9ba8caa6d23cfc1e73379bce332db80ee67))

- Added localiz. for calender strings ([`d8ec810`](https://github.com/nark/WiredSwift/commit/d8ec81035981d97eb9f2b3039327f72489616641))

- Added german localisation for calender entries. ([`df1e43b`](https://github.com/nark/WiredSwift/commit/df1e43bc43d4d7ba6bafe55f422c60ab7db8654e))

- Delete project.pbxproj ([`012ea3d`](https://github.com/nark/WiredSwift/commit/012ea3dba1cc6396d21703cdc012c6b65b4c7ec5))

- Update UsersViewController.swift ([`b412c8b`](https://github.com/nark/WiredSwift/commit/b412c8b28011c6c333f5b63461dd6c0973bfc4a6))

- Added german localisation for calender entries. ([`d0aa331`](https://github.com/nark/WiredSwift/commit/d0aa33145fa93347313297b76e56cad99dcc9624))

- Fixed unreadable colors in Darkmode for Userlist. Added Theme change detection. ([`83a1df6`](https://github.com/nark/WiredSwift/commit/83a1df652eb526dd35d1c49328c8a7311d39bc10))

- Added missing console localization ([`ff8c522`](https://github.com/nark/WiredSwift/commit/ff8c5229da428dc98c3fc88edf77664e1e4bb804))

- Fixed user view status color in darkmode. Prepared Theme detection (dark/light) for nickname color change. ([`87c82ce`](https://github.com/nark/WiredSwift/commit/87c82ce994f599f81b275e08b45629b42806f83f))

- Wired iOS: clean and refactor ([`21bb764`](https://github.com/nark/WiredSwift/commit/21bb76465cf5aa646cc7e36ccf64772ea5ae5663))

- Clean repo ([`6d24c08`](https://github.com/nark/WiredSwift/commit/6d24c0804071491cbd3836d2cb74f84f1a73cd68))

- Wired macOS: display received images in chat and messages ([`11c0d04`](https://github.com/nark/WiredSwift/commit/11c0d04fc6aa43e9864bbdde5776a203d33b782d))

- Minor iOS fix + framework adjustments ([`bf1ee43`](https://github.com/nark/WiredSwift/commit/bf1ee43ce4c90fcc14e6eb734dfe486173496848))

- Try to link framwork for device ([`edfce2c`](https://github.com/nark/WiredSwift/commit/edfce2cf28e9051f3c841da32ef961c72b945aad))

- Minimal iOS client ([`16de950`](https://github.com/nark/WiredSwift/commit/16de950e4feb03df3c747cb8b517860800401f4a))

- German Translation completed ([`f4382c4`](https://github.com/nark/WiredSwift/commit/f4382c41beeeb8131a467e32142eff92294d38da))

- Join public chat from iOS simulator works ([`8490be3`](https://github.com/nark/WiredSwift/commit/8490be3e441c73dd324dd2b7dd228d32a19e2dd0))

- Merege latest changes ([`c5be3e2`](https://github.com/nark/WiredSwift/commit/c5be3e25bce3dbdf0c915c724261c1bb76ed894a))

- Added german translation partly. Added Sparkle Update Framework. ([`60041e2`](https://github.com/nark/WiredSwift/commit/60041e252520272cdd04acac2d06a74eb1a68e00))

- Remove MessageKit(macos) ([`c1f0dfa`](https://github.com/nark/WiredSwift/commit/c1f0dfa975cc7aef751559a2cf38160851ac153d))

- Fixes fixes fixes ([`5040e8b`](https://github.com/nark/WiredSwift/commit/5040e8bffda540491b976124158bbf36c7569ece))

- Banner is back in main window toolbar ([`6a034ce`](https://github.com/nark/WiredSwift/commit/6a034ce616a4f28f95c53609819e907cd8e646f5))

- Search race condition ([`0b504c8`](https://github.com/nark/WiredSwift/commit/0b504c8bde8816b18af266012dd6f4cf1517e70d))

- User info displays in a popover ([`44cb6ba`](https://github.com/nark/WiredSwift/commit/44cb6ba8e9afb97748fb66f1cff60135129b1450))

- Better menu validation of sidebar items ([`01f42de`](https://github.com/nark/WiredSwift/commit/01f42dee7caa605607066957c7c17db8e7602a26))

- Better auto-reconnect ([`62a43b1`](https://github.com/nark/WiredSwift/commit/62a43b100017c6caa7344266ee9a5abd737037d3))

- Safe disconnect when ping failed or network is unreachable ([`7841128`](https://github.com/nark/WiredSwift/commit/78411280f7143f02cf0d5f41977d106e3fa00290))

- Try auto-reconnect every 10 sec when disconnected (fix #4) ([`f858f64`](https://github.com/nark/WiredSwift/commit/f858f64fd817ff0981f01ff87d415557a2d185fe))

- Missing snippet in README ([`1b6d110`](https://github.com/nark/WiredSwift/commit/1b6d110baefc4f157b1f294a97c423fb5eea0758))

- Missing snippet in README ([`0fbd726`](https://github.com/nark/WiredSwift/commit/0fbd726f7a9d174a91ad6936dbb69d4fa63dd0fc))

- Auto-connect bookmark at startup fix #1 ([`e788a64`](https://github.com/nark/WiredSwift/commit/e788a64670bd094200b0097a4c5bb92510b7e8e2))

- Read boards ([`0f7c98b`](https://github.com/nark/WiredSwift/commit/0f7c98b044f12ceb599048ae46a9cc09434fb497))

- Load and display thread posts ([`f2f449b`](https://github.com/nark/WiredSwift/commit/f2f449b29e9e73976e9ede4784e282d53a9b2990))

- Thread row has dynamic height ([`fffaa6e`](https://github.com/nark/WiredSwift/commit/fffaa6e2679f6ea79bea3925fbf163b10a40061b))

- Load threads for board ([`a296ff0`](https://github.com/nark/WiredSwift/commit/a296ff0fbc1ff8cb817a82ba961a5b9704002ace))

- Minimal boards loading and UI ([`30b1769`](https://github.com/nark/WiredSwift/commit/30b176935e6b56f34d932f07aeed00086ef90696))

- Files navigation history and better sync of list and browser views - fix #12 ([`9e59190`](https://github.com/nark/WiredSwift/commit/9e59190201345772bf85262431bf8ca75c0f1aac))

- Xcode cleaning ([`c1834a0`](https://github.com/nark/WiredSwift/commit/c1834a0047d736d821798d524d7d8af30d5a8263))

- Better double unpack ([`ca93a84`](https://github.com/nark/WiredSwift/commit/ca93a845c922994ad2cc68880b4fda4c42b059e7))

- Minimal server info ([`0a660a1`](https://github.com/nark/WiredSwift/commit/0a660a15109a0e44dd789157f229bba52f822f53))

- Review transfers and files buttons design ([`4f46eaa`](https://github.com/nark/WiredSwift/commit/4f46eaafdc861cad8fbc14b99cb9b37a3beec1ec))

- Better unexpected disconnect handling ([`62a8f41`](https://github.com/nark/WiredSwift/commit/62a8f410d4557a3a0fe2cff2e1662b61ced03a09))

- Clean logs ([`7339387`](https://github.com/nark/WiredSwift/commit/7339387abdac6d59ea33e072da366dd11bc16ca5))

- Upload file working ([`8df516c`](https://github.com/nark/WiredSwift/commit/8df516c4dce61b555700d092764c0f1377304798))

- Better transfers controls ([`7882d5a`](https://github.com/nark/WiredSwift/commit/7882d5a7d5f1a63cf0e8c771f58038f81f89e72b))

- Better connections managment ([`edcd074`](https://github.com/nark/WiredSwift/commit/edcd074ab00a2e687aaf58d521caa2d398e79704))

- Better window management ([`ae84126`](https://github.com/nark/WiredSwift/commit/ae841266a29be41daeb7c9713ccfc9e71ac37eca))

- Resumable download transfers + Disconnect/reconnect ([`74f3f4d`](https://github.com/nark/WiredSwift/commit/74f3f4da8979954e0615f1b566185dc05f4e395f))

- Complete server infos ([`ab4e6a1`](https://github.com/nark/WiredSwift/commit/ab4e6a193ec8de8243105cd2f7625fff5be4e059))

- Update user icon ([`890faa5`](https://github.com/nark/WiredSwift/commit/890faa5a6980158967392ec10d3afee29c0c7ad2))

- Better transfers error support ([`f86e8d9`](https://github.com/nark/WiredSwift/commit/f86e8d949df540135f582a0e867124e5873c214d))

- Better socket error support ([`c71263e`](https://github.com/nark/WiredSwift/commit/c71263e312be6456f426f53ccf0aad3ec7d1b219))

- Better emoji substitution ([`6bce5f0`](https://github.com/nark/WiredSwift/commit/6bce5f06423b2a5cf61c1e6b236bf016653d8b13))

- Update chat pref pane with emoji substitutions ([`449cfbb`](https://github.com/nark/WiredSwift/commit/449cfbbf9c52f050b9ffea3f341aa72380971d9a))

- Minimal emojis substitution support ([`3985910`](https://github.com/nark/WiredSwift/commit/39859102e2e64cda42f11314c35fea42473c40dd))

- Local notifications support ([`55c19a8`](https://github.com/nark/WiredSwift/commit/55c19a88f11faf219f08644cea7fc67ef335b72b))

- Minimal unread support ([`0c4b658`](https://github.com/nark/WiredSwift/commit/0c4b658300b3321580ccfc29df066df342254be3))

- Minimal message suppor ([`be40fc2`](https://github.com/nark/WiredSwift/commit/be40fc2197620265facfbb7e5af9ec90e7af57f5))

- Better window management ([`2ab4661`](https://github.com/nark/WiredSwift/commit/2ab46618b87212a9ff77f24322ec62f3c52c7fba))

- Minor fixes ([`bd64e0c`](https://github.com/nark/WiredSwift/commit/bd64e0c5c732e3eb8015e439b00f852f67fe2938))

- Prepare upload transfer + try deflate socket without success ([`0b51dd6`](https://github.com/nark/WiredSwift/commit/0b51dd6d689cb0accdbd563c00679680b51f56b6))

- Migrate Transfer class to Core Data ([`f6b498a`](https://github.com/nark/WiredSwift/commit/f6b498a9cc80851a0993d2650a660976a8470518))

- Better download finish ([`4e3a4b2`](https://github.com/nark/WiredSwift/commit/4e3a4b2adf25bfc34ec29b9033b646364155c7ae))

- First working transfer ([`0d2e58a`](https://github.com/nark/WiredSwift/commit/0d2e58a2b10cba76434911e298214162cd854e29))

- Working on transfers, not that easy, will take some time ([`ca073ce`](https://github.com/nark/WiredSwift/commit/ca073ce5ba9e986a27931cb14fb4dc25fb7a701d))

- Prepare transfers tableview ([`0864339`](https://github.com/nark/WiredSwift/commit/0864339532e958d072e0b70c9d307a31f3ea9590))

- Update github action setup (3) ([`9e75d89`](https://github.com/nark/WiredSwift/commit/9e75d89639080b552a90e93c5e85a031974d4238))

- Update github action setup (2) ([`4d42212`](https://github.com/nark/WiredSwift/commit/4d42212ad5cb8fe9a425ffca732e428e16747cec))

- Update github action setup ([`eef40ed`](https://github.com/nark/WiredSwift/commit/eef40edc0334d98331b8dd269b1850919a0f18b0))

- Organizing project + comments ([`c6faf6e`](https://github.com/nark/WiredSwift/commit/c6faf6e6ad6122da0d46a29846ec19035e467a2b))

- Make chat input the first responder, always ([`1f3c6a5`](https://github.com/nark/WiredSwift/commit/1f3c6a53781b248fe4ef9bb1f99c833b5e3928f7))

- Minimal bookmarks support (Core Data + Keychain) ([`38bee97`](https://github.com/nark/WiredSwift/commit/38bee97de13c9fafac4d98d93edcebf63beb27ca))

- Disconnect when closing window/tab ([`8632d67`](https://github.com/nark/WiredSwift/commit/8632d67deefa6a1616d86435831da9e21a9c45bc))

- Resources sidebar and window tabs ([`60758cd`](https://github.com/nark/WiredSwift/commit/60758cd76ce3d4288f33fd572748b7b4918575bf))

- Display status in chat user list ([`439690c`](https://github.com/nark/WiredSwift/commit/439690c8bf4fff966757941b042ca5bdad5b2a67))

- Create workflow ([`b5d034a`](https://github.com/nark/WiredSwift/commit/b5d034a91d9615ba69023fb3418cac6ebec1c937))

- Better remote connexion support ([`2c456b6`](https://github.com/nark/WiredSwift/commit/2c456b6e92b7f056d879430bf7465a3f9afb4b33))

- It works, renamed to WiredSwift ([`b44dcef`](https://github.com/nark/WiredSwift/commit/b44dcefb6f0c3ad64cc8bcb8e38921010ab044f3))

- Initial Commit ([`50d3a1e`](https://github.com/nark/WiredSwift/commit/50d3a1e7fb18686f631b53f016315f7bb249beec))


### Refactoring
- Improve WiredServer app UX and launch wired3 at login ([`584b861`](https://github.com/nark/WiredSwift/commit/584b86171f85be761ec942fcfc41d33b41f61cbf))

- Improve Linux LZ4 interop using frame format ([`14f4e82`](https://github.com/nark/WiredSwift/commit/14f4e82f703373ed8589146e8f45bc81e477c8ac))

- Replace DataCompression by SWCompression for Linux support ([`2a63c26`](https://github.com/nark/WiredSwift/commit/2a63c26478ea08d377ca021b4173e57c54ed05ba))

- Move new delegate methods to ClientInfoDelegate ([`29a6c1e`](https://github.com/nark/WiredSwift/commit/29a6c1eba4a751fc1e3b5d770d482740853c9229))

- Move RSA in separated class ([`fbab769`](https://github.com/nark/WiredSwift/commit/fbab7695e5c1569d603498c52f4d83e35d60c17b))

- Move SparkeFramework from WiredSwift to Wired ([`6856395`](https://github.com/nark/WiredSwift/commit/6856395d83497fb6255ea77b53c17b66a35479d9))

- Reduce warnings and fix Swift 5 deprecated in framework ([`5dab878`](https://github.com/nark/WiredSwift/commit/5dab878cb2f35ed973a4f321a101aced19cd53f2))

- Rename and refactor ([`4d430aa`](https://github.com/nark/WiredSwift/commit/4d430aad17f9a386e608c52548c055459fdb5299))


