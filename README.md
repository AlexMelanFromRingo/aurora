# Aurora

[![ci](https://github.com/AlexMelanFromRingo/aurora/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexMelanFromRingo/aurora/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/AlexMelanFromRingo/aurora?sort=semver)](https://github.com/AlexMelanFromRingo/aurora/releases)
[![license](https://img.shields.io/github/license/AlexMelanFromRingo/aurora)](LICENSE)
![lua](https://img.shields.io/badge/Lua-5.3-blue)
[![docs](https://img.shields.io/badge/docs-pages-brightgreen)](https://alexmelanfromringo.github.io/aurora/)

**A modern, batteries-included overlay distribution for OpenComputers OpenOS.**

Aurora takes a stock [OpenOS](https://ocdoc.cil.li/) install and layers on a real
package manager, a developer toolchain ("compilers"), networking libraries, shell
themes, and security + reliability fixes — **without breaking OpenOS
compatibility**. Anything that runs on stock OpenOS keeps running; Aurora just
makes the system far more capable and pleasant to use.

It installs *on top of* an existing OpenOS (as an overlay + a couple of targeted
core patches), so there is nothing to re-learn and nothing to lose.

📖 **Documentation site:** <https://alexmelanfromringo.github.io/aurora/> ·
[API reference](docs/API.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Patches](docs/PATCHES.md)

---

## Highlights

| Area | What you get |
|------|--------------|
| 📦 **Packages** | `opm` — install/remove/update/search with semver dependency resolution and **sha256-verified, atomic** downloads from a GitHub-hosted registry |
| 🛠️ **Dev toolchain** | `acc` (compile = transpile→lint→bundle→minify), `aminify` (Lua-aware minifier), `abundle` (require-graph linker), `atpl` (compound-assignment transpiler), `alint` (**scope-aware** linter on a real Lua AST), `afmt` (AST-based code formatter), `adoc` (API-doc generator), `atest`, `arepl` |
| 🌐 **Networking** | `ahttp` (status-checked HTTP with JSON + verified downloads), `anet` (modem messaging + JSON-RPC 2.0) |
| 🎨 **Shell & UX** | `atheme` color themes, configurable prompt, `afetch` system summary, curated aliases |
| 🔒 **Security & reliability** | patched `wget` (checks HTTP status, atomic, `--sha256`), `cp` crash fix, `strict` global guard, safe-remove |
| 🧰 **Libraries** | `json`, `inspect`, `class`, `argparse`, `aurora.hash` (SHA-256/CRC-32), `aurora.semver`, `aurora.fsx`, `aurora.util`, `aurora.optimize` |

Every shipped Lua file is syntax-linted, every pure module is unit-tested on the
host (**112 tests**), and the whole distribution is booted and self-tested inside
a real OpenOS under an emulator (**15 in-VM checks**, including the data card's
hardware SHA-256).

---

## Install

### Online (recommended)

On any OpenOS machine with an internet card:

```sh
wget https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main/install/install.lua /tmp/ai.lua
/tmp/ai.lua
```

The installer fetches a checksummed manifest, **verifies every file's sha256**,
writes atomically, backs up any core file it patches (`*.orig-aurora`), and wires
a guarded login hook. It is idempotent — safe to re-run. Open a new shell or
reboot afterwards.

### Offline (patch overlay)

Clone or copy this repository onto a disk the machine can see, then:

```sh
/mnt/<disk>/install/apply.lua /mnt/<disk>
```

This applies the same overlay + patches with no network, verifying checksums
from the local copy.

---

## Quick tour

```sh
afetch                         # system summary
atheme set matrix              # switch shell theme (persists)

opm update                     # refresh package lists
opm install acowsay            # install a package (sha256-verified)
acowsay "hello from Aurora"

arepl                          # nicer Lua REPL (multiline, pretty-print)

# compile a multi-file project into one minified, linted file:
acc src/main.lua -o build/app.lua

# safer downloads:
awget --sha256=<hex> https://host/file.lua /usr/bin/file.lua
```

Every command has a man page (`man opm`, `man acc`, …) and `--help`.

---

## Using the libraries in your programs

```lua
local json   = require("json")
local ahttp  = require("ahttp")
local class  = require("class")

local res = ahttp.getJSON("https://api.example.com/status")
print(json.encode(res, {pretty = true}))

local Animal = class("Animal")
function Animal:init(name) self.name = name end
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full library map.

---

## Repository layout

```
overlay/     files laid over OpenOS (bin/, lib/, etc/, usr/man/)
patches/     patched core files + pristine *.orig + rationale
install/     install.lua (online), apply.lua (offline), manifest.lua
registry/    opm package registry (index.json + packages/)
tools/       build.sh, test.sh, lint.sh, integration.sh, generators
tests/       host unit tests + OpenComputers shim + in-VM self-test
docs/        ARCHITECTURE.md, PATCHES.md, design spec
```

---

## Developing & testing

```sh
tools/lint.sh            # syntax-lint every Lua file (luac5.3 -p)
tools/test.sh            # lint + host unit tests + in-VM integration
tools/test.sh --no-integration   # skip the emulator step
tools/build.sh           # regenerate manifest + registry after edits
```

Host unit tests run pure-Lua modules under `lua5.3` against an OpenComputers
shim. The integration step stages stock OpenOS + Aurora into a throwaway
instance and boots it under [`ocvm`](https://github.com/payonel/ocvm), running an
in-system self-test. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#testing).

---

## Compatibility

- OpenComputers 1.7+, OpenOS, Lua 5.3.
- The data card (SHA-256, deflate) is used when present, with pure-Lua
  fallbacks — nothing *requires* a particular tier.
- Aurora never replaces the OpenOS boot path, `require`, or component model.

## License

MIT — see [LICENSE](LICENSE).
