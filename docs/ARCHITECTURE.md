# Aurora — Architecture & Design Decisions

This document explains how Aurora is structured and *why*. For the original
design spec see [`superpowers/specs/2026-06-13-aurora-design.md`](superpowers/specs/2026-06-13-aurora-design.md).

## 1. The core bet: overlay, not fork

Aurora is deliberately **not** a new operating system. The OpenComputers
ecosystem already has from-scratch OSes; what it lacks is a *stock OpenOS that
feels modern*. So Aurora keeps the entire OpenOS substrate — `init.lua`, the
boot sequence, `package`/`require`, the component model, the shell — and adds
value **additively**:

- New programs and libraries live under their own names and never shadow stock
  files.
- Core files are touched **only** to fix a real bug, each documented in
  [`PATCHES.md`](PATCHES.md) with a behavior-preserving rationale and a pristine
  `*.orig` kept for diffing.
- The installer backs up every patched file to `*.orig-aurora` before writing.

The payoff: zero migration cost, zero compatibility risk, and a clean
"apply patches over existing files" install story.

## 2. Portability & the hardware/software split

Every library is plain Lua 5.3 and avoids hard hardware dependencies:

- `aurora.hash` uses the **data card** for SHA-256 when present and falls back to
  a correct pure-Lua implementation otherwise. The in-VM self-test verifies
  *both* paths against the FIPS-180-4 vectors.
- `ahttp`/`anet` degrade gracefully when the internet/modem card is absent
  (clear error, never a crash).

Nothing in Aurora *requires* a particular card tier.

## 3. Layering

`/lib/aurora/` is the private namespace; top-level libs (`json`, `inspect`,
`class`, `argparse`, `ahttp`, `anet`) are meant to be required by user code under
short names.

```
bin/            thin CLI front-ends; all logic lives in libraries
lib/            json, inspect, class, argparse, ahttp, anet
lib/aurora/     util, fsx, hash, semver, version, prompt, theme, sysinfo,
                strict, optimize, minify, transpile, bundle, lint, test
lib/aurora/lua/ lexer + parser + gen  (the "compiler" core; gen = AST→source)
lib/aurora/     ... analyze (scope-aware static analysis on the parser AST)
lib/aurora/opm/ resolver, db, registry, init  (the package manager)
```

Dependencies point downward only. The package manager is split so the
**pure, logic-heavy parts are isolated and unit-tested**:

- `resolver` — pure dependency resolution (semver, cycle/conflict detection).
  No I/O, so it is exhaustively host-tested.
- `db` — installed-package manifests; `root` is injectable for tests.
- `registry` — source loading, cached index fetch, multi-source merge.
- `init` — orchestration (download → verify → atomic write → record).

The same discipline applies to the toolchain: a single `lexer` underpins both
`minify` and `transpile`, and bundling is a separate static pass. Each is a small
unit with one job.

## 4. Reliability primitives

Two ideas recur throughout:

1. **Atomic writes** (`fsx.atomicWrite`): write to a temp file, then rename over
   the target. A crash or failed download never leaves a half-written or wrong
   file. The package manager, installer, theme persistence and `awget` all use
   this.
2. **Verify before trust**: downloads are checked against sha256 from the
   manifest/registry, and HTTP status codes are honored (a 404 body is an error,
   not your file — a real bug in stock `wget`).

## 5. Testing

Three layers, all driven by `tools/test.sh`:

| Layer | Mechanism | Covers |
|-------|-----------|--------|
| **Lint** | `luac5.3 -p` over every shipped + test file | syntax of all 61 shipped + test files |
| **Unit** | host `lua5.3` + `tests/shim/oc.lua` | every pure module — 112 tests, incl. round-trip exec for minify/transpile/bundle and SHA-256/CRC-32 vectors |
| **Integration** | boot stock OpenOS + Aurora under `ocvm` (`script` PTY), run `tests/integration/selftest.lua`, read `/selftest.log` | 15 checks against the *real* OpenOS environment (hardware sha256, real `component.list`, real `filesystem`/`os.setenv`) |

The OpenComputers **host shim** (`tests/shim/oc.lua`) provides `checkArg`,
`unicode`, mockable `component`/`computer`, and a host-backed `filesystem`, so
modules that target OpenOS can be exercised off-emulator in milliseconds. The
emulator step then proves the same code works on the genuine platform.

The minifier is additionally **fuzzed against all 127 stock OpenOS Lua files**:
each is minified and must recompile cleanly (it does; ~27% smaller). The
**parser is fuzzed over all 168 stock + Aurora files** (every one parses); the
**analyzer**, run across the same corpus, produces exactly one "undefined name"
finding — a genuine latent bug in stock OpenOS's `etc/rc.d/example.lua`
(`print(args)` references an unbound global) — which is the kind of
false-positive-free precision a scope-aware checker should have.

The **formatter** (`afmt`/`aurora.lua.gen`) is fuzzed over the same corpus with
the strongest possible check: for every file, `parse(format(src))` must be
structurally identical to `parse(src)` (meaning preserved) and
`format(format(src)) == format(src)` (idempotent). All 170 files pass both.

## 6. Distribution

Two install paths share one **checksummed manifest** (`install/manifest.lua`,
generated by `tools/gen-manifest.lua`):

- `install/install.lua` — online, self-contained (no Aurora deps so it runs on a
  bare system). It bootstraps `hash.lua` first, then verifies everything it
  downloads, including itself.
- `install/apply.lua` — offline, from a local repo copy.

The `opm` registry index (`registry/index.json`) is generated the same way from
`registry/packages/` by `tools/build-registry.lua`. Both generators are run by
`tools/build.sh` and their outputs are committed so installs work straight from
GitHub.

## 7. Trade-offs we accepted

- **The transpiler is line-oriented** (one statement per line for the sugar).
  A full Lua parser would lift that restriction but is far more code for a
  marginal gain; the documented scope covers the common case and is fully
  tested.
- **The minifier does not rename locals.** Comment/whitespace removal is the
  bulk of the win and is provably safe; renaming risks correctness for a few
  extra bytes.
- **LAN/RPC is validated across two real VMs.** `tools/integration-net.sh` boots
  a server and a client OpenOS+Aurora instance that share a modem network (ocvm
  bridges modems over a localhost socket hub) and performs a genuine JSON-RPC
  call between them. The wire protocol and RPC envelopes are additionally pure
  unit-tested.
