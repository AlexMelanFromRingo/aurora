# Contributing to Aurora

Thanks for your interest! Aurora is an **overlay** for OpenOS — it stays 100%
compatible and adds value additively. Please keep that contract in mind.

## Ground rules

- **Don't break OpenOS compatibility.** New programs/libraries get their own
  names; never shadow stock files. Core files are patched only to fix a real
  bug, documented in [`docs/PATCHES.md`](docs/PATCHES.md) with a pristine
  `*.orig` kept under `patches/`.
- **Pure-Lua, OC-portable.** Target Lua 5.3. Use the data card when present, but
  always provide a pure-Lua fallback — nothing may *require* a specific tier.
- **Everything is tested.** Pure modules get host unit tests; anything touching
  hardware gets an in-VM check. New CLIs ship a `usr/man/<cmd>` page and `--help`.

## Dev workflow

```sh
tools/lint.sh                 # syntax-lint every Lua file (luac5.3 -p)
tools/test.sh                 # lint + host unit tests + in-VM integration
tools/test.sh --no-integration
tools/integration-net.sh      # two-VM modem/RPC test
tools/build.sh                # regenerate manifest + registry + docs/API.md
```

Run `tools/build.sh` and commit its output whenever you change a shipped file —
CI fails if the generated artifacts are stale.

### Host tests

Pure modules run under `lua5.3` against the OpenComputers shim
(`tests/shim/oc.lua`). Add a `tests/unit/test_*.lua` that uses `aurora.test`
(`describe`/`it`/`expect`) and `os.exit((t.run({quiet=true})))`.

### In-VM tests

`tools/integration.sh` stages stock OpenOS + the overlay + patches into a
throwaway instance and boots it under `ocvm`, running
`tests/integration/selftest.lua`. Add a `check(...)` there for behavior that
needs the real platform.

## Adding an opm package

Create `registry/packages/<name>/<version>/<path-mirroring-install-target>` and
a `registry/packages/<name>/package.lua` descriptor, then `tools/build.sh` to
regenerate `registry/index.json` (computes per-file sha256).

## Commit style

Conventional-ish prefixes (`feat:`, `fix:`, `docs:`, `test:`, `chore:`). Keep
each commit focused and green (`tools/test.sh` passes).

## License

By contributing you agree your work is released under the project's
[MIT license](LICENSE).
