"""Valida los JSON del compendio contra el SRD (criterios de F-07).

Uso: python3 tools/compendio/validar.py [carpeta-json] [pdf]
Sale con codigo 1 si algo falla. Escribe tmp/fidelidad.txt con el detalle.
"""
import difflib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import srdlines
import texto

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RAIZ, "dndsheet.koplugin", "compendium", "srd521", "en")
PDF = sys.argv[2] if len(sys.argv) > 2 else os.path.join(RAIZ, "fuentes", "SRD_CC_v5.2.1.pdf")

errores = []
avisos = []
# Diferencias del propio SRD 5.2.1 entre la descripcion del conjuro y las listas por clase (verificadas a mano):
# la lista de Bard/Sorcerer/Wizard nombra "Phantasmal Killer" (sin descripcion en el SRD) y no "Phantasmal Force";
# la descripcion de Mind Spike nombra a Sorcerer pero su lista no lo trae.
INCONSISTENCIAS_SRD = {("Phantasmal Force", "Bard"), ("Phantasmal Force", "Sorcerer"),
                       ("Phantasmal Force", "Wizard"), ("Mind Spike", "Sorcerer")}


def err(m):
    errores.append(m)


def load(n):
    with open(os.path.join(BASE, n + ".json"), encoding="utf-8") as f:
        return json.load(f)


classes, subclasses, species = load("classes"), load("subclasses"), load("species")
feats, spells, weapons = load("feats"), load("spells"), load("weapons")
meta = load("meta")

# ------------------------------------------------------------ ids y referencias
ids = {}
for lista in (classes, subclasses, species, feats, spells, weapons):
    for e in lista:
        if e["id"] in ids:
            err("id repetido: " + e["id"])
        ids[e["id"]] = e
        for f in e.get("features", []) + e.get("traits", []):
            if f["id"] in ids:
                err("id repetido: " + f["id"])
            ids[f["id"]] = f
class_ids = {c["id"] for c in classes}
sub_ids = {s["id"] for s in subclasses}
for c in classes:
    for sid in c["subclass_ids"]:
        if sid not in sub_ids:
            err("subclase inexistente %s en %s" % (sid, c["id"]))
for s in subclasses:
    if s["class_id"] not in class_ids:
        err("class_id inexistente en " + s["id"])
    if s["id"] not in next(c for c in classes if c["id"] == s["class_id"])["subclass_ids"]:
        err("subclase no listada en su clase: " + s["id"])
class_names = {c["name"] for c in classes}
for sp in spells:
    for cn in sp["classes"]:
        if cn not in class_names:
            err("clase inexistente %s en conjuro %s" % (cn, sp["id"]))

# ------------------------------------------------------------ clases
if len(classes) != 12:
    err("se esperaban 12 clases, hay %d" % len(classes))
for c in classes:
    for k in ("hit_die", "primary_ability"):
        if not c.get(k):
            err("clase %s sin %s" % (c["id"], k))
    if len(c["saving_throws"]) != 2:
        err("clase %s: salvaciones %s" % (c["id"], c["saving_throws"]))
    if not c["subclass_ids"]:
        err("clase sin subclases: " + c["id"])
    lv = {f["level"] for f in c["features"] if f["level"]}
    for need in (1,):
        if need not in lv:
            err("clase %s sin rasgo de nivel %d" % (c["id"], need))
    for f in c["features"]:
        if not f["text"].strip():
            err("rasgo sin texto: " + f["id"])
for s in subclasses:
    if not s["features"]:
        err("subclase sin rasgos: " + s["id"])
    for f in s["features"]:
        if not f["text"].strip():
            err("rasgo sin texto: " + f["id"])


def check_class_tables():
    """Cada nombre de la columna 'Class Features' de la tabla del SRD existe como rasgo en ese nivel."""
    lines = srdlines.load(PDF, 27, 83)
    cname = None
    i, n = 0, len(lines)
    tablas = {}
    while i < n:
        l = lines[i]
        if l["font"].startswith("GillSans-SemiBold") and l["size"] == 18.0:
            cname = l["text"].strip()
        if l["font"].startswith("GillSans-SemiBold") and l["size"] == 10.5 and l["text"].strip() == (cname or "") + " Features":
            j = i + 1
            tl = []
            while j < n and lines[j]["size"] in (9.2, 9.5) and lines[j]["font"].startswith("GillSans"):
                tl.append(lines[j])
                j += 1
            tablas[cname] = tl
            i = j
            continue
        i += 1
    for c in classes:
        tl = tablas.get(c["name"])
        if not tl:
            err("sin tabla de rasgos para " + c["name"])
            continue
        # filas por y; la fila empieza con el numero de nivel; celdas ordenadas por x
        rows = {}
        for l in tl:
            rows.setdefault((l["pg"], round(l["y"] / 3)), []).append(l)
        niveles = []
        cur = None
        for key in sorted(rows):
            cells = sorted(rows[key], key=lambda l: l["x"])
            txts = [x["text"].strip() for x in cells if not x["bold"]]
            if not txts:
                continue
            if re.fullmatch(r"\d{1,2}", txts[0]) and int(txts[0]) <= 20:
                cur = {"level": int(txts[0]), "txt": ""}
                niveles.append(cur)
                cand = [t for t in txts[1:] if re.search(r"[A-Za-z]{4}", t) and not re.fullmatch(r"[Dd]\d+|\+\d+ ft\.", t)]
                cur["txt"] = cand[0] if cand else ""
            elif cur is not None:
                cand = [t for t in txts if re.search(r"[A-Za-z]{3}", t) and not re.fullmatch(r"[Dd]\d+|\+\d+ ft\.", t)]
                if cand:
                    cur["txt"] = texto._join(cur["txt"], cand[0])
        if len(niveles) != 20:
            err("%s: la tabla tiene %d filas" % (c["name"], len(niveles)))
        names_all = {f["name"] for f in c["features"]}
        by_level = {}
        for f in c["features"]:
            by_level.setdefault(f["level"], []).append(f)
        rowtxt = {r["level"]: r["txt"] for r in niveles}
        # directo: cada rasgo (no opcion) figura en la fila de su nivel
        for f in c["features"]:
            if f.get("group"):
                continue
            if f["name"] not in rowtxt.get(f["level"], "") and not (f["name"].endswith("Subclass") and "Subclass" in rowtxt.get(f["level"], "")):
                err("%s nivel %d: el rasgo '%s' no figura en la tabla (%s)" % (c["name"], f["level"], f["name"], rowtxt.get(f["level"])))
        # inverso: cada nombre de la tabla existe como rasgo de la clase (sin parentesis)
        for lvl, txt in rowtxt.items():
            for nm in [x.strip() for x in re.sub(r"\([^)]*\)", "", txt).split(",") if x.strip()]:
                if nm in ("Subclass feature", "\u2014"):
                    continue
                if nm not in names_all:
                    err("%s nivel %d: '%s' esta en la tabla pero no como rasgo" % (c["name"], lvl, nm))


check_class_tables()

# ------------------------------------------------------------ conjuros
for sp in spells:
    for k in ("id", "name", "level", "school", "casting_time", "range", "components", "duration", "ritual",
              "concentration", "classes", "text"):
        if k not in sp or sp[k] in (None, "", []) and k not in ("ritual", "concentration"):
            err("conjuro %s sin %s" % (sp.get("id"), k))
    if not 0 <= sp["level"] <= 9:
        err("nivel fuera de rango: " + sp["id"])


def check_spell_lists():
    """classes[] de cada conjuro coincide con las listas 'X Spell List' del SRD."""
    lines = srdlines.load(PDF, 27, 83)
    names = {sp["name"]: sp for sp in spells}
    cname = None
    part = None
    found = {}
    for l in lines:
        if l["font"].startswith("GillSans-SemiBold") and l["size"] == 18.0:
            cname = l["text"].strip()
        if l["font"].startswith("GillSans-SemiBold") and l["size"] == 14.0:
            part = "list" if l["text"].strip().endswith("Spell List") else None
        if part == "list" and cname and l["size"] == 9.5 and not l["bold"] and l["text"].strip() in names:
            base = 63.0 if l["col"] != 2 else 313.5
            if l["x"] < base + 6:
                found.setdefault(cname, set()).add(l["text"].strip())
    for c in classes:
        mine = {sp["name"] for sp in spells if c["name"] in sp["classes"]}
        lst = found.get(c["name"], set())
        if lst:
            falta = lst - mine
            sobra = mine - lst
            # Wizard/otras: la lista del SRD solo cubre las clases con lista propia
            for n in sorted(falta):
                err("lista %s tiene %s pero el conjuro no la nombra" % (c["name"], n))
            for n in sorted(sobra):
                if (n, c["name"]) in INCONSISTENCIAS_SRD:
                    avisos.append("SRD inconsistente: %s nombra a %s pero la lista de la clase no lo trae" % (n, c["name"]))
                else:
                    err("conjuro %s nombra %s pero no esta en su lista" % (n, c["name"]))
        elif any(c["name"] in sp["classes"] for sp in spells):
            avisos.append("clase %s sin lista de conjuros detectada" % c["name"])


check_spell_lists()

# ------------------------------------------------------------ armas
for w in weapons:
    if w["id"] == "weapon.net":
        continue
    if w["id"] == "weapon.blowgun":
        if w["damage"] != "1":
            err("arma blowgun: damage '%s'" % w["damage"])
    elif not re.fullmatch(r"\d+d\d+", w["damage"] or ""):
        err("arma %s: damage '%s'" % (w["id"], w["damage"]))
    if not w["damage_type"]:
        err("arma %s sin tipo de dano" % w["id"])
    if not w["mastery"]:
        err("arma %s sin mastery" % w["id"])
    if not isinstance(w["properties"], list):
        err("arma %s sin properties" % w["id"])

# ------------------------------------------------------------ meta
if "This work includes material from the System Reference Document 5.2.1" not in meta["attribution"]:
    err("meta sin atribucion")
if not re.fullmatch(r"[0-9a-f]{64}", meta["sha256"]):
    err("meta sin sha256")

# ------------------------------------------------------------ fidelidad
def norm_tokens(t):
    t = t.replace("­", "").replace(" ", " ")
    t = re.sub(r"-\s*\n", "", t)
    t = t.replace("-", "").replace("−", "").replace("—", " ")
    t = t.replace("’", "'").replace("“", '"').replace("”", '"').lower()
    return re.findall(r"[a-z0-9]+", t)


lines_all = srdlines.load(PDF)
src_text = "\n".join(l["text"] for l in texto.strip_feature_tables(lines_all))
src = norm_tokens(src_text)
index = {}
for i in range(len(src) - 3):
    index.setdefault(tuple(src[i:i + 4]), []).append(i)

entries = []
for c in classes:
    for f in c["features"]:
        entries.append((f["id"], f["text"]))
for s in subclasses:
    for f in s["features"]:
        entries.append((f["id"], f["text"]))
for s in species:
    for t in s["traits"]:
        entries.append((t["id"], t["text"]))
for f in feats:
    entries.append((f["id"], f["text"]))
for sp in spells:
    entries.append((sp["id"], sp["text"]))
    if sp["higher_levels"]:
        entries.append((sp["id"] + "#higher", sp["higher_levels"]))

def tabla_lineas(txt):
    """Separa las lineas de tabla (con ' | ') del resto."""
    tab, resto = [], []
    for ln in txt.split("\n"):
        (tab if " | " in ln else resto).append(ln)
    return "\n".join(tab), "\n".join(resto)


def alinear(toks):
    votes = {}
    for off in range(0, len(toks) - 3):
        for pos in index.get(tuple(toks[off:off + 4]), []):
            k = (pos - off) // 16
            votes[k] = votes.get(k, 0) + 1
    best, best_win, best_sm = 0.0, None, None
    for k in sorted(votes, key=votes.get, reverse=True)[:6]:
        lo = max(0, k * 16 - 340)
        win = src[lo: lo + int(len(toks) * 3) + 900]
        sm = difflib.SequenceMatcher(None, toks, win, autojunk=False)
        matched = sum(b_.size for b_ in sm.get_matching_blocks())
        if matched / len(toks) > best:
            best, best_win, best_sm = matched / len(toks), win, sm
    return best, best_win, best_sm


detalle = []
bajos = []
omitidos = []
dif = os.environ.get("DIF", "").split(",")
for eid, txt in entries:
    tab, resto = tabla_lineas(txt)
    toks = norm_tokens(resto)
    if len(toks) < 4:
        continue
    best, win, sm = alinear(toks)
    # celdas de tabla: cada token debe existir en la ventana (el orden de filas del PDF no es el de lectura)
    if tab and win is not None:
        from collections import Counter
        have = Counter(win)
        falta = 0
        tt = norm_tokens(tab)
        for tk in tt:
            if have[tk] > 0:
                have[tk] -= 1
            else:
                falta += 1
        cob = 1 - falta / max(1, len(tt))
        if cob < 0.98:
            best = min(best, cob)
    if sm is not None:
        bl = [b_ for b_ in sm.get_matching_blocks() if b_.size]
        omit = sum(max(0, bl[k + 1].b - (bl[k].b + bl[k].size)) for k in range(len(bl) - 1)) if len(bl) > 1 else 0
        if omit > 12 and not tab:
            omitidos.append((omit, eid))
    detalle.append("%.4f %s" % (best, eid))
    if best < 0.98:
        bajos.append((eid, best))
    if eid in dif and sm is not None:
        print("==", eid, len(toks), "%.3f" % best)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag != "equal" and (i2 - i1) > 0:
                print(" ", tag, "ENTRY:", toks[i1:i2][:40], "SRC:", win[j1:j2][:40])
os.makedirs(os.path.join(RAIZ, "tmp"), exist_ok=True)
with open(os.path.join(RAIZ, "tmp", "fidelidad.txt"), "w") as f:
    f.write("\n".join(sorted(detalle)))
for om, eid in sorted(omitidos, reverse=True)[:40]:
    avisos.append("posible texto omitido dentro de %s: %d palabras del SRD" % (eid, om))
for eid, b in bajos:
    err("fidelidad %.3f < 0.98: %s" % (b, eid))

print("entradas verificadas por fidelidad:", len(detalle), "· peor:", min((float(d.split()[0]) for d in detalle), default=1))
for a in avisos:
    print("AVISO:", a)
for e in errores:
    print("ERROR:", e)
print("OK" if not errores else "FALLAS: %d" % len(errores))
sys.exit(1 if errores else 0)
