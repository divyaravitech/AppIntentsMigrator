# Contributing

The most useful thing you can file is a real SiriKit pattern this gets wrong. Detection is
regex-based and line-oriented, so unusual code shapes are where it fails. A three-line
snippet is enough.

## Setup

```bash
swift build && swift test
```

`Examples/LegacySiriKitApp` triggers every rule if you need something to run against.

## Where things live

| To change | Edit |
| --- | --- |
| What counts as a SiriKit pattern | `PatternDetector.swift` |
| The advice shown for a pattern | `CommonPatterns.swift` |
| What the patcher may rewrite | `PatchingRules.swift` |
| Which files are in scope | `FileWalker.swift` |

## Two invariants the tests enforce

1. Every `RuleID` has a migration in `CommonPatterns`. Without one, findings would be
   detected and then dropped from `suggest`.
2. Automatic patching rules map only to `.autoPatchable` migrations, so the patcher never
   writes a change the guide calls manual.

## Adding a patching rule

An automatic rule has to be line-local and preserve semantics: the line matches, it's
replaced or deleted, and nothing outside it changes meaning. If you can't verify a rewrite
by looking at one line, it belongs in `.proposalOnly`.

Things that went wrong here before, all of which passed `swiftc -parse`:

- Rewriting SiriKit code that was inside a string literal.
- Swapping `import Intents` while the file still used `IN…` symbols.
- Deleting `isEligibleForHandoff = false`, which reverted the property to its default and
  flipped the behaviour. It isn't part of this migration anyway.

## Validation is weaker than it looks

`swiftc -parse` checks syntax only. It doesn't catch type errors, missing members or
unresolved imports, so "validation passed" never means "this compiles".

## Commits

Say why in the body, not just what. If a fix is subtle, describe what the failure looked
like.
