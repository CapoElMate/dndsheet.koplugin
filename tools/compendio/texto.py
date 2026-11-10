"""Convierte lineas del SRD (srdlines) en texto plano: parrafos, vinetas y tablas.

Reglas:
  - Parrafo nuevo: la linea empieza con tabulacion, con vineta, o la anterior termino corta.
  - Vinetas: "- ".
  - Guion de corte de linea ("Ar-" + "mor"): se une sin guion, salvo que la palabra con guion
    exista en el documento (por ejemplo "two-handed").
  - Tablas (titulo GillSans 10.5 negrita + celdas 9.2/9.5): lineas "titulo" y "celda | celda".
El texto se copia del SRD sin resumir ni traducir.
"""
import re

HYPHEN_WORDS = set()   # palabras con guion legitimo, se rellena con build_hyphen_words


def build_hyphen_words(lines):
    pat = re.compile(r"[A-Za-z’']+(?:-[A-Za-z’']+)+")
    for l in lines:
        t = l["text"].rstrip()
        if t.endswith("-"):
            t = t[:-1]
        for m in pat.finditer(t):
            HYPHEN_WORDS.add(m.group(0).lower())


def is_table_line(l):
    f = l["font"]
    return f.startswith("GillSans") and l["size"] in (9.2, 9.5, 8.0, 10.5) and not f.startswith("Cambria")


def is_table_title(l):
    return l["font"].startswith("GillSans-SemiBold") and l["size"] == 10.5


def is_sidebar(l):
    return l["font"].startswith("GillSans") and (abs(l["size"] - 7.7) < 0.05 or l["size"] == 9.0)


def _join(prev, nxt):
    """Une dos lineas consecutivas del mismo parrafo."""
    prev = prev.rstrip()
    nxt = nxt.lstrip()
    if prev.endswith("\u00ad"):
        return prev[:-1] + nxt
    if prev.endswith("-") and len(prev) > 1 and prev[-2].isdigit() and nxt[:1].isalpha():
        return prev + nxt           # "10-" + "foot" -> "10-foot"
    if prev.endswith("-") and len(prev) > 1 and prev[-2].isalpha() and nxt[:1].islower():
        # palabra cortada al final de linea
        left = re.search(r"[A-Za-z’']+$", prev[:-1])
        right = re.match(r"[A-Za-z’']+", nxt)
        if left and right:
            with_hyphen = (left.group(0) + "-" + right.group(0)).lower()
            if with_hyphen in HYPHEN_WORDS:
                return prev + nxt
        return prev[:-1] + nxt
    return prev + " " + nxt


def _clean(text):
    return text.replace("\t", " ").replace(" ", " ").strip()


def _merge_headers(rows_lines):
    """Une las lineas de cabecera (negrita) en una sola linea por columna."""
    hdr = sorted([l for l in rows_lines if l["bold"]], key=lambda l: l["x"])
    rest = [l for l in rows_lines if not l["bold"]]
    cols = []
    for l in hdr:
        for c in cols:
            if abs(c[0]["x"] - l["x"]) <= 20 and l["y"] > c[-1]["y"] and l["y"] - c[-1]["y"] <= 14:
                c.append(l)
                break
        else:
            cols.append([l])
    merged = []
    for c in cols:
        c.sort(key=lambda l: l["y"])
        t = c[0]["text"].strip()
        for m in c[1:]:
            t = t + " " + m["text"].strip()
        d = dict(c[0])
        d["text"] = t
        d["y"] = c[-1]["y"]
        merged.append(d)
    return merged + rest


def _group_table(rows_lines):
    """Agrupa las lineas de una tabla en filas de celdas. Devuelve lista de listas de str."""
    rows_lines = _merge_headers(rows_lines)
    ls = sorted(rows_lines, key=lambda l: (round(l["y"]), l["x"]))
    min_x = min(l["x"] for l in ls)
    rows = []   # cada fila: {"y":..., "cells":[(x, text)]}
    for l in ls:
        if rows and abs(l["y"] - rows[-1]["y"]) <= 3.5:
            rows[-1]["cells"].append((l["x"], l["text"]))
            continue
        rows.append({"y": l["y"], "cells": [(l["x"], l["text"])]})
    # filas de continuacion: no tienen celda en la primera columna
    ncols = max(len(r["cells"]) for r in rows) if rows else 0
    out = []
    for r in rows:
        r["cells"].sort()
        first_x = r["cells"][0][0]
        if out and first_x > min_x + 12 and len(r["cells"]) < ncols and r["y"] - out[-1]["y"] <= 14:
            prev = out[-1]
            for cx, ct in r["cells"]:
                # celda de la fila anterior mas cercana por x (la de x mayor <= cx + 3)
                best = None
                for i, (px, pt) in enumerate(prev["cells"]):
                    if px <= cx + 6:
                        best = i
                if best is None:
                    best = 0
                px, pt = prev["cells"][best]
                prev["cells"][best] = (px, _join(pt, ct))
            prev["y"] = r["y"]
            continue
        out.append(r)
    return [[_clean(t) for _, t in r["cells"]] for r in out]


def render_table(title, tlines, skip_header_dupes=True):
    rows = _group_table(tlines) if tlines else []
    out = []
    if title:
        out.append(_clean(title))
    for cells in rows:
        out.append(" | ".join(c for c in cells if c != ""))
    return out


def render(lines, drop_sidebars=True):
    """lines: lista de dicts en orden. Devuelve el texto plano (str)."""
    # margen izquierdo de cada (pagina, columna)
    base = {}
    for l in lines:
        if l["font"].startswith("Cambria") and l["size"] == 10.0:
            k = (l["pg"], l["col"])
            base[k] = min(base.get(k, 9999), l["x"])
    out = []          # lista de parrafos / lineas de tabla ya listas
    cur = None        # parrafo en construccion
    prev_line = None
    i = 0
    n = len(lines)
    while i < n:
        l = lines[i]
        if drop_sidebars and is_sidebar(l):
            i += 1
            continue
        if is_table_title(l) or (is_table_line(l) and l["size"] in (9.2, 9.5)):
            # bloque de tabla: titulo opcional + celdas
            title = None
            if is_table_title(l):
                title = l["text"]
                i += 1
            tl = []
            while i < n and is_table_line(lines[i]) and not is_table_title(lines[i]) and not lines[i]["font"].startswith("Cambria"):
                tl.append(lines[i])
                i += 1
            if title is not None and re.search(r"Features$", title.strip()):
                continue    # tabla de rasgos de clase: se descarta sin cortar el parrafo
            if cur is not None:
                out.append(cur)
                cur = None
            out.extend(render_table(title, tl))
            prev_line = None
            continue
        t = l["text"]
        is_bullet = t.lstrip().startswith("•")
        starts_tab = t.startswith("\t") or t.startswith(" \t")
        k = (l["pg"], l["col"])
        sp = [x for x in l["spans"] if x[2].strip()]
        run_in = (bool(sp) and "Bold" in sp[0][0] and l["font"].startswith("Cambria")
                  and (prev_line is None or re.search(r"[.!?:;”\")]\s*$", prev_line["text"]) is not None))
        after_bullet = cur is not None and cur.startswith("- ") and not is_bullet and l["x"] <= base.get(k, 0) + 3
        after_formula = prev_line is not None and prev_line["font"].startswith("GillSans")
        after_cost = prev_line is not None and prev_line["text"].startswith(("Cost:", "Prerequisite")) and prev_line["ital"]
        new_par = cur is None or is_bullet or starts_tab or run_in or after_bullet or after_formula or after_cost
        # formulas / lineas GillSans 10.0 sueltas: siempre parrafo propio
        if l["font"].startswith("GillSans") and l["size"] == 10.0 and not l["bold"]:
            new_par = True
        body = _clean(re.sub(r"^\s*•\s*", "", t)) if is_bullet else _clean(t)
        if new_par:
            if cur is not None:
                out.append(cur)
            cur = ("- " + body) if is_bullet else body
        else:
            cur = _join(cur, body)
        prev_line = l
        i += 1
    if cur is not None:
        out.append(cur)
    return "\n".join(p for p in out if p != "")


STAT_KEYS = ("AC ", "HP ", "Speed ", "Senses ", "Languages ", "CR ", "Skills ", "Resistances ", "Immunities ", "Gear ", "Initiative ")


def is_stat(l):
    f = l["font"]
    return (f.startswith("Optima") or l["size"] in (14.8, 6.0, 6.8, 9.8)
            or (f == "GillSans" and l["size"] == 12.0))


def render_statblock(lines):
    """Bloque de estadisticas de criatura (conjuros que invocan): una linea por dato, texto copiado tal cual."""
    out = []
    cur = None
    # filas por y (solo para tablas de atributos: lineas chicas 6.0 / 6.8 / 9.8)
    i = 0
    n = len(lines)
    while i < n:
        l = lines[i]
        t = _clean(l["text"])
        if l["size"] == 6.0:
            i += 1
            continue
        if l["size"] in (6.8, 9.8):
            # fila de atributos: juntar todo lo que este a la misma altura
            row = [l]
            j = i + 1
            while j < n and lines[j]["size"] in (6.8, 9.8) and abs(lines[j]["y"] - l["y"]) <= 3.5:
                row.append(lines[j])
                j += 1
            row.sort(key=lambda r: r["x"])
            txt = re.sub(r" {2,}", " ", " ".join(_clean(r["text"]) for r in row))
            txt = re.sub(r"\s+(?=(Str|Dex|Con|Int|Wis|Cha)\b)", " | ", txt).strip(" |")
            if cur is not None:
                out.append(cur)
                cur = None
            out.append(txt)
            i = j
            continue
        if l["size"] == 14.8 or (l["font"] == "GillSans" and l["size"] == 12.0):
            if cur is not None:
                out.append(cur)
                cur = None
            out.append(t)
            i += 1
            continue
        if l["font"].startswith("Optima-Italic") and l["size"] == 9.0:
            if cur is not None:
                out.append(cur)
            cur = t
            i += 1
            continue
        starts_new = False
        if l["size"] == 9.0:
            starts_new = t.startswith(STAT_KEYS)
        else:
            starts_new = "BoldItalic" in l["font"]
        if cur is None or starts_new:
            if cur is not None:
                out.append(cur)
            cur = t
        else:
            cur = _join(cur, t)
        i += 1
    if cur is not None:
        out.append(cur)
    return "\n".join(out)


def strip_feature_tables(lines):
    """Quita las tablas 'X Features' (rasgos por nivel de cada clase); el resto queda igual."""
    out = []
    i, n = 0, len(lines)
    while i < n:
        l = lines[i]
        if is_table_title(l) and re.search(r"Features$", l["text"].strip()):
            i += 1
            while i < n and is_table_line(lines[i]) and not is_table_title(lines[i]) and not lines[i]["font"].startswith("Cambria"):
                i += 1
            continue
        out.append(l)
        i += 1
    return out
