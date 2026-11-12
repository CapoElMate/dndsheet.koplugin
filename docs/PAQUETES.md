# Content packs and the catalog

dndsheet ships only the SRD 5.2.1. Anything else is **content you add yourself**, in a *pack*, and a small *catalog* tells you what exists.

## Pack format

A pack is the same JSON as the plugin's own entries (`documents/dnd/compendio/*.json`): lists by type, plus optional `package` (a name; the plugin ignores it).

```json
{
  "package": "My pack",
  "subclasses": [
    {
      "id": "custom.subclass.order-of-the-lantern", "class_id": "fighter", "name": "Order of the Lantern",
      "features": [
        { "id": "custom.subclass.order-of-the-lantern.glow", "name": "Glow", "level": 3, "text": "Your own notes.",
          "efectos": [ { "tipo": "bono", "a": "ca", "valor": 1 } ] }
      ]
    }
  ]
}
```

Types: `subclasses`, `species`, `feats`, `spells`, `weapons` (read by the plugin) and `backgrounds` (`id`, `name`, `text`; used by the web creator only). Each entry may have an `efectos` list, and so may each feature (`features`/`traits`); a feature's effects apply from its `level`.

## Effects (`efectos`)

Effects change the numbers on the sheet. They **add up**. Incomplete or unknown effects are ignored.

| `tipo` | Fields | Effect |
|---|---|---|
| `competencia` | `categoria` (`habilidad`, `salvacion`, `arma`, `armadura`, `herramienta`), `valor` | proficiency (skill and save keys are those of the `.dnd`: `sigilo`, `fue`…) |
| `pericia` | `habilidad` | expertise (double proficiency) |
| `bono` | `a` (`ca`, `ataque`, `dano`, `iniciativa`, `velocidad`, `pg_por_nivel`), `valor` (integer) | numeric bonus |
| `sentido` | `sentido`, `alcance` (feet) | sense; the largest range wins |
| `resistencia` | `dano` | damage resistance |
| `conjuro_preparado` | `conjuro` (id or name) | always-prepared spell |
| `recurso` | `nombre`, `usos` (integer) or `formula` (`prof`, `nivel`, `mod:fue`…), `descanso` (`corto`/`largo`) | resource with uses; `mod:*` is at least 1 |
| `aumento_atributo` | `atributo`, `valor`, `maximo` (default 20) | ability score increase, capped |
| `lanzador` | `progresion` (`completo`, `medio`, `pacto`) | standard spell slots for the character level |

Shared test vectors: `format/vectors/effects.json`. The web creator applies effects when it exports a `.dnd`. The plugin loads entries that have `efectos` without error but does not compute them yet.

## Catalog (`format/catalogo/*.json`)

One file per book. It lists **only names and basic catalog data**: subclasses (`nombre`, `clase`, `nivel`), species (`nombre`, optionally `reemplazada_por`) and spells (`nombre`, `nivel`, `escuela`, `clases`, `ritual`, `concentracion`), each with `fuente` and `edicion`. No descriptions, no feature names, no tables. `tests/test_catalogo.lua` enforces the whitelist (values ≤ 60 characters, no other fields).

Content from 2014 books can be used with the 2024 rules: a subclass chosen before level 3 is taken at level 3, and species from 2014 books use the background's ability increases.
