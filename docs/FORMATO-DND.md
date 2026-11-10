# The `.dnd` file format (schema 3)

A `.dnd` file is a **UTF-8 JSON** document describing one character. It is what dndsheet reads and writes, and it is meant to be
easy to generate from other tools (the web character creator does exactly that).

- Machine-readable definition: [`format/dnd.schema.json`](../format/dnd.schema.json) (JSON Schema, draft 2020-12).
- Test vectors for the calculations: [`format/vectors/`](../format/vectors/).
- Keys are in Spanish, lowercase, without accents (`vinculos`, not `vínculos`). They are **never translated**, so a character works in any UI language.
- **Only input data is stored.** Modifiers, saves, skills, initiative, passive Perception, spell DC… are calculated by the reader
  (see [Calculations](#calculations)). The exception is `ajustes` (manual overrides), where `null` means "calculate".
- **Unknown keys must be preserved** when you rewrite a file.
- Long texts are strings with `\n`. Lists are JSON arrays (`[]` when empty, never `{}`).
- `meta.schema` is the format version. **Current: 3.**

## Fields

| Key | Type | Notes |
|---|---|---|
| `meta` | object | `schema` (integer, **required**), `app` (`"dndsheet"`), `creado`, `guardado` (Unix time) |
| `nombre`, `jugador`, `raza`, `alineamiento`, `trasfondo` | string | character name, player, species, alignment, background |
| `clase_nivel` | string | free text: `"Rogue 5"`, `"Fighter 3 / Wizard 2"` |
| `nivel` | integer 1–20 | **total** level; drives the proficiency bonus |
| `experiencia` | integer ≥ 0 | |
| `atributos` | object | `fue`, `des`, `con`, `int`, `sab`, `car` (STR, DEX, CON, INT, WIS, CHA): integers 1–30 |
| `salvaciones` | object | same six keys: boolean, proficient in that saving throw |
| `habilidades` | object | 18 skills (below): `0` none · `1` proficient · `2` expertise |
| `inspiracion` | integer 0–99 | |
| `ca` | integer ≥ 0 | armor class |
| `velocidad` | string | free text: `"30 ft"`, `"9 m / fly 18 m"` |
| `hp` | object | `maximo`, `actual`, `temporal` (integers ≥ 0) |
| `dados_golpe` | object | `total` (string `"5d8"`, `"3d10+2d8"`), `restantes` (integer ≥ 0) |
| `muerte` | object | `exitos`, `fallos`: 0–3 |
| `ajustes` | object | manual overrides, each integer or `null`: `competencia`, `iniciativa`, `percepcion_pasiva`, `cd_conjuros`, `ataque_conjuros` |
| `ataques` | array | `{ nombre, bonus, dano, ref? }` — `bonus` and `dano` are **text** (`"+5"`, `"1d8+3 slashing"`); `ref` optional, a compendium id (`"weapon.quarterstaff"`) |
| `ataques_notas` | string | free area under the attacks table |
| `monedas` | object | `pc` copper, `pp` silver, `pe` electrum, `po` gold, `ppt` platinum (integers ≥ 0) |
| `equipo`, `otras_competencias`, `tesoro` | string | equipment, other proficiencies & languages, treasure |
| `rasgos` | string | features & traits (free text) |
| `rasgos_ref` | array | `{ ref, nombre, nota }`: rules added from the compendium (`ref` required, non-empty) |
| `personalidad` | object | `rasgos`, `ideales`, `vinculos`, `defectos` (strings) |
| `fisico` | object | `edad`, `altura`, `peso`, `ojos`, `piel`, `pelo` (strings) |
| `apariencia`, `aliados`, `organizacion`, `rasgos_adicionales`, `historia`, `notas` | string | |
| `conjuros` | object | `clase` (string), `aptitud` (`"int"`, `"sab"`, `"car"` or `null`), `niveles` |
| `conjuros.niveles` | object | keys `"0"`…`"9"`. `"0"` (cantrips): `{ lista }`. `"1"`…`"9"`: `{ total, usados, lista }` — slots (0–99, `usados` ≤ `total`) |
| `conjuros.niveles.N.lista` | array | cantrips: `{ nombre, ref? }`; leveled spells: `{ nombre, preparado (boolean), ref? }` |

Skills (key → ability): `acrobacias` DEX · `trato_animales` WIS · `arcanos` INT · `atletismo` STR · `engano` CHA · `historia` INT ·
`perspicacia` WIS · `intimidacion` CHA · `investigacion` INT · `medicina` WIS · `naturaleza` INT · `percepcion` WIS ·
`interpretacion` CHA · `persuasion` CHA · `religion` INT · `juego_manos` DEX · `sigilo` DEX · `supervivencia` WIS.

A complete example is [`templates/nuevo.dnd`](../templates/nuevo.dnd) (an empty character).

## Calculations

Reference implementation: `dndsheet/rules.lua`. All numbers are integers; `mod(x) = floor((x - 10) / 2)`.

| Value | Formula |
|---|---|
| proficiency | `ajustes.competencia` if set, else `2 + floor((nivel - 1) / 4)` |
| saving throw | `mod(atributo) + (proficiency if salvaciones[ab])` |
| skill | `mod(ability of the skill) + proficiency × rank` (rank 0/1/2) |
| initiative | `ajustes.iniciativa` if set, else `mod(des)` |
| passive Perception | `ajustes.percepcion_pasiva` if set, else `10 + skill(percepcion)` |
| spell save DC | `ajustes.cd_conjuros` if set; else, if `aptitud` is set, `8 + proficiency + mod(aptitud)`; else none |
| spell attack | `ajustes.ataque_conjuros` if set; else, if `aptitud` is set, `proficiency + mod(aptitud)`; else none |
| weapon attack | Finesse → the better of STR/DEX; ranged → DEX; otherwise STR. Bonus = that mod (+ proficiency if proficient); damage = dice + mod (omitted when 0) |

The test vectors in `format/vectors/` encode these rules (input → expected values). Both the Lua plugin and the web creator run them.

## Reading a file robustly (normalization)

Files can be incomplete (hand-edited) or older. A reader should, in this order:

1. If `meta.schema` is **greater than 3**, open the file read-only and never overwrite it (a newer app wrote it).
2. **Migrate** to the current schema (below).
3. **Normalize**: fill every missing key with its default, force types (numbers become integers, text fields become strings, a
   number in a text field becomes its text), clamp ranges (`nivel` 1–20, `atributos` 1–30, `habilidades` ∈ {0,1,2}, `muerte` 0–3,
   `inspiracion` 0–99, `usados` ≤ `total`…), drop list items that are not objects, drop `rasgos_ref` items without a text `ref`,
   drop a `ref` that is not a non-empty string, and keep unknown keys.

The defaults are the values of `templates/nuevo.dnd`.

## Versions and migrations

| `schema` | Change |
|---|---|
| 1 | first version; `inspiracion` was a boolean |
| 2 | `inspiracion` is an integer 0–99 (`true` → 1, `false`/missing → 0) |
| 3 | added `rasgos_ref` (`[]` by default) and optional `ref` in `ataques` and spell lists |

Each migration only adds or converts; nothing is removed. An older app opens a newer file read-only.

## Validating a file

`dnd.schema.json` describes a **complete, schema-3** file (what an app should write). Any JSON Schema 2020-12 validator works, for
example [Ajv](https://ajv.js.org/) (`ajv/dist/2020`) or Python `jsonschema` (`Draft202012Validator`). Migrate and normalize older or partial
files first. The repository's `tools/formato/validar.py` does this with the plugin's own Lua code.

## Compendium ids (`ref`)

`ref` ids come from the SRD 5.2.1 data in `compendium/srd521/<language>/*.json`: `spell.fireball`, `weapon.quarterstaff`,
`feat.alert`, `species.elf.keen-senses`, `subclass.evoker`, `monk.martial-arts`… A `ref` is only a pointer: the sheet keeps working
(and shows the stored `nombre`) if the entry is missing. Your own entries (JSON files next to your characters) use the same ids.
