-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Lista blanca del catálogo (format/catalogo/*.json): solo nombres y datos de catálogo, nunca texto de los libros.
local rapidjson = require("rapidjson")
local Compendium = require("dndsheet/compendium")

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local doc = assert(rapidjson.decode(f:read("*a")), path)
    f:close()
    return doc
end

-- el repo de desarrollo tiene format/ junto a dndsheet.koplugin/; el público lo tiene en la raíz del plugin
local function find_dir()
    for _i, d in ipairs({ "format/catalogo/", "../format/catalogo/" }) do
        if read(d .. "phb2014.json") then return d end
    end
    error("no encuentro format/catalogo/")
end

local FILES = { "phb2014", "xge", "tce", "motm", "mtof" }
local TOP = { libro = true, fuente = true, edicion = true, subclasses = true, species = true, spells = true }
local FIELDS = {
    subclasses = { nombre = true, fuente = true, edicion = true, clase = true, nivel = true },
    species = { nombre = true, fuente = true, edicion = true, reemplazada_por = true },
    spells = { nombre = true, fuente = true, edicion = true, nivel = true, escuela = true, clases = true,
               ritual = true, concentracion = true },
}
local SCHOOLS = { Abjuration = 1, Conjuration = 1, Divination = 1, Enchantment = 1, Evocation = 1,
                  Illusion = 1, Necromancy = 1, Transmutation = 1 }
local CLASSES = { Artificer = 1, Barbarian = 1, Bard = 1, Cleric = 1, Druid = 1, Fighter = 1, Monk = 1,
                  Paladin = 1, Ranger = 1, Rogue = 1, Sorcerer = 1, Warlock = 1, Wizard = 1 }
local SOURCES = { PHB = 1, XGE = 1, TCE = 1, MotM = 1, MToF = 1 }

local function short_text(v, where)
    assert(type(v) == "string" and v ~= "", where .. ": texto vacío o no es texto")
    assert(#v <= 60, where .. ": más de 60 caracteres")
    assert(not v:find("[%c]") and not v:find("  ", 1, true) and not v:find("^%s") and not v:find("%s$"),
        where .. ": caracteres raros")
end

local T = {}

function T.listas_blancas_y_formas()
    local dir = find_dir()
    local seen = 0
    for _i, name in ipairs(FILES) do
        local doc = read(dir .. name .. ".json")
        if doc then
            seen = seen + 1
            for k in pairs(doc) do assert(TOP[k], name .. ": campo no permitido " .. k) end
            short_text(doc.libro, name .. ".libro")
            assert(SOURCES[doc.fuente], name .. ": fuente")
            assert(doc.edicion == "2014" or doc.edicion == "2024", name .. ": edicion")
            for kind, allowed in pairs(FIELDS) do
                assert(type(doc[kind]) == "table", name .. ": falta la lista " .. kind)
                local names = {}
                for n, e in ipairs(doc[kind]) do
                    local w = string.format("%s.%s[%d]", name, kind, n)
                    for k, v in pairs(e) do
                        assert(allowed[k], w .. ": campo no permitido " .. k)
                        if type(v) == "string" then short_text(v, w .. "." .. k) end
                    end
                    short_text(e.nombre, w .. ".nombre")
                    assert(SOURCES[e.fuente] and e.fuente == doc.fuente, w .. ": fuente")
                    assert(e.edicion == doc.edicion, w .. ": edicion")
                    local key = Compendium.fold(e.nombre) .. "|" .. tostring(e.clase)
                    assert(not names[key], w .. ": nombre repetido")
                    names[key] = true
                    if kind == "subclasses" then
                        assert(CLASSES[e.clase], w .. ": clase")
                        assert(e.nivel == math.floor(e.nivel) and e.nivel >= 1 and e.nivel <= 3, w .. ": nivel")
                    elseif kind == "spells" then
                        assert(e.nivel == math.floor(e.nivel) and e.nivel >= 0 and e.nivel <= 9, w .. ": nivel")
                        assert(SCHOOLS[e.escuela], w .. ": escuela")
                        assert(type(e.clases) == "table" and #e.clases >= 1, w .. ": clases")
                        for _j, c in ipairs(e.clases) do assert(CLASSES[c], w .. ": clase " .. tostring(c)) end
                        assert(type(e.ritual) == "boolean" and type(e.concentracion) == "boolean", w .. ": banderas")
                    end
                end
            end
        end
    end
    assert(seen >= 1, "no hay ningún archivo de catálogo")
end

function T.no_duplica_lo_que_ya_esta_en_el_srd()
    local dir = find_dir()
    local srd_dir = (read("compendium/srd521/en/spells.json") and "compendium/srd521/en/")
        or "../compendium/srd521/en/"
    local srd = {}
    for _i, e in ipairs(read(srd_dir .. "spells.json") or {}) do srd[Compendium.fold(e.name)] = true end
    for _i, name in ipairs(FILES) do
        local doc = read(dir .. name .. ".json")
        for _j, e in ipairs(doc and doc.spells or {}) do
            assert(not srd[Compendium.fold(e.nombre)], name .. ": «" .. e.nombre .. "» ya está en el SRD")
        end
    end
end

function T.reemplazada_por_apunta_a_una_especie_de_motm()
    local dir = find_dir()
    local motm, mtof = read(dir .. "motm.json"), read(dir .. "mtof.json")
    if not (motm and mtof) then return end
    local names = {}
    for _i, e in ipairs(motm.species) do names[e.nombre] = true end
    for _i, e in ipairs(mtof.species) do
        if e.reemplazada_por then assert(names[e.reemplazada_por], e.nombre .. ": reemplazada_por inexistente") end
    end
end

return T
