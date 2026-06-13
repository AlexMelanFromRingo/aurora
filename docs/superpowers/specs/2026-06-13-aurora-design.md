# Aurora — Design & Architecture Spec

**Date:** 2026-06-13
**Status:** approved (overlay direction, broad v1, public GH repo, full autonomy)
**One-liner:** A modern, batteries-included **overlay distribution** for OpenComputers **OpenOS**.

## 1. Goal & non-goals

Aurora upgrades a stock OpenOS install with modern programs, libraries, a real
package manager, a developer toolchain ("compilers"), shell/UX improvements, and
security + reliability + performance patches — **without breaking OpenOS
compatibility**. Any program that runs on stock OpenOS keeps running.

**Non-goals:**

- Not a fork or a new kernel. We do not replace `init.lua`, the boot sequence,
  `package`/`require`, the scheduler, or the component model. (The sibling `OCOS`
  project already explores a from-scratch capability OS; Aurora is deliberately
  the opposite bet: stay on OpenOS, make it pleasant and powerful.)
- No incompatible reorganization of `/bin`, `/lib`, `/etc`.

## 2. Design principles

1. **Additive, not destructive.** New files live under their own names. Core
   files are only *patched* when fixing a real bug, and the patch is documented
   in `docs/PATCHES.md` with a stock-behavior-preserving rationale. Stock files
   we replace are kept verbatim under `patches/<name>.orig` for diffing.
2. **Pure-Lua, OC-portable.** Every library runs on Lua 5.3. Hardware
   acceleration (the `data` card: sha256, deflate) is used when present, with a
   pure-Lua fallback so nothing *requires* a specific tier.
3. **Testable on the host.** Pure-Lua modules are unit-tested with the host
   `lua5.3` against an OpenComputers shim (`tests/shim/oc.lua`). Anything that
   touches real components is covered by an in-emulator self-test booted under
   `ocvm`. Everything is syntax-linted with `luac5.3 -p`.
4. **Self-documenting.** Every user-facing command ships a `usr/man/<cmd>` page
   and `--help`. Libraries carry doc-comments.
5. **Idempotent install.** Re-running the installer converges; never corrupts a
   half-installed state. Downloads are checksum-verified and written atomically.

## 3. Repository layout

```
aurora/
├── overlay/                 # files laid over an OpenOS rootfs (the product)
│   ├── bin/                 # new commands (opm, abundle, aminify, atest, alint, arepl, ...)
│   ├── lib/                 # new libraries (aurora/*, json, class, inspect, argparse, ahttp, anet, ...)
│   ├── etc/                 # default config (aurora.cfg, themes, opm sources)
│   └── usr/man/             # man pages for every new command
├── patches/                 # patched core files + *.orig originals + PATCHES rationale
├── install/                 # in-VM installer (install.lua) + host bootstrap
├── registry/                # opm package registry (index.lua + packages/*)
├── tools/                   # host-side: build.sh, test.sh (unit+integration), lint.sh, pack.lua
├── tests/
│   ├── shim/oc.lua          # OpenComputers API shim for host lua5.3
│   ├── unit/*.lua           # host unit tests (fast)
│   └── integration/selftest.lua  # in-VM self-test (boots under ocvm)
├── docs/                    # ARCHITECTURE.md, PATCHES.md, design spec, per-feature docs
├── .github/workflows/ci.yml # lint + host unit tests on push
├── README.md  CHANGELOG.md  LICENSE
```

`/lib/aurora/` is the namespace root for Aurora internals so `require("aurora.x")`
never collides with stock or third-party modules. Top-level convenience libs
(`json`, `class`, `inspect`, `argparse`, `ahttp`, `anet`) are placed in `/lib`
directly because they are meant to be required by user programs by short name.

## 4. Components (v1, all four focus areas)

### 4.1 Core libraries (`overlay/lib`)
- `json.lua` — strict JSON encode/decode (numbers, escapes, UTF-8), no globals.
- `class.lua` — minimal single-inheritance OOP (`class("Name", Base)`).
- `inspect.lua` — cycle-safe pretty-printer for tables/values.
- `argparse.lua` — declarative CLI parser (flags, options, positionals, help).
- `aurora/version.lua`, `aurora/util.lua`, `aurora/fsx.lua` (path/file helpers:
  atomic write, read-all, mkdirs), `aurora/hash.lua` (sha256: data-card or
  pure-Lua), `aurora/semver.lua`.

### 4.2 Ecosystem, packages & networking
- `ahttp.lua` — ergonomic HTTP client over the internet card: `get/post`,
  returns `{status, headers, body}`; streaming download with progress; honors
  redirects; timeouts.
- `anet.lua` — LAN messaging over the modem: addressed datagrams, `send/recv`,
  broadcast, plus a tiny JSON-RPC 2.0 layer (`rpc.server`, `rpc.call`).
- `opm` (`bin/opm.lua` + `lib/aurora/opm/*`) — the package manager:
  `opm update | search | info | install | remove | list | upgrade`.
  Registry is a Lua/JSON index fetched over HTTP from the GitHub repo (raw).
  Each package entry has files + per-file sha256. Install downloads to a temp
  dir, verifies checksums, then atomically moves into place and records a local
  manifest at `/etc/opm/installed/<pkg>.lua`. Removal uses the manifest.

### 4.3 Dev toolchain & "compilers"
- `abundle` — resolve a project's `require` graph and emit a single self-
  contained Lua file (modules registered into `package.preload`). Entry +
  followed deps; detects cycles; `--minify` pipes through aminify.
- `aminify` — Lua source minifier: a real Lua 5.3 lexer that strips
  comments/whitespace and collapses tokens safely (string/number/identifier
  aware; never merges tokens that would change meaning). Optional local-name
  shortening is **off by default** (safety first).
- `aluac` / `acc` — "compiler" front-end: a small **transpiler** for a sugar
  dialect ("AuroraScript-lite") → Lua. Supported sugar (each independently
  tested at the lexer level): compound assignment `+= -= *= /= ..=`,
  `fn(a,b) => expr` arrow lambdas, and `a ?? b` nil-coalescing. Emits clean Lua
  and (via abundle) a runnable file. Deliberately small and fully tested rather
  than a sprawling language.
- `atest` — xUnit-style test framework usable in-VM and on host:
  `describe/it/expect`, returns nonzero on failure; powers the self-test.
- `alint` — linter: load()-based syntax check + static checks (writes to
  globals, undefined-global reads against a known-symbol set, unused locals).
- `arepl` — improved interactive Lua REPL: multiline continuation, persistent
  history, pretty-printed results via inspect, `=expr` shorthand.

### 4.4 Shell, UX & editor
- `aurora/prompt.lua` + `etc/aurora/prompt.cfg` — configurable colored prompt
  (cwd, hostname, last-exit, optional truncation), installed via `.shrc`.
- `aurora/theme.lua` + `etc/aurora/themes/*` — color themes for ls/prompt.
- `acomplete` — Tab-completion enhancements (commands from PATH, file paths,
  opm subcommands) hooked into the shell's existing hint mechanism.
- `als` — colorized `ls` wrapper (type/extension colors), opt-in alias.
- `.shrc` additions (non-destructive: appended, guarded by markers) to load
  prompt, aliases, completion.

### 4.5 Security, reliability & optimization (patches)
- **wget patch** — verified, atomic downloads: `--sha256=<hex>` integrity check,
  download to `tmp` then rename (no partial files, no clobber races), correct
  HTTP status handling (stock wget ignores non-200), real error propagation.
  Stock invocation unchanged when no new flag is passed.
- **cp/transfer review** — audit `lib/tools/transfer.lua` for the copy-failure
  edge cases; patch only if a real defect is found, else document as reviewed.
- `aurora/hardening.lua` — opt-in `set -e`-style strict mode for scripts and a
  safe-rm guard library.
- **require cache warmer / `aurora/optimize.lua`** — preload hot modules; a
  `bufread` helper for large-file reads; micro-optimizations packaged as a lib,
  not forced onto core.

## 5. Data flow — package install (representative)

```
opm install foo
  └─ load /etc/opm/sources.lua  (registry base URL)
  └─ ahttp.get(<base>/index.lua) → parse → resolve deps (semver)
  └─ for each file: ahttp download → tmp → hash.sha256 == manifest? 
  └─ atomic move tmp → target; write /etc/opm/installed/foo.lua manifest
  └─ run optional post-install hook
```

## 6. Testing strategy

| Layer | Tool | What |
|---|---|---|
| Lint | `luac5.3 -p` over all `.lua` | syntax of every shipped + test file |
| Unit | host `lua5.3` + `tests/shim/oc.lua` | pure-Lua libs (json, semver, hash, minify, transpiler lexer, argparse, inspect, opm resolver) |
| Integration | `ocvm` self-test (`script -qc`) | boot OpenOS+overlay, run `atest` suite, write `/selftest.log`, shutdown; assert no FAIL |

`tools/test.sh` runs lint → unit → integration and is the canonical signal.
A throwaway emulator instance is built by copying stock `openos` + applying the
overlay, so tests never mutate the lab's pristine tree.

## 7. Install & distribution

1. **Bootstrap (online):** `wget <raw>/install/install.lua /tmp/i.lua && /tmp/i.lua`
   — fetches the registry, installs `aurora-base` meta-package, patches wget,
   wires `.shrc`, reboots. Idempotent.
2. **Overlay (offline):** `tools/build.sh` produces `dist/aurora-overlay.tar`-like
   directory + an in-VM `apply.lua` that copies overlay files and applies patches
   over an existing OpenOS, keeping `*.orig` backups.
3. **opm** thereafter manages individual packages from the GitHub-hosted registry.

## 8. Risks & mitigations

- *ocvm needs a real TTY:* use `script -qc` (proven by OCOS) for integration.
- *Internet/registry flakiness in tests:* unit tests mock HTTP; integration
  test uses a local file:// or bundled registry, not the network.
- *Scope:* v1 ships every focus area but each feature is small, isolated, and
  individually tested; depth can grow in later minor releases.

## 9. Milestones (autonomous execution order)

1. Test harness + shim + CI skeleton.
2. Core libs (json, class, inspect, argparse, util, fsx, hash, semver) + unit tests.
3. Networking (ahttp, anet) + unit tests (mocked).
4. opm + registry + unit tests (resolver/manifest) .
5. Dev toolchain (atest, alint, aminify, abundle, transpiler, arepl) + tests.
6. Shell/UX (prompt, theme, completion, als, .shrc wiring).
7. Security/perf patches (wget, transfer review, hardening, optimize).
8. Installer + offline overlay applier + ocvm integration self-test.
9. Docs (README, ARCHITECTURE, PATCHES, CHANGELOG, man pages) + CI.
10. Create public GH repo, topics, description, push.
```
