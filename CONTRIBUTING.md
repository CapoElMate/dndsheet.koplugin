# Contributing

Thanks for helping. This is a small hobby project; keep changes small and focused.

## Rules for every contribution
- **No text from the Player's Handbook** or any book other than the SRD 5.2.1 (pull requests with such text are closed).
  Rules content that is not in the SRD goes in *your own entries*, not in this repository.
- Do not use Wizards of the Coast logos or artwork. Do not use "D&D" as a product name.
- No personal data in fixtures or examples (use invented names).
- Commits: no AI co-author trailers or similar attribution lines.

## Running the checks
Requirements: `luajit`, `luacheck`, `lua-cjson` (Debian/Ubuntu: `sudo apt install luajit lua-check lua-cjson`).

```sh
./dev.sh          # luacheck + pure logic tests (luajit tests/run.lua)
./empaquetar.sh   # builds dndsheet-<version>.zip + SHA256SUMS
```

The UI specs (`tests/spec/`, in the development repository) need a compiled KOReader checkout and run locally only;
CI runs luacheck and the pure tests.

## Style
- Lua 5.1 / LuaJIT. Four spaces. `snake_case` for variables, `CamelCase` for classes. Every `local`.
- No file longer than ~400 lines. Pure modules (`rules`, `schema`, `dice`, `compendium`) must not require UI code.
- Every user-visible string goes through `T("key")` and is defined in `dndsheet/lang/en.lua` (reference) and `es.lua`.
- Every `.lua` file starts with `-- SPDX-License-Identifier: AGPL-3.0-or-later` (a test checks it).
- Do not invent KOReader APIs: point to the file and line in KOReader's source.

## Translations
See [`docs/TRADUCIR.md`](docs/TRADUCIR.md): one new file in `dndsheet/lang/`.

## Reporting bugs
Use the issue templates and include the dndsheet and KOReader versions, the device and `crash.log` lines with `dndsheet`.
