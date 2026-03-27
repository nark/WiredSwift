## Summary

<!-- What does this PR change? -->

## Why

<!-- Why is this change needed? Bug, feature request, refactor goal, etc. -->

## Type of change

- [ ] `feat` — new feature
- [ ] `fix` — bug fix
- [ ] `refactor` — refactoring, no behavior change
- [ ] `perf` — performance improvement
- [ ] `test` — tests only
- [ ] `docs` — documentation only
- [ ] `chore` / `ci` — tooling, build, CI

## Behavioral impact

<!-- User-visible/API/protocol impact. Write "none" if no impact. -->

- [ ] Breaking change
- [ ] Security-sensitive change
- [ ] Database/schema/data migration required

## Validation

<!-- Paste key outputs or a short summary of what you ran locally. -->

```bash
swift build --product wired3
swift test
swiftlint lint
```

## Checklist

- [ ] Tests added/updated when behavior changed
- [ ] Docs/README/CHANGELOG updated when needed
- [ ] `swift build` passes locally
- [ ] `swift test` passes locally
- [ ] SwiftLint reports no new errors (`swiftlint lint`)
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): summary`)
- [ ] No new `swiftlint:disable` without a `TODO:` comment explaining why

## Related issues

<!-- Closes #123 / Relates to #456 -->
