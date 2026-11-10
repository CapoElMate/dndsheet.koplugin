"""Extrae el SRD 5.2.1 (ingles) a JSON para dndsheet.koplugin/compendium/srd521/en/.

Uso:  python3 tools/compendio/extraer.py [pdf] [salida]
Texto copiado del SRD sin resumir. Ver tools/compendio/README.md.
"""
import json
import os
import re
import sys
import pickle

sys.path.insert(0, os.path.dirname(__file__))
import srdlines
import texto

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PDF = os.path.join(RAIZ, "fuentes", "SRD_CC_v5.2.1.pdf")
OUT = os.path.join(RAIZ, "dndsheet.koplugin", "compendium", "srd521", "en")

ABILITIES = ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]


def slug(s):
    s = s.lower().replace("’", "").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def is_gs(l, size=None, bold=None):
    if not l["font"].startswith("GillSans-SemiBold"):
        return False
    if size is not None and l["size"] != size:
        return False
    return True


def is_h(l, size):
    return is_gs(l, size)


def split_sections(lines):
    """Devuelve dict nombre_H1 -> lista de lineas (H1 = GillSans-SemiBold 26)."""
    secs = {}
    cur = None
    for l in lines:
        if is_h(l, 26.0) and l["pg"] > 4:
            cur = l["text"].strip()
            secs.setdefault(cur, [])
            continue
        if cur:
            secs[cur].append(l)
    return secs


def headings_blocks(lines, sizes):
    """Parte `lines` en bloques [(heading_line_group, body_lines)] por encabezados de los tamanios dados.
    Lineas de encabezado consecutivas del mismo tamanio se unen."""
    blocks = []
    cur = None
    i = 0
    n = len(lines)
    while i < n:
        l = lines[i]
        if is_gs(l) and l["size"] in sizes and l["bold"]:
            size = l["size"]
            txt = l["text"]
            j = i + 1
            while j < n and is_gs(lines[j]) and lines[j]["size"] == size:
                txt += lines[j]["text"] if txt.endswith(" ") else " " + lines[j]["text"]
                j += 1
            cur = {"size": size, "title": re.sub(r"\s+", " ", txt).strip(), "pg": l["pg"], "body": []}
            blocks.append(cur)
            i = j
            continue
        if cur is None:
            cur = {"size": 0, "title": "", "pg": l["pg"], "body": []}
            blocks.append(cur)
        cur["body"].append(l)
        i += 1
    return blocks


# ---------------------------------------------------------------- clases
def parse_core(body):
    """Core X Traits: devuelve (hit_die, primary, saves)."""
    hit = primary = None
    saves = []
    vals = {}
    label = None
    # etiquetas en negrita 9.2; valor = primeras lineas no negrita siguientes
    for idx, l in enumerate(body):
        t = l["text"].strip()
        if l["bold"] and l["size"] == 9.2:
            label = t
            if label in ("Primary Ability", "Hit Point Die", "Saving Throw"):
                # valor = primera linea no negrita posterior
                for m in body[idx + 1:]:
                    if not m["bold"]:
                        vals[label] = m["text"].strip()
                        break
    m = re.match(r"D(\d+)", vals.get("Hit Point Die", ""))
    if m:
        hit = int(m.group(1))
    primary = vals.get("Primary Ability")
    st = vals.get("Saving Throw", "")
    saves = [a for a in ABILITIES if a in st]
    return hit, primary, saves


def parse_classes(sec_lines, out):
    classes, subclasses = [], []
    # partir por H2 (nombre de clase)
    blocks = headings_blocks(sec_lines, {18.0})
    for b in blocks:
        if b["size"] != 18.0:
            continue
        cname = b["title"]
        cid = slug(cname)
        sub = headings_blocks(b["body"], {14.0, 12.0})
        part = None
        cls = {"id": cid, "name": cname, "hit_die": None, "primary_ability": None,
               "saving_throws": [], "features": [], "subclass_ids": []}
        cur_sc = None
        group = None
        group_level = None
        pages = {}
        for s in sub:
            t = s["title"]
            if s["size"] == 0:
                cls["hit_die"], cls["primary_ability"], cls["saving_throws"] = parse_core(s["body"])
                continue
            if s["size"] == 14.0:
                cur_sc = None if not t.startswith(cname + " Subclass:") else cur_sc
                group = None
                if t.startswith("Becoming a"):
                    part = "becoming"
                elif t.endswith("Class Features"):
                    part = "features"
                elif t.endswith("Spell List"):
                    part = "spelllist"
                elif t.startswith(cname + " Subclass:"):
                    part = "subclass"
                    scname = t.split("Subclass:", 1)[1].strip()
                    cur_sc = {"id": "subclass." + slug(scname), "class_id": cid, "name": scname, "features": [],
                              "intro": s["body"]}
                    subclasses.append(cur_sc)
                    cls["subclass_ids"].append(cur_sc["id"])
                else:
                    part = "options"
                    group = t
                    # nivel: el del rasgo de clase cuyo nombre empieza con la primera palabra
                    group_level = None
                    first = t.split()[0]
                    for f in cls["features"]:
                        if f["name"].startswith(first):
                            group_level = f["level"]
                continue
            # size 12
            m = re.match(r"Level (\d+): (.+)$", t)
            if part in ("features", "subclass") and m:
                feat = {"id": None, "name": m.group(2).strip(), "level": int(m.group(1)),
                        "_lines": s["body"], "_pg": s["pg"]}
                (cur_sc["features"] if part == "subclass" else cls["features"]).append(feat)
            elif part == "options":
                feat = {"id": None, "name": t, "level": group_level, "group": group,
                        "_lines": s["body"], "_pg": s["pg"]}
                cls["features"].append(feat)
        classes.append(cls)
    return classes, subclasses


def attach_tables(blocks_sub):
    pass


def render_feature_bodies(items):
    """Pasa `_lines` a text y descarta tablas de rasgos de clase."""
    for it in items:
        lines = it.pop("_lines")
        it["text"] = texto.render(lines)
        it["_pg"] = it.get("_pg")


def fix_ids(classes, subclasses):
    for c in classes:
        names = {}
        for f in c["features"]:
            names.setdefault(slug(f["name"]), []).append(f)
        for sl, fs in names.items():
            for f in fs:
                f["id"] = c["id"] + "." + sl + (("-l%d" % f["level"]) if len(fs) > 1 and f["level"] is not None else "")
    for s in subclasses:
        names = {}
        for f in s["features"]:
            names.setdefault(slug(f["name"]), []).append(f)
        for sl, fs in names.items():
            for f in fs:
                f["id"] = s["id"] + "." + sl + (("-l%d" % f["level"]) if len(fs) > 1 else "")


# ---------------------------------------------------------------- especies
def render_with_tables(lines):
    return texto.render(lines)


def parse_species(sec_lines):
    # solo "Species Descriptions" en adelante
    start = None
    for i, l in enumerate(sec_lines):
        if is_h(l, 14.0) and l["text"].strip() == "Species Descriptions":
            start = i + 1
            break
    body = sec_lines[start:]
    # termina antes de la siguiente H2 (Feats esta en otra H1)
    out = []
    for b in headings_blocks(body, {12.0}):
        if b["size"] != 12.0:
            continue
        name = b["title"]
        lines = b["body"]
        ctype = size = speed = None
        i = 0
        hdr_end = 0
        # cabecera: Creature Type / Size / Speed (GillSans 10.0, 'Size' puede continuar en otra linea)
        buf = []
        for j, l in enumerate(lines):
            if l["font"].startswith("Cambria"):
                hdr_end = j
                break
            buf.append(l)
        else:
            hdr_end = len(lines)
        htxt = ""
        for l in buf:
            htxt = texto._join(htxt, l["text"]) if htxt else l["text"]
            htxt += "\n" if False else ""
        # separar por etiquetas
        m = re.search(r"Creature Type:\s*(.*?)\s*Size:\s*(.*?)\s*Speed:\s*(.*)$", htxt.replace("\n", " "))
        if m:
            ctype, size, speed = m.group(1), m.group(2), m.group(3)
        rest = lines[hdr_end:]
        out.append({"name": name, "creature_type": ctype, "size": size, "speed": speed, "_rest": rest})
    return out


def split_traits(rest):
    """Divide en rasgos: parrafos que empiezan con texto en negrita-cursiva."""
    traits = []
    cur = None
    for l in rest:
        sp = [s for s in l["spans"] if s[2].strip() != ""]
        lead_bi = bool(sp) and "BoldItalic" in sp[0][0] or (bool(sp) and "Cambria-Bold" in sp[0][0])
        tab = l["text"].lstrip(" ").startswith("\t") or l["text"].startswith("\t")
        if lead_bi and (tab or cur is None or True) and l["font"].startswith("Cambria"):
            # nombre = spans consecutivos en negrita
            name = ""
            for f, sz, tx in l["spans"]:
                if "Bold" in f:
                    name += tx
                elif tx.strip() == "":
                    name += tx
                else:
                    break
            name = name.strip().rstrip(".").strip()
            # es inicio de rasgo solo si el span siguiente continua en la misma linea o es el unico texto
            cur = {"name": name, "_lines": [l]}
            traits.append(cur)
            continue
        if cur is None:
            continue
        cur["_lines"].append(l)
    return traits


def species_entries(raw):
    res = []
    for sp in raw:
        sid = "species." + slug(sp["name"])
        # saltar la frase "As a X, you have these special traits." (primera linea Cambria sin negrita)
        rest = sp.pop("_rest")
        k = 0
        while k < len(rest) and not any("Bold" in s[0] for s in rest[k]["spans"] if s[2].strip()):
            k += 1
        # las tablas (Draconic Ancestors...) llegan como lineas GillSans dentro del ultimo rasgo
        traits_raw = split_traits(rest[k:])
        traits = []
        seen = {}
        for t in traits_raw:
            txt = texto.render(t["_lines"])
            # quitar el nombre inicial "Nombre. "
            nm = t["name"]
            pref = nm + "."
            if txt.startswith(pref):
                txt = txt[len(pref):].lstrip()
            tid = sid + "." + slug(nm)
            n = seen.get(tid, 0)
            seen[tid] = n + 1
            if n:
                tid += "-%d" % (n + 1)
            traits.append({"id": tid, "name": nm, "text": txt})
        res.append({"id": sid, "name": sp["name"], "size": sp["size"], "speed": sp["speed"],
                    "creature_type": sp["creature_type"], "traits": traits})
    return res


# ---------------------------------------------------------------- dotes
def parse_feats(sec_lines):
    feats = []
    cat_map = {"Origin Feats": "origin", "General Feats": "general",
               "Fighting Style Feats": "fighting_style", "Epic Boon Feats": "epic_boon"}
    blocks = headings_blocks(sec_lines, {14.0})
    for cb in blocks:
        if cb["title"] not in cat_map:
            continue
        cat = cat_map[cb["title"]]
        for fb in headings_blocks(cb["body"], {12.0}):
            if fb["size"] != 12.0:
                continue
            body = fb["body"]
            # linea(s) cursivas con "<Categoria> Feat (Prerequisite: ...)"
            it = []
            k = 0
            while k < len(body) and body[k]["font"].startswith("Cambria-Italic"):
                it.append(body[k])
                k += 1
            hdr = ""
            for l in it:
                hdr = texto._join(hdr, l["text"]) if hdr else l["text"]
            m = re.search(r"\(Prerequisite:\s*(.*)\)\s*$", hdr.strip())
            prereq = m.group(1).strip() if m else None
            feats.append({"id": "feat." + slug(fb["title"]), "name": fb["title"], "category": cat,
                          "prerequisite": prereq, "text": texto.render(body[k:]), "_pg": fb["pg"]})
    return feats


# ---------------------------------------------------------------- conjuros
SPELL_HDR = re.compile(r"^(?:Level (\d) ([A-Z][a-z]+)|([A-Z][a-z]+) Cantrip)\s*\((.*)\)\s*$")


def parse_spells(sec_lines):
    # empezar en "Spell Descriptions"
    start = 0
    for i, l in enumerate(sec_lines):
        if is_h(l, 18.0) and l["text"].strip() == "Spell Descriptions":
            start = i + 1
            break
    ls_all = sec_lines[start:]
    # bloques de estadisticas de criaturas: se sacan del flujo y se reasignan al conjuro que los nombra
    stat_runs, ls, run = [], [], None
    for l in ls_all:
        if texto.is_stat(l):
            if run is None:
                run = []
                stat_runs.append(run)
            run.append(l)
        else:
            run = None
            ls.append(l)
    # localizar titulos: linea negrita GillSans cuya siguiente linea cursiva (Cambria-Italic) cumple SPELL_HDR
    idxs = []
    i = 0
    n = len(ls)
    while i < n - 1:
        l = ls[i]
        if l["font"].startswith("GillSans-SemiBold") and ls[i + 1]["font"].startswith("Cambria-Italic"):
            hdr = ls[i + 1]["text"].strip()
            j = i + 2
            while j < n and ls[j]["font"].startswith("Cambria-Italic") and not SPELL_HDR.match(hdr):
                hdr = texto._join(hdr, ls[j]["text"])
                j += 1
            # puede haber un cierre ")" en otra linea cursiva
            hdr2 = hdr
            while not SPELL_HDR.match(hdr2) and j < n and ls[j]["font"].startswith("Cambria-Italic"):
                hdr2 = texto._join(hdr2, ls[j]["text"])
                j += 1
            if SPELL_HDR.match(hdr2.strip()):
                idxs.append((i, j, l["text"].strip(), hdr2.strip(), l["pg"]))
                i = j
                continue
        i += 1
    spells = []
    for k, (i, j, name, hdr, pg) in enumerate(idxs):
        end = idxs[k + 1][0] if k + 1 < len(idxs) else n
        body = ls[j:end]
        m = SPELL_HDR.match(hdr)
        if m.group(1):
            level, school = int(m.group(1)), m.group(2)
        else:
            level, school = 0, m.group(3)
        classes = [c.strip() for c in m.group(4).split(",")]
        # campos: Casting Time / Range / Components / Duration (GillSans 9.5)
        fields = {}
        cur = None
        p = 0
        while p < len(body):
            t = body[p]["text"].strip()
            mm = re.match(r"(Casting Time|Range|Components?|Duration):\s*(.*)$", t)
            if mm:
                cur = "Components" if mm.group(1).startswith("Component") else mm.group(1)
                fields[cur] = mm.group(2)
            elif cur and body[p]["font"].startswith("GillSans"):
                fields[cur] = texto._join(fields[cur], t)
            else:
                break
            p += 1
        rest = body[p:]
        # separar "Using a Higher-Level Spell Slot." / "Cantrip Upgrade." (ultimo parrafo en negrita-cursiva)
        higher = None
        cut = None
        for q, l in enumerate(rest):
            sp = [s for s in l["spans"] if s[2].strip()]
            if sp and "Bold" in sp[0][0] and re.match(r"\s*(Using a Higher-Level Spell Slot|Cantrip Upgrade)\.", "".join(s[2] for s in sp)):
                cut = q
        text_lines = rest if cut is None else rest[:cut]
        hl_lines = [] if cut is None else rest[cut:]
        ct = fields.get("Casting Time", "")
        dur = fields.get("Duration", "")
        spells.append({
            "id": "spell." + slug(name), "name": name, "level": level, "school": school,
            "casting_time": ct, "range": fields.get("Range", ""), "components": fields.get("Components", ""),
            "duration": dur, "ritual": "Ritual" in ct, "concentration": dur.startswith("Concentration"),
            "classes": classes, "text": texto.render(text_lines),
            "higher_levels": texto.render(hl_lines) if hl_lines else None, "_pg": pg,
        })
    for run in stat_runs:
        title = next((x["text"].strip() for x in run if x["size"] == 14.8), None)
        if title is None:
            continue
        sb = texto.render_statblock(run)
        target = [sp for sp in spells if title in sp["text"] or title in (sp["higher_levels"] or "")]
        if len(target) != 1:
            print("AVISO: bloque", title, "-> conjuros", [t["name"] for t in target])
            continue
        target[0]["text"] += "\n" + sb
    return spells


# ---------------------------------------------------------------- armas
def parse_weapons(lines):
    # tabla "Weapons" (10.5) con columnas Name/Damage/Properties/Mastery/Weight/Cost
    start = None
    for i, l in enumerate(lines):
        if is_h(l, 10.5) and l["text"].strip() == "Weapons" and l["pg"] >= 90:
            start = i
            break
    tl = []
    for l in lines[start + 1:]:
        if l["font"].startswith("Cambria") or (is_gs(l) and l["size"] in (12.0, 14.0, 18.0)):
            break
        tl.append(l)
    # filas: agrupar por (pagina, y) - cada fila tiene celdas en c1 y c2
    rows = []
    cur_cat = cur_kind = None
    by_page = {}
    for l in tl:
        by_page.setdefault(l["pg"], []).append(l)
    weapons = []
    for pg, ls in by_page.items():
        ls = [l for l in ls if l["size"] in (9.2, 9.5)]
        ls.sort(key=lambda l: (round(l["y"]), l["x"]))
        grouped = []
        for l in ls:
            if grouped and abs(l["y"] - grouped[-1][0]) <= 3.5:
                grouped[-1][1].append(l)
            else:
                grouped.append([l["y"], [l]])
        for y, cells in grouped:
            cells.sort(key=lambda l: l["x"])
            txts = [c["text"].strip() for c in cells]
            if len(cells) == 1 and cells[0]["ital"]:
                h = txts[0]
                cur_cat = "simple" if h.startswith("Simple") else "martial"
                cur_kind = "melee" if "Melee" in h else "ranged"
                continue
            if cells[0]["bold"]:
                continue   # cabecera
            rows.append((pg, y, cells))
    # unir filas de continuacion (propiedades que se parten en dos lineas)
    # cada fila valida tiene 6 celdas; las de continuacion tienen 1 celda a la altura de 'Properties'
    return rows, tl


def weapons_from_table(lines):
    rows, tl = parse_weapons(lines)
    # reconstruir con categoria
    weapons = []
    cur_cat = cur_kind = None
    # recorrer tl en orden y construir filas por pagina/y
    byp = {}
    for l in tl:
        if l["size"] in (9.2, 9.5):
            byp.setdefault(l["pg"], []).append(l)
    for pg in sorted(byp):
        ls = sorted(byp[pg], key=lambda l: (round(l["y"]), l["x"]))
        grouped = []
        for l in ls:
            if grouped and abs(l["y"] - grouped[-1][0]) <= 3.5:
                grouped[-1][1].append(l)
            else:
                grouped.append([l["y"], [l]])
        for y, cells in grouped:
            cells.sort(key=lambda l: l["x"])
            if len(cells) == 1 and cells[0]["ital"]:
                h = cells[0]["text"].strip()
                cur_cat = "simple" if h.startswith("Simple") else "martial"
                cur_kind = "melee" if "Melee" in h else "ranged"
                continue
            if any(c["bold"] for c in cells):
                continue
            if len(cells) >= 5:
                weapons.append({"cat": cur_cat, "kind": cur_kind, "cells": [c["text"].strip() for c in cells],
                                "xs": [c["x"] for c in cells], "y": y, "pg": pg})
            elif weapons and weapons[-1]["pg"] == pg:
                # continuacion de propiedades
                weapons[-1]["cont"] = weapons[-1].get("cont", []) + [c["text"].strip() for c in cells]
    out = []
    for w in weapons:
        c = w["cells"]
        name, dmg, props = c[0], c[1], c[2]
        mastery, weight, cost = c[3], c[4], c[5] if len(c) > 5 else ""
        if len(c) == 5:
            mastery, weight, cost = c[2], c[3], c[4]
            props = ""
        for extra in w.get("cont", []):
            props = texto._join(props, extra) if props else extra
        m = re.match(r"(\S+)\s+(.*)$", dmg)
        damage, dtype = (m.group(1), m.group(2).lower()) if m else (dmg, None)
        plist, versatile, rng = [], None, None
        if props.strip() in ("\u2014", "-", ""):
            props = ""
        # separar por comas fuera de parentesis
        depth, curp, parts = 0, "", []
        for ch in props:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(curp.strip())
                curp = ""
            else:
                curp += ch
        if curp.strip():
            parts.append(curp.strip())
        for p in parts:
            mm = re.match(r"([A-Za-z\- ]+?)\s*(?:\((.*)\))?$", p)
            nm = mm.group(1).strip() if mm else p
            arg = mm.group(2) if mm else None
            plist.append(nm)
            if nm == "Versatile" and arg:
                versatile = arg
            if arg and arg.startswith("Range"):
                mr = re.search(r"(\d+/\d+)", arg)
                rng = mr.group(1) if mr else None
        out.append({"id": "weapon." + slug(name), "name": name, "category": w["cat"], "kind": w["kind"],
                    "damage": damage, "damage_type": dtype, "properties": plist,
                    "properties_text": props or None, "versatile": versatile,
                    "range": rng, "mastery": mastery, "weight": weight, "cost": cost})
    return out


def main():
    pdf = sys.argv[1] if len(sys.argv) > 1 else PDF
    out = sys.argv[2] if len(sys.argv) > 2 else OUT
    os.makedirs(out, exist_ok=True)
    lines = srdlines.load(pdf)
    texto.build_hyphen_words(lines)
    # texto plano para fidelidad
    with open(os.path.join(RAIZ, "fuentes", "srd521-en.txt"), "w", encoding="utf-8") as f:
        pg = 0
        for l in lines:
            if l["pg"] != pg:
                f.write("\f")
                pg = l["pg"]
            f.write("p%d\t" % l["pg"] + l["text"].rstrip() + "\n")
    secs = split_sections(lines)
    print("secciones:", list(secs))
    classes, subclasses = parse_classes(secs["Classes"], out)
    for c in classes:
        render_feature_bodies(c["features"])
    for s in subclasses:
        s.pop("intro", None)
        render_feature_bodies(s["features"])
    fix_ids(classes, subclasses)
    species = species_entries(parse_species(secs["Character Origins"]))
    feats = parse_feats(secs["Feats"])
    spells = parse_spells(secs["Spells"])
    weapons = weapons_from_table(secs["Equipment"])
    for lst in (classes, subclasses, species, feats, spells, weapons):
        for e in lst:
            e.pop("_pg", None)
            for f in e.get("features", []) + e.get("traits", []):
                f.pop("_pg", None)
    data = {"classes": classes, "subclasses": subclasses, "species": species, "feats": feats,
            "spells": spells, "weapons": weapons}
    for k, v in data.items():
        with open(os.path.join(out, k + ".json"), "w", encoding="utf-8") as f:
            json.dump(v, f, ensure_ascii=False, indent=1)
        print(k, len(v))
    write_meta(pdf, out, lines, data)


def write_meta(pdf, out, lines, data):
    """meta.json: la atribucion se copia textual de la pagina legal del PDF (pagina 1)."""
    import hashlib
    import datetime
    p1 = [l["text"] for l in lines if l["pg"] == 1]
    a = next(i for i, t in enumerate(p1) if "This work includes material" in t)
    b = next(i for i, t in enumerate(p1) if t.strip().endswith("legalcode."))
    attr = ""
    for t in p1[a:b + 1]:
        t = t.replace("\t", "").strip()
        attr = attr + t if (attr.endswith("/") or not attr) else attr + " " + t
    h = hashlib.sha256(open(pdf, "rb").read()).hexdigest()
    meta = {"source": "System Reference Document 5.2.1", "version": "5.2.1", "language": "en",
            "license": "CC-BY-4.0", "attribution": attr, "sha256": h,
            "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "counts": {k: len(v) for k, v in data.items()}}
    with open(os.path.join(out, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
