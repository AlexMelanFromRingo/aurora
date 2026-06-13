# Changelog

All notable changes to Aurora are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`aurora.lua.parser`**: a full recursive-descent Lua 5.3 parser (AST). Fuzzed
  over all 168 stock + Aurora files — every one parses.
- **`aurora.analyze`**: scope-aware static analysis on the AST — detects reads of
  undefined names (typos) and unused locals. Wired into `alint`. Across the whole
  corpus it surfaces exactly one real latent bug (`etc/rc.d/example.lua`).
- New opm packages: `ajson`, `abase64`, `awatch`.
- **Multi-node networking test** (`tools/integration-net.sh`): boots two
  OpenOS+Aurora VMs sharing a modem network and performs a real JSON-RPC call
  between them — proving `anet` works node-to-node, not just in unit tests.

### Changed
- `aurora.transpile` rewritten on the lexer (token-based): handles multiline
  statements, multiple statements per line, never touches strings/comments, and
  parenthesizes the RHS to preserve precedence.
- The lexer now records per-token byte spans.

## [1.0.0] — 2026-06-13 — "Polaris"

First public release. A complete, tested overlay distribution for OpenOS.

### Added
- **Package manager `opm`**: install/remove/update/search/info/list/upgrade with
  semver dependency resolution, cycle/conflict detection, sha256-verified atomic
  downloads from a GitHub-hosted registry, local manifest database, and a
  reverse-dependency removal guard.
- **Networking**: `ahttp` (status-checked HTTP, JSON helpers, verified atomic
  downloads, progress, timeouts) and `anet` (modem messaging + JSON-RPC 2.0).
- **Dev toolchain / compilers**: `aurora.lua.lexer` (full Lua 5.3 tokenizer),
  `aminify` (semantics-preserving minifier), `abundle` (require-graph linker),
  `atpl` (compound-assignment transpiler), `acc` (transpile→lint→bundle→minify),
  `alint`, `atest`, `arepl`.
- **Shell & UX**: `atheme` (default/dark/mono/matrix themes), configurable
  prompt, `afetch` system summary, login hook with curated aliases.
- **Libraries**: `json`, `inspect`, `class`, `argparse`, and `aurora.*`
  (`util`, `fsx`, `hash` SHA-256/CRC-32, `semver`, `version`, `prompt`, `theme`,
  `sysinfo`, `strict`, `optimize`).
- **Installers**: self-contained online `install.lua` (checksum-verified,
  idempotent) and offline `apply.lua`; generated checksummed manifest.
- **Testing**: host unit harness with OpenComputers shim (122 tests), in-VM
  self-test under ocvm (15 checks), lint, and a minifier fuzz over all stock
  OpenOS files.

### Fixed (core patches)
- `wget`: now checks HTTP status (a 404 body is no longer saved as your file),
  writes atomically, and supports `--sha256` verification — drop-in compatible.
- `cp -u` (`lib/tools/transfer.lua`): `areEqual` no longer asserts/crashes when a
  file cannot be opened.

[1.0.0]: https://github.com/AlexMelanFromRingo/aurora/releases/tag/v1.0.0
