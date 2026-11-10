# Translating dndsheet / Traducir dndsheet

Cada idioma es **un archivo** `<código>.lua` en esta carpeta. Se detectan solos: no hay que tocar código.

Each language is **one file** `<code>.lua` in this folder. They are detected automatically: no code changes needed.

## Cómo agregar un idioma / How to add a language

1. Copiá `en.lua` con el código del idioma: `pt_BR.lua`, `fr.lua`, `es_MX.lua`…
   Copy `en.lua` to the new language code.
2. Cambiá `_name` por el nombre del idioma **en su propio idioma** (aparece en el selector): `"Português (Brasil)"`.
   Set `_name` to the language's name **in that language** (shown in the selector).
3. Traducí **solo el texto de la derecha** de cada línea. **No cambies las claves** (lo de la izquierda).
   Translate **only the right-hand text**. **Do not change the keys** (left-hand side).
4. Listo: el idioma aparece en *Herramientas → dndsheet → Idioma / Language*.
   Done: it shows up in the language selector (restart KOReader to apply).

## Reglas / Rules

- `en.lua` es la referencia y el respaldo: tiene **todas** las claves. Si a tu archivo le falta una, se muestra el texto en inglés.
  `en.lua` is the reference and the fallback: it has **every** key. A missing key falls back to English.
- `%1`, `%2`… son valores que pone el plugin (un número, un nombre). Conservalos tal cual, en cualquier posición:
  `"Level %1 slots"` → `"Ranuras de nivel %1"`. No hay plurales: redactá el texto para que no los necesite.
  `%1`, `%2`… are values filled in by the plugin. Keep them as they are; word order may change.
- `\n` es un salto de línea. Las comillas dentro del texto van con barra: `\"`.
  `\n` is a line break; escape quotes inside text as `\"`.
- Las **claves del archivo `.dnd`** (`fue`, `sigilo`, `inspiracion`…) **no** se traducen y no cambian: los personajes funcionan igual en cualquier idioma.
  Keys inside `.dnd` files are never translated: characters work the same in every language.
- Los textos son cortos a propósito (la pantalla es chica). Probá que se lean enteros en la hoja.
  Keep texts short: the screen is small. Check that nothing gets cut off on the sheet.

## Qué idioma se usa / Which language is used

1. Si en el selector elegiste uno → ese.  If you picked one in the selector → that one.
2. Si está en **Automático** → el idioma de KOReader (Configuración → Idioma). Se prueba, en orden: coincidencia exacta (`es_MX`),
   idioma base (`es`) y otra variante del mismo idioma (`es_AR`, por orden alfabético). Si no hay nada: inglés.
   On **Automatic** → KOReader's language: exact match (`es_MX`), base language (`es`), any other variant of the same language
   (alphabetical), otherwise English.
3. El cambio se aplica **al reiniciar KOReader**.  Changes apply **after restarting KOReader**.

## Límite conocido / Known limitation

Los botones propios de los diálogos de KOReader (p. ej. los del teclado) siguen el idioma de KOReader, no el del plugin.
Buttons that belong to KOReader's own widgets follow KOReader's language, not the plugin's.

## Probar / Testing

`./dev.sh` (desde la raíz del proyecto) verifica que todas las claves de `en.lua` existan en cada idioma, que `_name` esté
y que los `%1`, `%2` coincidan.  `./dev.sh` checks that every language has every key, a `_name`, and the same `%N` placeholders.

## Contributing a translation / Aportar una traducción

Open a pull request that adds only `dndsheet/lang/<code>.lua`. Run `./dev.sh` before: it checks that every key and every `%N` placeholder is present.
Abrí una PR que agregue solo `dndsheet/lang/<código>.lua` y corré `./dev.sh` antes: comprueba que estén todas las claves y los `%N`.
