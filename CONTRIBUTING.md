# Contributing

Thanks for looking. The most valuable contribution is a **real SiriKit pattern this gets
wrong** — detection is regex-based and line-oriented, so unusual code shapes are where it
fails. A three-line snippet in an issue is enough.

## Getting set up

```bash
swift build && swift test
```

There is a sample SiriKit app at `Examples/LegacySiriKitApp` that triggers every rule.

## Where things live

| To change | Edit |
| --- | --- |
| What counts as a SiriKit pattern | `PatternDetector.swift` — one regex per `RuleID` |
| The migration advice shown for a pattern | `CommonPatterns.swift` — the single source of truth |
| What the patcher is allowed to rewrite | `PatchingRules.swift` |
| Which files are in scope | `FileWalker.swift` |

## Two invariants the tests enforce

1. **Every `RuleID` has a migration.** Add a detection rule without adding a
   `CommonPatterns` entry and `CommonPatternsTests` fails — otherwise findings would be
   detected and then silently dropped from `suggest`.
2. **Automatic patching rules map only to `.autoPatchable` migrations.** The patcher must
   never write a change the guide describes as needing manual review.

## Adding a patching rule

The bar is high, and deliberately so. An automatic rule must be **line-local and
semantics-preserving**: the line matches, it is replaced or deleted, and nothing outside
that line changes meaning.

Things that have gone wrong here before, all of which passed `swiftc -parse`:

- Rewriting SiriKit code that lived inside a **string literal**.
- Swapping `import Intents` while the file still used `IN…` symbols.
- Deleting `isEligibleForHandoff = false`, which reverted the property to its default and
  flipped the behaviour — and isn't part of this migration anyway.

If a rewrite cannot be verified by looking at one line, it belongs in `.proposalOnly`.

## Validation is weaker than it looks

`swiftc -parse` checks **syntax only**. It does not catch type errors, missing members, or
unresolved imports. Never treat "validation passed" as "this compiles".

## Commits

Explain *why* in the body, not just what. If a change fixes something subtle, say what the
failure looked like — several comments in this codebase exist because the reason wasn't
obvious later.
