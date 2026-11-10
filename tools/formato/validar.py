#!/usr/bin/env python3
"""Valida .dnd contra format/dnd.schema.json.
  - Los archivos "buenos" se migran y normalizan con el código Lua del plugin (luajit) y deben validar.
  - Los "malos" (JSON roto, versión futura) deben fallar.
  - Requiere: python3-jsonschema y luajit con lua-cjson. Uso: tools/formato/validar.py [archivos.dnd …]
Sin argumentos usa la plantilla, personajes/ y pruebas/ del repo de desarrollo."""
import json, os, subprocess, sys
import jsonschema

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, "..", ".."))
PLUGIN = os.path.join(RAIZ, "dndsheet.koplugin")
if not os.path.isdir(PLUGIN):
    PLUGIN = RAIZ
schema_path = next(p for p in (os.path.join(RAIZ, "format", "dnd.schema.json"), os.path.join(PLUGIN, "format", "dnd.schema.json")) if os.path.isfile(p))
validator = jsonschema.Draft202012Validator(json.load(open(schema_path, encoding="utf-8")))


def normalizado(path):
    r = subprocess.run(["luajit", os.path.join(AQUI, "normalizar.lua"), os.path.abspath(path)], cwd=PLUGIN, capture_output=True, text=True)
    return r.returncode, (json.loads(r.stdout) if r.returncode == 0 else r.stderr.strip())


def errores(doc):
    return ["%s: %s" % ("/".join(map(str, e.absolute_path)) or "(raíz)", e.message[:90]) for e in validator.iter_errors(doc)]


def main(args):
    fallos = 0
    if args:
        buenos, malos = args, []
    else:
        buenos = [os.path.join(RAIZ, p) for p in ("plan/plantilla-personaje.dnd", "personajes/catra.dnd", "pruebas/prueba.dnd")]  # los que falten se saltean
        buenos += [os.path.join(PLUGIN, "templates", "nuevo.dnd")]
        buenos += [os.path.join(PLUGIN, "tests", "fixtures", f) for f in ("thalia.dnd", "mago.dnd", "grande.dnd", "tipos.dnd", "vacio.dnd")]
        malos = [os.path.join(RAIZ, "pruebas", f) for f in ("roto.dnd", "futuro.dnd")]
        malos += [os.path.join(PLUGIN, "tests", "fixtures", f) for f in ("roto.dnd", "futuro.dnd")]
    for p in buenos:
        if not os.path.isfile(p):
            continue
        rc, doc = normalizado(p)
        errs = errores(doc) if rc == 0 else [doc]
        print(("OK    " if not errs else "FALLA ") + os.path.relpath(p, RAIZ), *errs[:3])
        fallos += bool(errs)
        # los archivos ya en schema 3 y completos también validan crudos
    for p in malos:
        if not os.path.isfile(p):
            continue
        rc, doc = normalizado(p)
        malo = rc != 0 or bool(errores(doc))
        print(("OK    (rechazado, a propósito) " if malo else "FALLA (debía rechazarse) ") + os.path.relpath(p, RAIZ))
        fallos += not malo
    # el schema también debe validar CRUDOS los archivos completos en schema 3
    for p in (os.path.join(RAIZ, "plan", "plantilla-personaje.dnd"), os.path.join(PLUGIN, "templates", "nuevo.dnd")):
        if os.path.isfile(p) and not args:
            errs = errores(json.load(open(p, encoding="utf-8")))
            print(("OK    (crudo) " if not errs else "FALLA (crudo) ") + os.path.relpath(p, RAIZ), *errs[:3])
            fallos += bool(errs)
    if not args:
        fallos += mutaciones()
    return 1 if fallos else 0


def mutaciones():
    """El schema tiene que RECHAZAR estos cambios a la plantilla (comprueba que no valide todo)."""
    base_path = next(p for p in (os.path.join(RAIZ, "plan", "plantilla-personaje.dnd"), os.path.join(PLUGIN, "templates", "nuevo.dnd")) if os.path.isfile(p))
    base = json.load(open(base_path, encoding="utf-8"))
    casos = {
        "nivel 21": lambda d: d.update(nivel=21),
        "atributo 31": lambda d: d["atributos"].update(fue=31),
        "habilidad 3": lambda d: d["habilidades"].update(sigilo=3),
        "salvación no booleana": lambda d: d["salvaciones"].update(fue="si"),
        "falta hp": lambda d: d.pop("hp"),
        "inspiración booleana (schema 1)": lambda d: d.update(inspiracion=True),
        "muerte 4": lambda d: d["muerte"].update(fallos=4),
        "aptitud inválida": lambda d: d["conjuros"].update(aptitud="fue"),
        "ajuste texto": lambda d: d["ajustes"].update(iniciativa="x"),
        "ataque sin dano": lambda d: d["ataques"].append({"nombre": "a", "bonus": "+1"}),
        "ref vacío": lambda d: d["rasgos_ref"].append({"ref": "", "nombre": "", "nota": ""}),
        "schema 2": lambda d: d["meta"].update(schema=2),
        "falta el nivel 9 de conjuros": lambda d: d["conjuros"]["niveles"].pop("9"),
    }
    malos = 0
    for nombre, mut in casos.items():
        d = json.loads(json.dumps(base))
        mut(d)
        ok = bool(errores(d))
        print(("OK    (rechaza) " if ok else "FALLA (aceptó) ") + nombre)
        malos += not ok
    d = json.loads(json.dumps(base))
    d["campo_nuevo"] = [1, 2]
    ok = not errores(d)
    print(("OK    (acepta claves desconocidas)" if ok else "FALLA (rechazó una clave desconocida)"))
    return malos + (not ok)


sys.exit(main(sys.argv[1:]))
