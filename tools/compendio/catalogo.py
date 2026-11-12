#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Genera format/catalogo/*.json: lo que NO está en el SRD, solo con datos de catálogo (WEB.md §5.1).

Lee los libros del usuario en fuentes/ SOLO para extraer, con una lista blanca de campos:
  todos      nombre, fuente, edicion
  subclase   clase, nivel (en que se elige en su libro)
  especie    reemplazada_por (opcional)
  conjuro    nivel, escuela, clases, ritual, concentracion
Prohibido: descripciones, nombres de rasgos, tablas, páginas, cualquier texto de los libros.
Si falta un libro (o no tiene capa de texto), se salta ese archivo y se avisa.
No escribe temporales: todo se procesa en memoria.

Uso: python3 tools/compendio/catalogo.py [--fuentes fuentes] [--salida format/catalogo]
"""
import argparse
import difflib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from catalogo_datos import XGE_SPELLS  # noqa: E402
from catalogo_util import SCHOOLS, fold, level_from_header, ordinal_level, squish, title  # noqa: E402

try:
    import pymupdf
except ImportError:  # pragma: no cover
    import fitz as pymupdf  # type: ignore

ROOT = HERE.parent.parent
SRD = ROOT / "dndsheet.koplugin" / "compendium" / "srd521" / "en"

LIBROS = {
    "phb2014": dict(pdf="DD-Player-Handbook.pdf", fuente="PHB", edicion="2014",
                    libro="Player's Handbook (2014)"),
    "xge": dict(pdf="xanathar.pdf", fuente="XGE", edicion="2014", libro="Xanathar's Guide to Everything"),
    "tce": dict(pdf="Tashas_Cauldron_of_Everything.pdf", fuente="TCE", edicion="2014",
                libro="Tasha's Cauldron of Everything"),
    "motm": dict(pdf="mordenkainen-presents-monsters-of-the-multiverse_compress.pdf", fuente="MotM",
                 edicion="2014", libro="Mordenkainen Presents: Monsters of the Multiverse"),
    "mtof": dict(pdf="mordekainen tome of foes.pdf", fuente="MToF", edicion="2014",
                 libro="Mordenkainen's Tome of Foes"),
}

# Nivel en que cada clase elige subclase en los libros de 2014 (dato de las reglas, no del texto).
NIVEL_SUBCLASE = {
    "Artificer": 3, "Barbarian": 3, "Bard": 3, "Cleric": 1, "Druid": 2, "Fighter": 3, "Monk": 3,
    "Paladin": 3, "Ranger": 3, "Rogue": 3, "Sorcerer": 1, "Warlock": 1, "Wizard": 2,
}

# Nombres de subclases que se buscan en cada libro (clase -> nombres). Se VERIFICA que cada nombre
# aparezca en el texto del libro; los que no aparecen se descartan y se avisan.
SUBCLASES = {
    "phb2014": {  # "corto=nombre completo": el corto se busca en el libro; el completo es el que se publica
        "Barbarian": ["Berserker", "Totem Warrior=Path of the Totem Warrior"],
        "Bard": ["Lore", "Valor=College of Valor"],
        "Cleric": ["Knowledge=Knowledge Domain", "Life", "Light=Light Domain", "Nature=Nature Domain",
                   "Tempest=Tempest Domain", "Trickery=Trickery Domain", "War=War Domain"],
        "Druid": ["Land", "Moon=Circle of the Moon"],
        "Fighter": ["Champion", "Battle Master", "Eldritch Knight"],
        "Monk": ["Open Hand", "Shadow=Way of Shadow", "Four Elements=Way of the Four Elements"],
        "Paladin": ["Devotion", "Ancients=Oath of the Ancients", "Vengeance=Oath of Vengeance"],
        "Ranger": ["Hunter", "Beast Master"],
        "Rogue": ["Thief", "Assassin", "Arcane Trickster"],
        "Sorcerer": ["Draconic Bloodline", "Wild Magic"],
        "Warlock": ["Archfey=The Archfey", "Fiend", "Great Old One=The Great Old One"],
        "Wizard": ["Abjuration=School of Abjuration", "Conjuration=School of Conjuration",
                   "Divination=School of Divination", "Enchantment=School of Enchantment", "Evocation",
                   "Illusion=School of Illusion", "Necromancy=School of Necromancy",
                   "Transmutation=School of Transmutation"],
    },
    "xge": {
        "Barbarian": ["Path of the Ancestral Guardian", "Path of the Storm Herald", "Path of the Zealot"],
        "Bard": ["College of Glamour", "College of Swords", "College of Whispers"],
        "Cleric": ["Forge Domain", "Grave Domain"],
        "Druid": ["Circle of Dreams", "Circle of the Shepherd"],
        "Fighter": ["Arcane Archer", "Cavalier", "Samurai"],
        "Monk": ["Way of the Drunken Master", "Way of the Kensei", "Way of the Sun Soul"],
        "Paladin": ["Oath of Conquest", "Oath of Redemption"],
        "Ranger": ["Gloom Stalker", "Horizon Walker", "Monster Slayer"],
        "Rogue": ["Inquisitive", "Mastermind", "Scout", "Swashbuckler"],
        "Sorcerer": ["Divine Soul", "Shadow Magic", "Storm Sorcery"],
        "Warlock": ["The Celestial", "The Hexblade"],
        "Wizard": ["War Magic"],
    },
    "tce": {
        "Artificer": ["Alchemist", "Armorer", "Artillerist", "Battle Smith"],
        "Barbarian": ["Path of the Beast", "Path of Wild Magic"],
        "Bard": ["College of Creation", "College of Eloquence"],
        "Cleric": ["Order Domain", "Peace Domain", "Twilight Domain"],
        "Druid": ["Circle of Spores", "Circle of Stars", "Circle of Wildfire"],
        "Fighter": ["Psi Warrior", "Rune Knight"],
        "Monk": ["Way of Mercy", "Way of the Astral Self"],
        "Paladin": ["Oath of Glory", "Oath of the Watchers"],
        "Ranger": ["Fey Wanderer", "Swarmkeeper"],
        "Rogue": ["Phantom", "Soulknife"],
        "Sorcerer": ["Aberrant Mind", "Clockwork Soul"],
        "Warlock": ["The Fathomless", "The Genie"],
        "Wizard": ["Bladesinging", "Order of Scribes"],
    },
}

# Subclases de 2014 que el SRD 5.2.1 ya trae (con su nombre de 2024): no se duplican.
EN_SRD_2024 = {
    "Berserker", "Lore", "Life", "Land", "Champion", "Open Hand", "Devotion", "Hunter", "Thief",
    "Draconic Bloodline", "Fiend", "Evocation",
}

# Especies: las de cada libro que no son del SRD. `reemplazada_por`: MotM reemplaza a MToF.
ESPECIES_PHB = ["Dwarf", "Elf", "Halfling", "Human", "Dragonborn", "Gnome", "Half-Elf", "Half-Orc", "Tiefling"]

# Los nombres posesivos que el SRD 5.2.1 cambió (el resto se detecta quitando el posesivo).
ALIAS_SRD_CONJUROS = {
    "Bigby's Hand": "Arcane Hand", "Mordenkainen's Sword": "Arcane Sword",
    "Nystul's Magic Aura": "Arcanist's Magic Aura",
}

# Errores de OCR conocidos de los libros escaneados: squish(incorrecto) -> nombre correcto.
CORRECCIONES = {
    "causefear": "Cause Fear", "controlflames": "Control Flames", "controlflarnes": "Control Flames",
    "createbonfire": "Create Bonfire", "wordingwind": "Warding Wind", "wardingwind": "Warding Wind",
    "mentalprison": "Mental Prison", "mightyfortress": "Mighty Fortress",
    "negativeenergyflood": "Negative Energy Flood", "wallofsand": "Wall of Sand",
    "walloflight": "Wall of Light", "wallofwater": "Wall of Water", "iceknife": "Ice Knife",
    "lceknife": "Ice Knife", "lviindspike": "Mind Spike", "skvwrite": "Skywrite", "infestation": "Infestation",
    "lnvulnerability": "Invulnerability", "lnuulnerabiiity": "Invulnerability",
    "illusorydragon": "Illusory Dragon", "infernalcalling": "Infernal Calling",
    "lmmolation": "Immolation", "druidgrove": "Druid Grove", "massnolymorph": "Mass Polymorph",
    "masspoivmorph": "Mass Polymorph", "investitureofflame": "Investiture of Flame",
    "investitureofice": "Investiture of Ice", "investitureofstone": "Investiture of Stone",
    "investitureofwind": "Investiture of Wind", "lnvestitureofflame": "Investiture of Flame",
    "lnvestitureofice": "Investiture of Ice", "lnvestitureofstone": "Investiture of Stone",
    "lnvestitureofwind": "Investiture of Wind", "guardianofnature": "Guardian of Nature",
    "wrathofnature": "Wrath of Nature", "wordofradiance": "Word of Radiance",
    "templeofthegods": "Temple of the Gods", "bonesoftheearth": "Bones of the Earth",
    "shadowofmoil": "Shadow of Moil", "crownofstars": "Crown of Stars", "tidalwave": "Tidal Wave",
    "melfsminutemeteors": "Melf's Minute Meteors", "cloudkili": "Cloudkill",
    "destructivewave": "Destructive Wave",
}

# Clases de conjuros que la lista del libro escaneado no permitió leer.
CLASES_MANUAL = {"Destructive Wave": ["Paladin"]}

ESCUELAS_OK = set(SCHOOLS)


def avisar(msg):
    print(f"AVISO: {msg}", file=sys.stderr)


# ── SRD (lo que no hay que duplicar) ────────────────────────────────────────

def cargar_srd():
    def names(f):
        return {fold(e["name"]) for e in json.loads((SRD / f).read_text("utf-8"))}
    return {k: names(f"{k}.json") for k in ("spells", "species", "subclasses")}


def en_srd_conjuro(nombre, srd_spells):
    n = fold(nombre)
    if n in srd_spells:
        return True
    alias = ALIAS_SRD_CONJUROS.get(nombre)
    if alias and fold(alias) in srd_spells:
        return True
    # posesivo: "Melf's Acid Arrow" -> "Acid Arrow"
    m = re.match(r"^[A-Z][A-Za-z\-]+['’]s\s+(.+)$", nombre)
    return bool(m and fold(m.group(1)) in srd_spells)


# ── Lectura de PDF (en memoria) ─────────────────────────────────────────────

def paginas(pdf):
    doc = pymupdf.open(str(pdf))
    return doc, [doc[i].get_text() for i in range(doc.page_count)]


def tiene_texto(textos):
    muestra = textos[60:70] or textos
    return sum(len(t) for t in muestra) > 2000


# ── Subclases ────────────────────────────────────────────────────────────────

def subclases(clave, meta, texto_squish):
    out = []
    for clase, nombres in SUBCLASES.get(clave, {}).items():
        for n in nombres:
            n, _, completo = n.partition("=")
            if n in EN_SRD_2024:
                continue
            # el nombre tiene que figurar en el libro (sin espacios ni mayúsculas, por el ruido de OCR)
            if squish(n) not in texto_squish:
                avisar(f"{meta['fuente']}: subclase «{n}» no se encontró en el texto: se descarta")
                continue
            out.append(dict(nombre=completo or n, fuente=meta["fuente"], edicion=meta["edicion"], clase=clase,
                            nivel=NIVEL_SUBCLASE[clase]))
    return out


# ── Conjuros ─────────────────────────────────────────────────────────────────

def escuela_de(txt):
    t = fold(txt)
    for s in SCHOOLS:
        if s in t:
            return s.capitalize()
    mejor = difflib.get_close_matches(t, SCHOOLS, n=1, cutoff=0.75)
    return mejor[0].capitalize() if mejor else None


def parse_descripciones(textos, estilo):
    """Devuelve {squish(nombre): dict(nivel, escuela, ritual, concentracion)} desde las descripciones.

    estilo 'phb': nombre con letras separadas y la línea siguiente 'Nth-level escuela' o 'Escuela cantrip'.
    estilo 'caps': nombre en mayúsculas (XGE/TCE).
    """
    lineas = []
    for t in textos:
        lineas.extend(l.strip() for l in t.split("\n"))
    out = {}
    nivel_re = re.compile(
        r"^(?:(?P<lv>[0-9lIJ][a-z\-]{1,4}?)[\-—–\s]*level\s+(?P<s1>[A-Za-z]+)|(?P<s2>[A-Za-z]+)\s+cantrip)"
        r"(?:\s*\((?P<rit>[^)]*)\))?\s*$", re.I)
    for i in range(1, len(lineas) - 2):
        m = nivel_re.match(lineas[i].replace("—", "-"))
        if not m:
            m = re.match(r"^(?P<lv>\S{2,5})[\-—–]\s*(?:level|ievel|Ievel|leve1)\s+(?P<s1>[A-Za-z]+)(?:\s*\((?P<rit>[^)]*)\))?\s*$",
                         lineas[i], re.I)
        if not m:
            continue
        if not any(l.lower().startswith("casting time") for l in lineas[i + 1:i + 3]):
            continue
        nombre = lineas[i - 1]
        if len(nombre) < 3 or len(nombre) > 40:
            continue
        esc = escuela_de(m.groupdict().get("s1") or m.groupdict().get("s2") or "")
        if esc is None:
            continue
        nivel = 0 if m.groupdict().get("s2") else ordinal_level(m.group("lv")) if m.groupdict().get("lv") else None
        ritual = bool(m.groupdict().get("rit") and "rit" in m.group("rit").lower())
        conc = False
        for l in lineas[i + 1:i + 9]:
            if l.lower().startswith("duration"):
                conc = "oncentration" in l
                break
        out[squish(nombre)] = dict(nivel=nivel, escuela=esc, ritual=ritual, concentracion=conc, bruto=nombre)
    return out


def listas_phb(textos, pg0=187, pg1=191):
    """PHB 2014: listas por clase en flujo de texto: 'X Spells', encabezados de nivel y nombres."""
    clases = {}
    cls = None
    for t in textos[pg0:pg1 + 1]:
        for l in t.split("\n"):
            s = re.sub(r"\s+", " ", l).strip()
            comp = re.sub(r"\s+", "", s).lower()
            m = re.match(r"^(bard|cleric|druid|paladin|ranger|sorcerer|warlock|wizard)spells$", comp)
            if m:
                cls = m.group(1).capitalize()
                continue
            if cls is None or not s:
                continue
            if "level" in comp or comp.startswith("cantrips"):
                continue
            if re.match(r"^=+|^\d+$|^Chapter|^C h a p t e r|^Spells$", s) or len(s) > 40:
                continue
            nombre = re.sub(r"\s+o f\b", " of", s)
            nombre = re.sub(r"\bo f\s", "of ", nombre)
            clases.setdefault(squish(nombre), (nombre, set()))[1].add(cls)
    return clases


def listas_xge(doc, paginas_idx):
    """XGE: tres columnas por página, listas en flujo columna a columna entre páginas (escaneo con OCR)."""
    HD = re.compile(r"^[A-Z]+ SPELLS$")
    SP = re.compile(r"^(.*?)\s*\(\s*([A-Za-z ]+?)\s*(?:,\s*([A-Za-z]+))?\s*\)\s*$")
    clases = {}
    cls = None
    for pn in paginas_idx:
        blocks = [b for b in doc[pn].get_text("blocks") if (pn != paginas_idx[0] or b[1] > 400)]
        xs = sorted({round(b[0]) for b in blocks if re.search(r"LEVEL|SPELLS|CANTRIP", b[4].upper())})
        cols = []
        for x in xs:
            if not cols or x - cols[-1] > 60:
                cols.append(x)
        if not cols:
            continue

        def col(x):
            return min(range(len(cols)), key=lambda i: abs(cols[i] - x))
        flujo = []
        for b in blocks:
            ls = [l.strip() for l in b[4].split("\n") if l.strip()]
            hs = [l for l in ls if HD.match(l)]
            base = col(b[0])
            if len(hs) > 1:
                for i, l in enumerate(hs):
                    flujo.append((base + i, b[1], 0, l))
                continue
            for i, l in enumerate(ls):
                flujo.append((base, b[1], i, l))
        flujo.sort()
        for _c, _y, _i, l in flujo:
            if HD.match(l):
                cls = l.split()[0].title().replace("Sorgerer", "Sorcerer")
                continue
            if "LEVE" in l.upper() or "CANTRIP" in l.upper():
                continue
            m = SP.match(l)
            if m and cls and len(l) < 60:
                nombre = re.sub(r"\s+", " ", m.group(1)).strip()
                clases.setdefault(squish(nombre), (nombre, set()))[1].add(cls)
    return clases


def unir_conjuros(meta, desc, listas, srd_spells, nombres_desc=None):
    """Combina descripciones (nivel/escuela/ritual/concentración) con listas (clases)."""
    # emparejar nombres de las listas con los de las descripciones (difuso, por el ruido de OCR)
    claves = list(desc.keys())
    out = []
    usados = set()
    for sq, (nombre_lista, cl) in listas.items():
        k = sq if sq in desc else None
        if k is None:
            c = difflib.get_close_matches(sq, claves, n=1, cutoff=0.86)
            k = c[0] if c else None
        if k is None:
            avisar(f"{meta['fuente']}: «{nombre_lista}» está en una lista de clase pero no tiene descripción: se descarta")
            continue
        usados.add(k)
        d = desc[k]
        out.append((nombre_lista, d, set(cl)))
    for k, d in desc.items():
        if k not in usados:
            out.append((None, dict(d), set()))
    return out


def construir_conjuros(meta, entradas, srd_spells, nombre_de_desc):
    res = {}
    for nombre_lista, d, cl in entradas:
        nombre = nombre_lista or nombre_de_desc(d["bruto"])
        corr = CORRECCIONES.get(squish(nombre))
        nombre = corr or title(nombre)
        if d["nivel"] is None:
            avisar(f"{meta['fuente']}: «{nombre}» sin nivel reconocible: se descarta")
            continue
        if en_srd_conjuro(nombre, srd_spells):
            continue
        res[squish(nombre)] = dict(
            nombre=nombre, fuente=meta["fuente"], edicion=meta["edicion"], nivel=d["nivel"],
            escuela=d["escuela"], clases=sorted(cl or CLASES_MANUAL.get(nombre, [])), ritual=d["ritual"], concentracion=d["concentracion"])
    return sorted(res.values(), key=lambda s: (s["nivel"], s["nombre"]))


def nombre_caps(bruto):
    s = re.sub(r"\s+", " ", bruto).strip()
    s = s.replace("’", "'")
    return s


def conjuros_tce(textos, meta, srd_spells):
    """TCE: la tabla 'Spells' trae nivel, escuela, concentración, ritual y clases en columnas."""
    t = textos[105]
    ls = [l.strip() for l in t.split("\n")]
    try:
        i0 = ls.index("Cone.")
    except ValueError:
        i0 = ls.index("Conc.")
    filas = []
    i = i0 + 1
    while i + 3 < len(ls) and not ls[i].startswith("SPELLS"):
        lv, nm, sc, cn = ls[i:i + 4]
        filas.append((lv, nm, sc, cn))
        i += 4
    n = len(filas)
    j = ls.index("Ritual", i) + 1
    rit = ls[j:j + n]
    k = ls.index("Class", j) + 1
    cls = ls[k:k + n]
    desc = parse_descripciones(textos[106:117], "caps")
    out = []
    for (lv, nm, sc, cn), r, c in zip(filas, rit, cls):
        nivel = 0 if lv == "0" else ordinal_level(lv.replace("l st", "1st").replace("l", "1") if lv.startswith("l ") else lv)
        if nivel is None:
            mapa = {"l st": 1, "lst": 1}
            nivel = mapa.get(lv)
        nombre = title(nm.replace("’", "'"))
        if en_srd_conjuro(nombre, srd_spells):
            continue
        out.append(dict(nombre=nombre, fuente=meta["fuente"], edicion=meta["edicion"], nivel=nivel,
                        escuela=escuela_de(sc), clases=sorted(x.strip() for x in c.split(",") if x.strip()),
                        ritual=r.strip().lower().startswith("y"), concentracion=cn.strip().lower().startswith("y")))
    for s in out:
        if s["nivel"] is None or s["escuela"] is None:
            avisar(f"TCE: fila incompleta {s['nombre']}")
    del desc
    return sorted(out, key=lambda s: (s["nivel"] or 0, s["nombre"]))


# ── Especies ────────────────────────────────────────────────────────────────

def especies_phb(texto_squish, meta, srd_species):
    out = []
    for n in ESPECIES_PHB:
        if fold(n) in srd_species:
            continue
        if squish(n) not in texto_squish:
            avisar(f"PHB: especie «{n}» no se encontró: se descarta")
            continue
        out.append(dict(nombre=n, fuente=meta["fuente"], edicion=meta["edicion"]))
    return out


def especies_motm(doc, meta, srd_species):
    toc = doc.get_toc()
    ini = next(i for i, t in enumerate(toc) if t[1].startswith("Chapter 1"))
    fin = next(i for i, t in enumerate(toc) if t[1].startswith("Chapter 2"))
    out = []
    for lvl, nombre, _p in toc[ini + 1:fin]:
        if lvl != 3 or nombre.lower().startswith("creating"):
            continue
        if fold(nombre) in srd_species or fold(nombre.split(",")[0]) in srd_species:
            continue
        out.append(dict(nombre=nombre, fuente=meta["fuente"], edicion=meta["edicion"]))
    return out


def conjuros_tabla(meta, tabla, texto_squish, srd_spells, desc, lst):
    """Conjuros desde la tabla curada de catalogo_datos.py, verificados contra el PDF del usuario.

    Cada nombre tiene que figurar en el libro; nivel, escuela y clases se comparan con lo que se pudo
    leer (OCR) y las divergencias se avisan para revisión manual.
    """
    out = []
    for linea in tabla.strip().splitlines():
        nombre, nivel, escuela, clases, flags = linea.split("|")
        if en_srd_conjuro(nombre, srd_spells):
            continue
        if squish(nombre) not in texto_squish:
            avisar(f"{meta['fuente']}: conjuro «{nombre}» no se encontró en el texto: se descarta")
            continue
        sq = squish(nombre)
        clv = difflib.get_close_matches(sq, list(lst.keys()), n=1, cutoff=0.88)
        if clv:
            leidas = lst[clv[0]][1]
            if leidas != set(clases.split(",")):
                avisar(f"{meta['fuente']}: «{nombre}» clases tabla={sorted(clases.split(','))} libro={sorted(leidas)}")
        dsc = desc.get(sq)
        if dsc and (dsc["nivel"] != int(nivel) or dsc["escuela"] != escuela):
            avisar(f"{meta['fuente']}: «{nombre}» nivel/escuela tabla={nivel}/{escuela} libro={dsc['nivel']}/{dsc['escuela']}")
        out.append(dict(nombre=nombre, fuente=meta["fuente"], edicion=meta["edicion"], nivel=int(nivel),
                        escuela=escuela, clases=sorted(clases.split(",")), ritual="r" in flags,
                        concentracion="c" in flags))
    return sorted(out, key=lambda s: (s["nivel"], s["nombre"]))


def especies_mtof(doc, meta, srd_species, motm):
    """MToF: especies y subrazas jugables (por título del índice); las que MotM reemplazó se marcan."""
    nombres = ["Eladrin", "Sea Elf", "Shadar-kai", "Duergar", "Githyanki", "Githzerai", "Deep Gnome"]
    toc = " ".join(t[1] for t in doc.get_toc()).lower()
    texto = squish("".join(doc[i].get_text() for i in range(doc.page_count)))
    out = []
    for n in nombres:
        if fold(n) in srd_species:
            continue
        if squish(n) not in texto and n.lower() not in toc:
            avisar(f"MToF: especie «{n}» no se encontró: se descarta")
            continue
        e = dict(nombre=n, fuente=meta["fuente"], edicion=meta["edicion"])
        if fold(n) in motm:
            e["reemplazada_por"] = motm[fold(n)]
        out.append(e)
    return out


# ── Principal ────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fuentes", default=str(ROOT / "fuentes"))
    ap.add_argument("--salida", default=str(ROOT / "format" / "catalogo"))
    ap.add_argument("--solo", nargs="*", help="solo estos libros (claves de LIBROS)")
    a = ap.parse_args()
    fuentes, salida = Path(a.fuentes), Path(a.salida)
    salida.mkdir(parents=True, exist_ok=True)
    srd = cargar_srd()
    resumen = {}
    motm_nombres = {}

    for clave, meta in LIBROS.items():
        if a.solo and clave not in a.solo and clave != "motm":
            continue
        pdf = fuentes / meta["pdf"]
        if not pdf.exists():
            avisar(f"{meta['libro']}: no está {meta['pdf']}: se salta")
            continue
        doc, textos = paginas(pdf)
        if not tiene_texto(textos):
            avisar(f"{meta['libro']}: el PDF no tiene capa de texto (escaneo sin OCR): se salta")
            continue
        sq = squish("".join(textos))
        datos = dict(libro=meta["libro"], fuente=meta["fuente"], edicion=meta["edicion"],
                     subclasses=[], species=[], spells=[])
        datos["subclasses"] = subclases(clave, meta, sq)
        if clave == "phb2014":
            datos["species"] = especies_phb(sq, meta, srd["species"])
            desc = parse_descripciones(textos[188:260], "phb")
            lst = listas_phb(textos)
            ent = unir_conjuros(meta, desc, lst, srd["spells"])
            datos["spells"] = construir_conjuros(meta, ent, srd["spells"], nombre_caps)
        elif clave == "xge":
            desc = parse_descripciones(textos[150:175], "caps")
            lst = listas_xge(doc, [147, 148, 149])
            datos["spells"] = conjuros_tabla(meta, XGE_SPELLS, sq, srd["spells"], desc, lst)
        elif clave == "tce":
            datos["spells"] = conjuros_tce(textos, meta, srd["spells"])
        elif clave == "motm":
            datos["species"] = especies_motm(doc, meta, srd["species"])
        elif clave == "mtof":
            datos["species"] = especies_mtof(doc, meta, srd["species"], motm_nombres)
        if clave == "motm":
            motm_nombres = {fold(e["nombre"].split(",")[0]): e["nombre"] for e in datos["species"]}
        (salida / f"{clave}.json").write_text(json.dumps(datos, ensure_ascii=False, indent=1) + "\n", "utf-8")
        resumen[clave] = {k: len(v) for k, v in datos.items() if isinstance(v, list)}
    print(json.dumps(resumen, indent=1))


if __name__ == "__main__":
    main()
