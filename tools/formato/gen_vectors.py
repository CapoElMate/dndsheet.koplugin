#!/usr/bin/env python3
"""Genera format/vectors/*.json: casos de prueba de reglas COMPARTIDOS por el plugin (Lua) y la web (TypeScript).
Los valores esperados se calculan aquí con fórmulas escritas aparte (regla de 5e, no copiadas de rules.lua), así que un acuerdo
entre Lua, TypeScript y este script es una comprobación triple. Los vectores generados son los que se publican."""
import json, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "format", "vectors")
ABIL = ["fue", "des", "con", "int", "sab", "car"]
SKILL_AB = {"acrobacias": "des", "trato_animales": "sab", "arcanos": "int", "atletismo": "fue", "engano": "car", "historia": "int",
            "perspicacia": "sab", "intimidacion": "car", "investigacion": "int", "medicina": "sab", "naturaleza": "int",
            "percepcion": "sab", "interpretacion": "car", "persuasion": "car", "religion": "int", "juego_manos": "des",
            "sigilo": "des", "supervivencia": "sab"}


def mod(score): return (score - 10) // 2
def prof(level): return 2 + (level - 1) // 4


def derived(inp):
    """Valores derivados de un personaje ya normalizado (defaults aplicados)."""
    a = {k: 10 for k in ABIL}; a.update(inp.get("atributos", {}))
    a = {k: min(30, max(1, v)) for k, v in a.items()}
    level = min(20, max(1, inp.get("nivel", 1)))
    adj = inp.get("ajustes", {})
    p = adj.get("competencia") if adj.get("competencia") is not None else prof(level)
    saves = {k: mod(a[k]) + (p if inp.get("salvaciones", {}).get(k) else 0) for k in ABIL}
    rank = lambda v: v if v in (0, 1, 2) else 0  # normalize(): valores fuera de 0-2 cuentan como 0
    skills = {s: mod(a[ab]) + p * rank(inp.get("habilidades", {}).get(s, 0)) for s, ab in SKILL_AB.items()}
    init = adj.get("iniciativa") if adj.get("iniciativa") is not None else mod(a["des"])
    passive = adj.get("percepcion_pasiva") if adj.get("percepcion_pasiva") is not None else 10 + skills["percepcion"]
    apt = inp.get("conjuros", {}).get("aptitud")
    dc = adj.get("cd_conjuros")
    if dc is None and apt: dc = 8 + p + mod(a[apt])
    atk = adj.get("ataque_conjuros")
    if atk is None and apt: atk = p + mod(a[apt])
    return {"prof": p, "mod": {k: mod(a[k]) for k in ABIL}, "save": saves, "skill": skills,
            "initiative": init, "passive": passive, "spell_dc": dc, "spell_atk": atk}


THALIA = {"nivel": 5, "atributos": {"fue": 8, "des": 18, "con": 14, "int": 12, "sab": 13, "car": 14},
          "salvaciones": {"des": True, "int": True},
          "habilidades": {"acrobacias": 1, "engano": 2, "percepcion": 1, "sigilo": 2},
          "hp": {"maximo": 38, "actual": 27, "temporal": 5}, "dados_golpe": {"total": "5d8", "restantes": 3}}


def case(name, inp, note=None):
    c = {"name": name, "input": inp, "expect": derived(inp)}
    if note: c["note"] = note
    return c


def with_(base, **kw):
    d = json.loads(json.dumps(base)); d.update(kw); return d


basic_cases = [
    case("Thalia nivel 5 sin lanzamiento de conjuros", THALIA, "Thalia: personaje de referencia de las pruebas"),
    case("Thalia con aptitud INT", with_(THALIA, conjuros={"aptitud": "int"})),
    case("Thalia con aptitud CAR", with_(THALIA, conjuros={"aptitud": "car"})),
    case("Thalia con aptitud SAB", with_(THALIA, conjuros={"aptitud": "sab"})),
    case("Thalia con ajustes manuales", with_(THALIA, conjuros={"aptitud": "int"},
         ajustes={"competencia": 4, "iniciativa": 9, "percepcion_pasiva": 20, "cd_conjuros": 15, "ataque_conjuros": 7})),
    case("Personaje vacío (todo por defecto)", {}),
    case("Nivel 1, atributos 8", {"nivel": 1, "atributos": {k: 8 for k in ABIL}}),
    case("Nivel 20, atributos 30 y pericia en todo", {"nivel": 20, "atributos": {k: 30 for k in ABIL},
         "salvaciones": {k: True for k in ABIL}, "habilidades": {s: 2 for s in SKILL_AB}, "conjuros": {"aptitud": "sab"}}),
    case("Atributos fuera de rango se acotan a 1-30", {"atributos": {"fue": 99, "des": -5, "con": 0}}),
    case("Nivel fuera de rango se acota a 1-20", {"nivel": 99}),
    case("Nivel 0 se acota a 1", {"nivel": 0}),
    case("Habilidad con valor inválido cuenta como 0", {"nivel": 9, "habilidades": {"sigilo": 7, "atletismo": 1}, "atributos": {"fue": 14, "des": 12}}),
]
for lvl in (4, 5, 8, 9, 12, 13, 16, 17):
    basic_cases.append(case("Competencia en el nivel %d" % lvl, {"nivel": lvl, "salvaciones": {"fue": True}, "atributos": {"fue": 16}}))

basic = {"description": "Entrada: .dnd parcial. Cada implementación lo pasa por normalize() y compara los derivados. "
                         "`spell_dc` y `spell_atk` son null cuando no hay aptitud ni ajuste manual.",
         "mods": [{"score": s, "mod": mod(s)} for s in (1, 2, 3, 8, 9, 10, 11, 12, 13, 15, 18, 20, 29, 30)],
         "cases": basic_cases}

# ── armas (datos de weapons.json del compendio, embebidos para que el vector sea autocontenido)
W = {
    "quarterstaff": {"kind": "melee", "damage": "1d6", "damage_type": "bludgeoning", "properties": ["Versatile"], "versatile": "1d8"},
    "dagger": {"kind": "melee", "damage": "1d4", "damage_type": "piercing", "properties": ["Finesse", "Light", "Thrown"], "versatile": None},
    "shortbow": {"kind": "ranged", "damage": "1d6", "damage_type": "piercing", "properties": ["Ammunition", "Two-Handed"], "versatile": None},
    "club": {"kind": "melee", "damage": "1d4", "damage_type": "bludgeoning", "properties": ["Light"], "versatile": None},
    "rapier": {"kind": "melee", "damage": "1d8", "damage_type": "piercing", "properties": ["Finesse"], "versatile": None},
    "greatsword": {"kind": "melee", "damage": "2d6", "damage_type": "slashing", "properties": ["Heavy", "Two-Handed"], "versatile": None},
}


def signed(n): return "%+d" % n


def dmg(expr, m): return expr if m == 0 else expr + signed(m)


def weapon_attack(inp, w, proficient):
    a = {k: 10 for k in ("fue", "des")}; a.update({k: v for k, v in inp.get("atributos", {}).items() if k in a})
    fue, des = mod(a["fue"]), mod(a["des"])
    if "Finesse" in w["properties"]: ab, m = ("des" if des > fue else "fue"), max(fue, des)
    elif w["kind"] == "ranged": ab, m = "des", des
    else: ab, m = "fue", fue
    adj = inp.get("ajustes", {})
    p = adj.get("competencia") if adj.get("competencia") is not None else prof(min(20, max(1, inp.get("nivel", 1))))
    bonus = m + (p if proficient else 0)
    d = dmg(w["damage"], m) + " " + w["damage_type"]
    if w["versatile"]: d += " (%s two-handed)" % dmg(w["versatile"], m)
    return {"bonus": signed(bonus), "damage": d, "ability": ab}


wcases = []
for name, fue, des, lvl, wid, pr in [
    ("Quarterstaff FUE 12 DES 16 con competencia", 12, 16, 1, "quarterstaff", True),
    ("Dagger finesse usa el mayor (DES)", 12, 16, 1, "dagger", True),
    ("Dagger finesse usa el mayor (FUE)", 18, 12, 1, "dagger", True),
    ("Dagger finesse con FUE = DES usa FUE", 14, 14, 1, "dagger", True),
    ("Shortbow a distancia usa DES", 12, 16, 1, "shortbow", True),
    ("Quarterstaff sin competencia", 12, 16, 1, "quarterstaff", False),
    ("Quarterstaff con modificador 0 (sin «+0»)", 10, 10, 1, "quarterstaff", True),
    ("Club con modificador negativo", 8, 10, 1, "club", True),
    ("Club con competencia de nivel 9", 10, 10, 9, "club", True),
    ("Rapier finesse con DES alta", 10, 20, 5, "rapier", True),
    ("Greatsword con FUE 20 nivel 17", 20, 10, 17, "greatsword", True),
]:
    inp = {"nivel": lvl, "atributos": {"fue": fue, "des": des}}
    wcases.append({"name": name, "input": inp, "weapon": W[wid], "proficient": pr, "expect": weapon_attack(inp, W[wid], pr)})
wcases.append({"name": "Competencia manual (ajuste)", "input": {"nivel": 1, "atributos": {"fue": 14}, "ajustes": {"competencia": 5}},
               "weapon": W["club"], "proficient": True, "expect": weapon_attack({"nivel": 1, "atributos": {"fue": 14}, "ajustes": {"competencia": 5}}, W["club"], True)})
weapons = {"description": "Rules.weapon_attack(data, weapon, proficient) → bonus con signo, daño con modificador y atributo usado. "
                           "`weapon` trae solo los campos de weapons.json del compendio que usa la regla.", "cases": wcases}

# ── acciones sobre el HP, descansos
actions = {"description": "Cada caso parte de `input` (normalizado), aplica `ops` en orden y compara con `expect` (solo los campos listados).", "cases": [
    {"name": "Daño: primero el HP temporal", "input": THALIA, "ops": [["damage", 8]], "expect": {"hp": {"actual": 24, "temporal": 0}}},
    {"name": "Daño menor que el temporal", "input": THALIA, "ops": [["damage", 3]], "expect": {"hp": {"actual": 27, "temporal": 2}}},
    {"name": "Daño enorme: mínimo 0", "input": THALIA, "ops": [["damage", 100]], "expect": {"hp": {"actual": 0, "temporal": 0}}},
    {"name": "Daño 0 o negativo no hace nada", "input": THALIA, "ops": [["damage", 0], ["damage", -4]], "expect": {"hp": {"actual": 27, "temporal": 5}}},
    {"name": "Curar con tope en el máximo", "input": with_(THALIA, hp={"maximo": 38, "actual": 10, "temporal": 0}), "ops": [["heal", 50]], "expect": {"hp": {"actual": 38}}},
    {"name": "Curar no baja un HP que ya supera el máximo", "input": with_(THALIA, hp={"maximo": 38, "actual": 40, "temporal": 0}), "ops": [["heal", 5]], "expect": {"hp": {"actual": 40}}},
    {"name": "Descanso largo", "input": with_(THALIA, muerte={"exitos": 1, "fallos": 2},
        conjuros={"niveles": {"1": {"total": 3, "usados": 3}, "2": {"total": 2, "usados": 1}}}),
     "ops": [["long_rest"]], "expect": {"hp": {"actual": 38, "temporal": 0}, "muerte": {"exitos": 0, "fallos": 0},
        "slots_usados": {"1": 0, "2": 0}, "dados_golpe": {"restantes": 5}}},
    {"name": "Descanso largo recupera al menos 1 dado", "input": with_(THALIA, dados_golpe={"total": "1d8", "restantes": 0}),
     "ops": [["long_rest"]], "expect": {"dados_golpe": {"restantes": 1}}},
    {"name": "Descanso largo recupera la mitad de los dados", "input": with_(THALIA, dados_golpe={"total": "5d8", "restantes": 0}),
     "ops": [["long_rest"]], "expect": {"dados_golpe": {"restantes": 2}}},
    {"name": "Dados de golpe mixtos (3d10+2d8 = 5)", "input": with_(THALIA, dados_golpe={"total": "3d10+2d8", "restantes": 1}),
     "ops": [["long_rest"]], "expect": {"dados_golpe": {"restantes": 3}}},
], "hit_dice_count": [["5d8", 5], ["3d10+2d8", 5], ["1d8+2", 1], ["x", None], ["", None], [None, None], ["d8", None]]}

os.makedirs(OUT, exist_ok=True)
for fname, doc in (("rules-basic.json", basic), ("weapon-attacks.json", weapons), ("hp-and-rests.json", actions)):
    with open(os.path.join(OUT, fname), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("escrito", fname)
