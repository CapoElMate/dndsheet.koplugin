#!/usr/bin/env python3
"""Genera format/dnd.schema.json (JSON Schema draft 2020-12) a partir de lo que acepta schema.lua (normalize, schema 3).
El archivo generado es la fuente publicada; este script documenta cómo se armó y evita errores de tipeo."""
import json, os

ABIL = ["fue", "des", "con", "int", "sab", "car"]
SKILLS = ["acrobacias", "trato_animales", "arcanos", "atletismo", "engano", "historia", "perspicacia", "intimidacion",
          "investigacion", "medicina", "naturaleza", "percepcion", "interpretacion", "persuasion", "religion",
          "juego_manos", "sigilo", "supervivencia"]

S = {"type": "string"}
def ints(lo=None, hi=None, desc=None):
    d = {"type": "integer"}
    if lo is not None: d["minimum"] = lo
    if hi is not None: d["maximum"] = hi
    if desc: d["description"] = desc
    return d
def obj(props, required=None, desc=None):
    d = {"type": "object", "properties": props, "required": required if required is not None else list(props)}
    if desc: d["description"] = desc
    return d
def text(desc): return {"type": "string", "description": desc}

ref = {"type": "string", "minLength": 1, "description": "id de una entrada del compendio (opcional)"}
manual = {"type": ["integer", "null"], "description": "ajuste manual; null = calcular"}

levels = {"0": obj({"lista": {"type": "array", "items": obj({"nombre": S, "ref": ref}, ["nombre"])}}, ["lista"],
                   "trucos: sin ranuras")}
for n in range(1, 10):
    levels[str(n)] = obj({
        "total": ints(0, 99, "ranuras totales"),
        "usados": ints(0, 99, "ranuras gastadas (<= total)"),
        "lista": {"type": "array", "items": obj({"nombre": S, "preparado": {"type": "boolean"}, "ref": ref}, ["nombre", "preparado"])},
    })

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://github.com/capoelmate/dndsheet.koplugin/blob/main/format/dnd.schema.json",
    "title": "dndsheet character file (.dnd), schema 3",
    "description": "Describe un archivo .dnd COMPLETO y ya migrado a schema 3 (lo que escribe dndsheet). Las claves desconocidas se permiten y se conservan. "
                   "Para leer archivos incompletos o de versiones anteriores, aplicá primero las migraciones y la normalización (docs/FORMATO-DND.md).",
    "type": "object",
    "properties": {
        "meta": {"type": "object", "properties": {
            "schema": {"const": 3, "description": "versión del formato"},
            "app": S, "creado": {"type": "integer", "description": "Unix time"}, "guardado": {"type": "integer", "description": "Unix time"},
        }, "required": ["schema"]},
        "nombre": S, "clase_nivel": text("texto libre: «Rogue 5», «Fighter 3 / Wizard 2»"),
        "nivel": ints(1, 20, "nivel total: define el bonificador de competencia"),
        "trasfondo": S, "jugador": S, "raza": S, "alineamiento": S, "experiencia": ints(0),
        "atributos": obj({a: ints(1, 30) for a in ABIL}),
        "salvaciones": obj({a: {"type": "boolean", "description": "competencia en la salvación"} for a in ABIL}),
        "habilidades": obj({k: {"enum": [0, 1, 2], "description": "0 sin competencia · 1 competente · 2 pericia"} for k in SKILLS}),
        "inspiracion": ints(0, 99),
        "ca": ints(0), "velocidad": text("texto libre: «30 ft», «9 m / fly 18 m»"),
        "hp": obj({"maximo": ints(0), "actual": ints(0), "temporal": ints(0)}),
        "dados_golpe": obj({"total": text("«5d8», «3d10+2d8»"), "restantes": ints(0)}),
        "muerte": obj({"exitos": ints(0, 3), "fallos": ints(0, 3)}),
        "ajustes": obj({k: manual for k in ["competencia", "iniciativa", "percepcion_pasiva", "cd_conjuros", "ataque_conjuros"]}),
        "ataques": {"type": "array", "items": obj({"nombre": S, "bonus": text("texto: «+5»"), "dano": text("texto: «1d8+3 slashing»"), "ref": ref},
                                                  ["nombre", "bonus", "dano"])},
        "ataques_notas": S,
        "monedas": obj({k: ints(0) for k in ["pc", "pp", "pe", "po", "ppt"]}, desc="cobre, plata, electro, oro, platino"),
        "equipo": S, "otras_competencias": S, "rasgos": S,
        "rasgos_ref": {"type": "array", "items": obj({"ref": {"type": "string", "minLength": 1}, "nombre": S, "nota": S})},
        "personalidad": obj({k: S for k in ["rasgos", "ideales", "vinculos", "defectos"]}),
        "fisico": obj({k: S for k in ["edad", "altura", "peso", "ojos", "piel", "pelo"]}),
        "apariencia": S, "aliados": S, "organizacion": S, "rasgos_adicionales": S, "historia": S, "tesoro": S,
        "conjuros": obj({"clase": S, "aptitud": {"enum": ["int", "sab", "car", None]}, "niveles": obj(levels)}),
        "notas": S,
    },
    "required": ["meta", "nombre", "clase_nivel", "nivel", "trasfondo", "jugador", "raza", "alineamiento", "experiencia", "atributos",
                 "salvaciones", "habilidades", "inspiracion", "ca", "velocidad", "hp", "dados_golpe", "muerte", "ajustes", "ataques",
                 "ataques_notas", "monedas", "equipo", "otras_competencias", "rasgos", "rasgos_ref", "personalidad", "fisico",
                 "apariencia", "aliados", "organizacion", "rasgos_adicionales", "historia", "tesoro", "conjuros", "notas"],
    "additionalProperties": True,
}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "format", "dnd.schema.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("escrito", os.path.normpath(out))
