# tools/compendio · convertir el SRD 5.2.1 a JSON (F-07)

No va al plugin ni al zip. Requiere Python 3 y PyMuPDF (`pip install --user --break-system-packages pymupdf`).
`pdftotext` no hace falta: el linealizador usa las fuentes y posiciones del PDF.

| Script | Qué hace |
|---|---|
| `srdlines.py` | Lee el PDF y devuelve las líneas en orden de lectura (columnas, tablas reubicadas) con fuente y tamaño |
| `texto.py` | Pasa líneas a texto plano: párrafos, viñetas, tablas (`a \| b`), guiones de corte, bloques de criatura |
| `extraer.py` | Genera `dndsheet.koplugin/compendium/srd521/en/*.json` + `meta.json` y `fuentes/srd521-en.txt` |
| `validar.py` | Criterios de F-07: ids, referencias, 12 clases vs. tabla de rasgos del SRD, listas de conjuros, armas, fidelidad ≥ 0,98 |

Uso: `python3 tools/compendio/extraer.py && python3 tools/compendio/validar.py`.
Para el informe de cobertura: extraer el texto del PHB a `tmp/phb.txt` (con PyMuPDF, `page.get_text()` por página con una línea
`DIF=<id>,<id> python3 tools/compendio/validar.py` imprime las diferencias de fidelidad de esas entradas.
