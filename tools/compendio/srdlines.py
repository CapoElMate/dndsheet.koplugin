"""Linealiza el SRD 5.2.1 (PDF) en lineas con estilo, en orden de lectura por columnas.

Uso como modulo: lines = srdlines.load(pdf) -> lista de dicts
  {pg (1-based), col (0/1/2), y, x, size, bold, ital, font, text}
"""
import pymupdf

MID = 297.0  # mitad de la pagina (594 pt de ancho)


def _line_info(line):
    spans = [s for s in line["spans"] if s["text"] != ""]
    if not spans:
        return None
    text = "".join(s["text"] for s in line["spans"])
    # estilo: el del span con mas caracteres no blancos
    main = max(spans, key=lambda s: len(s["text"].strip()))
    f = main["font"]
    return {
        "x": line["bbox"][0], "x1": line["bbox"][2], "y": line["bbox"][1],
        "size": round(main["size"], 1), "font": f,
        "bold": ("Bold" in f or "SemiBold" in f),
        "ital": ("Italic" in f),
        "text": text,
        "spans": [(s["font"], round(s["size"], 1), s["text"]) for s in line["spans"]],
    }


ROTADAS = []   # paginas cuyo flujo traia la columna derecha antes que la izquierda


def _es_lateral(li):
    return li["font"].startswith("GillSans") and (abs(li["size"] - 7.7) < 0.05 or li["size"] == 9.0)


def _ordenar(page_lines):
    """Si el flujo de la pagina es [col 2 completa, col 1 completa], las invierte (lectura natural)."""
    runs = []
    for l in page_lines:
        if l["col"] in (1, 2) and not _es_lateral(l):
            if not runs or runs[-1] != l["col"]:
                runs.append(l["col"])
    if runs in ([2, 1], [1, 2, 1]) and 107 <= page_lines[0]["pg"] <= 175:   # paginas de conjuros
        ROTADAS.append(page_lines[0]["pg"])
        c0 = [l for l in page_lines if l["col"] == 0]   # (no hay lineas de ancho completo en esas paginas)
        c1 = [l for l in page_lines if l["col"] == 1]
        c2 = [l for l in page_lines if l["col"] == 2]
        return c0 + c1 + c2
    return page_lines


MOVIDAS = []   # (pagina, titulo) de tablas reubicadas


def _es_celda(l):
    return l["font"].startswith("GillSans") and l["size"] in (9.2, 9.5, 8.0, 10.5)


def _reubicar_tablas(pl):
    """Una tabla que el PDF emite al final de la pagina pero que esta visualmente ARRIBA de texto que ya salio
    en el flujo (misma columna) se vuelve a poner justo antes de ese texto."""
    i = 0
    while i < len(pl):
        l = pl[i]
        if (l["font"].startswith("GillSans-SemiBold") and l["size"] == 10.5 and i > 0
                and not l["text"].strip().endswith("Features")):
            j = i + 1
            while j < len(pl) and _es_celda(pl[j]) and not (pl[j]["size"] == 10.5 and pl[j]["font"].startswith("GillSans-SemiBold")):
                j += 1
            run = pl[i:j]
            col = l["col"]
            top = l["y"]
            target = None
            for k in range(0, i):
                m = pl[k]
                if m["col"] == col and not _es_celda(m) and m["y"] > top + 3 and m["font"].startswith("Cambria"):
                    target = k
                    break
            if target is not None:
                MOVIDAS.append((l["pg"], l["text"].strip()))
                pl = pl[:target] + run + pl[target:i] + pl[j:]
                i = target + len(run)
                continue
            i = j
            continue
        i += 1
    return pl


def load(pdf_path, first=0, last=None):
    """Lineas en el orden nativo del flujo del PDF (ya sigue la lectura por columnas)."""
    doc = pymupdf.open(pdf_path)
    out = []
    n = len(doc)
    for pn in range(first, n if last is None else last):
        page_lines = []
        for b in doc[pn].get_text("dict")["blocks"]:
            if b["type"] != 0:
                continue
            for l in b["lines"]:
                li = _line_info(l)
                if li is None or li["text"].strip() == "" or li["y"] > 735:
                    continue
                li["pg"] = pn + 1
                if li["x"] < MID - 20 and li["x1"] > MID + 20:
                    li["col"] = 0
                elif li["x"] < MID - 5:
                    li["col"] = 1
                else:
                    li["col"] = 2
                page_lines.append(li)
        if page_lines:
            out.extend(_reubicar_tablas(_ordenar(page_lines)))
    return out


if __name__ == "__main__":
    import sys
    a, b = int(sys.argv[2]), int(sys.argv[3])
    for l in load(sys.argv[1], a - 1, b):
        flag = ("B" if l["bold"] else "-") + ("I" if l["ital"] else "-")
        print("p%d c%d y%3d %s%4.1f %s| %s" % (l["pg"], l["col"], l["y"], flag, l["size"], l["font"][:10], l["text"]))
