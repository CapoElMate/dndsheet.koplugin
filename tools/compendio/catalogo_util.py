# SPDX-License-Identifier: AGPL-3.0-or-later
"""Utilidades del generador del catálogo (format/catalogo/).

Solo se extraen los campos de la lista blanca (WEB.md §5.1): nombre, fuente, edición, clase, nivel,
escuela, clases, ritual, concentración, reemplazada_por. Nunca descripciones ni nombres de rasgos.
"""
import re
import unicodedata

SMALL = {"of", "the", "and", "to", "in", "on", "for", "a", "an", "or", "at", "from", "with"}

SCHOOLS = ["abjuration", "conjuration", "divination", "enchantment", "evocation", "illusion",
           "necromancy", "transmutation"]


def fold(s):
    """Minúsculas, sin tildes ni signos: para comparar nombres."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("’", "'").replace("ﬁ", "fi").replace("ﬂ", "fl")
    return re.sub(r"[^a-z0-9]", "", s.lower())


def squish(s):
    return fold(s)


def title(s):
    """'wording wind' -> 'Wording Wind' (artículos y preposiciones en minúscula salvo al inicio)."""
    s = s.replace("’", "'").replace("ﬁ", "fi").replace("ﬂ", "fl")
    out = []
    for i, w in enumerate(re.split(r"(\s+|-|/)", s)):
        if not w or re.fullmatch(r"\s+|-|/", w):
            out.append(w)
            continue
        lw = w.lower()
        if i > 0 and lw in SMALL:
            out.append(lw)
        else:
            # apóstrofo: "tasha's" -> "Tasha's"; "mordenkainen's"
            out.append(lw[:1].upper() + lw[1:])
    return "".join(out)


def level_from_header(line):
    """Nivel de conjuro de un encabezado de lista ('CANTRIPS (0 LEVEL)', '3RD LEVEL', con ruido de OCR)."""
    u = re.sub(r"[^A-Za-z0-9\]]", "", line).upper()
    if u.startswith("CANTRIP"):
        return 0
    m = re.match(r"^(.{1,3}?)LEVE?L?$", u)
    if not m or "LEVE" not in u:
        return None
    lead = m.group(1)[:1]
    table = {"1": 1, "I": 1, "L": 1, "2": 2, "Z": 2, "3": 3, "4": 4, "5": 5, "S": 5, "6": 6, "7": 7, "]": 7,
             "J": 7, "8": 8, "9": 9}
    return table.get(lead)


def ordinal_level(text):
    """'3rd-level', '1st level' (con ruido) -> 3 / 1; 'cantrip' -> 0."""
    t = text.lower()
    if "cantrip" in t:
        return 0
    m = re.search(r"(\d)\s*(?:st|nd|rd|th)", t)
    if m:
        return int(m.group(1))
    return None


def despace(s):
    """'C o n t r o l W e a t h e r' no se puede recuperar; se usa solo para comparar (squish)."""
    return squish(s)
