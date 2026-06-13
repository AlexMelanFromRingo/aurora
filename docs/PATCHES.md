# Aurora — Patches & Improvements

Aurora is overwhelmingly **additive**: new programs and libraries that never
shadow stock files. Only two stock OpenOS files are patched, each to fix a real
defect. Pristine originals are kept as `patches/**/*.orig`, and the installer
backs up the live file to `*.orig-aurora` before replacing it.

---

## Core patches

### 1. `bin/wget.lua` — honor HTTP status, atomic writes, integrity

**Problem (stock):** OpenOS `wget` streams the response body straight to the
final file and **never inspects the HTTP status code**. A `404`/`500` error page
is happily saved *as if it were your file*. The write is also non-atomic, so an
interrupted transfer leaves a partial/garbage file at the destination.

**Fix:** the patched `wget` routes through `ahttp.download`, which:
- treats any non-2xx status as a failure (your file is never an error page),
- downloads to a temp file and renames into place (atomic; no partial files),
- supports `--sha256=HEX` to verify integrity.

The CLI, defaults, filename inference and **function return values are
unchanged**, so existing scripts and `require("wget")`-style callers keep
working. (A new command, `awget`, offers the same engine with a cleaner flag
set.)

*Files:* `patches/bin/wget.lua` (+ `.orig`).

### 2. `lib/tools/transfer.lua` — stop `cp -u` from crashing

**Problem (stock):** the `areEqual` helper used by `cp -u`/`mv -u` opens both
files and ends with `assert(f1 and f2, …)`. If the second file can't be opened,
the assert **throws and aborts the whole copy** instead of treating the files as
different.

**Fix:** an unopenable file now simply means "not equal", so the copy proceeds.
The change is minimal and behavior-preserving for every success path (see the
diff against `transfer.lua.orig`).

*Files:* `patches/lib/tools/transfer.lua` (+ `.orig`).

### 3. `etc/profile.lua` — login hook (added by the installer)

The installer appends a guarded, idempotent block:

```lua
-- >>> aurora >>>
pcall(dofile, "/etc/aurora/login.lua")
-- <<< aurora <<<
```

`login.lua` runs in-process (so `os.setenv`/aliases persist), applies the
remembered color theme and adds convenience aliases. It is fully defensive — a
failure there can never block login. The original `profile.lua` is backed up to
`profile.lua.orig-aurora`.

---

## New programs (overlay, non-destructive)

| Command | Purpose |
|---------|---------|
| `opm` | package manager (install/remove/update/search/info/list/upgrade) |
| `awget` | safe downloader (status-checked, atomic, `--sha256`) |
| `acc` | compiler: transpile → lint → bundle → minify |
| `aminify` | Lua-aware minifier |
| `abundle` | require-graph linker → single file |
| `atpl` | compound-assignment transpiler |
| `alint` | syntax + implicit-global linter |
| `atest` | xUnit test runner |
| `arepl` | multiline, pretty-printing Lua REPL |
| `atheme` | shell color-theme manager |
| `afetch` | neofetch-style system summary |

## New libraries (overlay)

`json`, `inspect`, `class`, `argparse`, `ahttp`, `anet`, and the `aurora.*`
namespace: `util`, `fsx`, `hash`, `semver`, `version`, `prompt`, `theme`,
`sysinfo`, `strict`, `optimize`, `minify`, `transpile`, `bundle`, `lint`, `test`,
`lua.lexer`, and the `opm` package (`resolver`, `db`, `registry`).

## Optimizations

- `aurora.optimize.warm` preloads hot modules; `slurp` reads files in large
  blocks (fewer component round-trips); `memoize` caches pure functions.
- Atomic-write helpers avoid redundant re-reads and partial states.

## Security/hardening

- sha256 verification on every package and download.
- HTTP status enforcement (see wget patch).
- `aurora.strict`: undeclared-global guard for scripts and `safe_remove` that
  refuses to recursively delete protected system paths without `force`.
