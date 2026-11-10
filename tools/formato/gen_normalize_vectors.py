#!/usr/bin/env python3
"""Genera format/vectors/normalize.json: para cada entrada de normalize-inputs.json, el resultado de MIGRAR + NORMALIZAR con el código Lua
del plugin (la implementación de referencia). La web (TypeScript) debe producir exactamente lo mismo."""
import json, os, subprocess, tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, "..", ".."))
PLUGIN = os.path.join(RAIZ, "dndsheet.koplugin")
casos = json.load(open(os.path.join(AQUI, "normalize-inputs.json"), encoding="utf-8"))
out = []
for c in casos:
    with tempfile.NamedTemporaryFile("w", suffix=".dnd", delete=False, encoding="utf-8") as f:
        json.dump(c["input"], f)
        ruta = f.name
    r = subprocess.run(["luajit", os.path.join(AQUI, "normalizar.lua"), ruta], cwd=PLUGIN, capture_output=True, text=True)
    os.unlink(ruta)
    if r.returncode != 0:
        raise SystemExit("falló %s: %s" % (c["name"], r.stderr))
    out.append({"name": c["name"], "input": c["input"], "expect": json.loads(r.stdout)})
doc = {"description": "migrate() + normalize() de dndsheet/schema.lua sobre cada `input`. `expect` es el resultado completo.", "cases": out}
dest = os.path.join(RAIZ, "format", "vectors", "normalize.json")
with open(dest, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("escrito", len(out), "casos")
