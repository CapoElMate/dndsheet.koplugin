#!/usr/bin/env bash
# Genera dndsheet-<version>.zip (carpeta dndsheet.koplugin/ en la raíz, lista para koreader/plugins/) y SHA256SUMS.
# Sin tests/, tools/, docs/, __pycache__ ni archivos de desarrollo. Funciona en el repo de desarrollo y en el público.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")"
RAIZ="$PWD"
if [ "${SKIP_CHECK:-0}" != "1" ]; then
    ./dev.sh check >/dev/null || { echo "dev.sh falló: no se empaqueta"; exit 1; }
fi
if [ -d dndsheet.koplugin ]; then SRC="dndsheet.koplugin"; else SRC="."; fi
VERSION="$(sed -n 's/^return "\(.*\)"$/\1/p' "$SRC/dndsheet/version.lua")"
[ -n "$VERSION" ] || { echo "no encuentro la versión en dndsheet/version.lua"; exit 1; }
SALIDA="${SALIDA:-$RAIZ}"
ZIP="$SALIDA/dndsheet-$VERSION.zip"
rm -f "$ZIP" "$SALIDA/SHA256SUMS"
python3 - "$SRC" "$ZIP" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
# lista blanca: lo que el dispositivo necesita
tops = ["_meta.lua", "main.lua", "dndsheet", "compendium", "templates", "COBERTURA.md"]
extra = {}  # LICENSE y NOTICE.md pueden estar un nivel más arriba (repo de desarrollo)
for name in ("LICENSE", "NOTICE.md", "README.md", "README.es.md", "CHANGELOG.md"):
    for base in (src, os.path.join(src, "..")):
        p = os.path.join(base, name)
        if os.path.isfile(p):
            extra[name] = p
            break
    else:
        sys.exit("falta " + name)
prefix = "dndsheet.koplugin/"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for t in tops:
        p = os.path.join(src, t)
        if os.path.isfile(p):
            z.write(p, prefix + t)
        elif os.path.isdir(p):
            for d, dirs, files in os.walk(p):
                dirs[:] = sorted(x for x in dirs if x not in ("__pycache__", "tests"))
                for f in sorted(files):
                    if f.endswith((".pyc", ".bak", ".tmp")):
                        continue
                    full = os.path.join(d, f)
                    z.write(full, prefix + os.path.relpath(full, src))
    for name, p in extra.items():
        z.write(p, prefix + name)
    names = z.namelist()
for need in ("_meta.lua", "main.lua", "LICENSE", "NOTICE.md", "COBERTURA.md"):
    if prefix + need not in names:
        sys.exit("el zip no contiene " + need)
bad = [n for n in names if "/tests/" in n or "__pycache__" in n or "fuentes" in n]
if bad:
    sys.exit("archivos que no deben ir: " + ", ".join(bad))
PY
( cd "$SALIDA" && sha256sum "dndsheet-$VERSION.zip" > SHA256SUMS )
python3 -m zipfile -l "$ZIP" | tail -n +2 | awk '{n++} END {print n " archivos"}'
ls -l "$ZIP" | awk '{print "tamaño: " $5 " bytes"}'
cat "$SALIDA/SHA256SUMS"
