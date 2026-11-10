-- SPDX-License-Identifier: AGPL-3.0-or-later
local Schema = require("dndsheet/schema")
local rapidjson = require("rapidjson")
local util = require("util")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

-- Comparación profunda que ignora metatablas (arrays marcados o no)
local function deep_eq(a, b, path)
    path = path or "$"
    if type(a) ~= type(b) then error(path .. ": tipos distintos " .. type(a) .. " / " .. type(b), 2) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
        return
    end
    for k, v in pairs(a) do deep_eq(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do
        if a[k] == nil then error(path .. "." .. tostring(k) .. ": falta", 2) end
    end
end

local function fixture(name)
    local raw = assert(util.readFromFile("tests/fixtures/" .. name, "rb"))
    return assert(rapidjson.decode(raw))
end

local T = {}

function T.normalize_vacio_es_valido()
    local d = Schema.normalize({})
    eq(#Schema.validate(d), 0)
    deep_eq(d, Schema.normalize(Schema.defaults()))
    eq(d.nivel, 1)
    eq(d.conjuros.aptitud, rapidjson.null)
end

function T.normalize_no_tabla()
    eq(type(Schema.normalize(nil)), "table")
    eq(type(Schema.normalize("x")), "table")
end

function T.normalize_plantilla_no_cambia()
    -- thalia.dnd es un archivo schema 1 auténtico (inspiracion booleana): migrate + normalize
    -- solo cambian meta.schema (3), inspiracion (true → 1) y la lista nueva rasgos_ref; el resto queda igual.
    local original = fixture("thalia.dnd")
    local d = Schema.normalize(Schema.migrate(fixture("thalia.dnd")))
    eq(d.inspiracion, 1)
    eq(d.meta.schema, 3)
    eq(#d.rasgos_ref, 0)
    original.inspiracion, original.meta.schema = 1, 3
    original.rasgos_ref = d.rasgos_ref
    deep_eq(d, original)
end

function T.plantilla_nuevo_coincide_con_defaults()
    local raw = assert(util.readFromFile("templates/nuevo.dnd", "rb"))
    deep_eq(assert(rapidjson.decode(raw)), Schema.normalize(Schema.defaults()))
end

function T.corrige_tipos_y_rangos()
    local d = Schema.normalize(fixture("tipos.dnd"))
    eq(d.nombre, "42")
    eq(d.nivel, 7)
    eq(d.ca, 15)
    eq(d.atributos.fue, 16)
    eq(d.atributos.des, 30)
    eq(d.atributos.con, 1)
    eq(d.atributos.int, 10)
    eq(d.atributos.sab, 10)
    eq(d.habilidades.sigilo, 0)
    eq(d.habilidades.acrobacias, 2)
    eq(d.muerte.fallos, 3)
    eq(d.muerte.exitos, 1)
    eq(d.hp.maximo, 0)
    eq(d.hp.actual, 12)
    eq(d.hp.temporal, 0)
    eq(d.ajustes.iniciativa, 3)
    eq(d.ajustes.competencia, rapidjson.null)
    eq(d.conjuros.aptitud, rapidjson.null)
    eq(#d.ataques, 1)
    eq(d.ataques[1].nombre, "Espada")
    eq(d.ataques[1].bonus, "")
    local n1 = d.conjuros.niveles["1"]
    eq(n1.usados, 3, "usados acotado al total")
    eq(n1.lista[1].preparado, false)
    eq(#Schema.validate(d), 0)
end

function T.conserva_claves_desconocidas()
    local d = Schema.normalize(fixture("tipos.dnd"))
    eq(d.homebrew.x[3], 3)
end

function T.ataques_ausente_es_array()
    local d = Schema.normalize({})
    eq(#d.ataques, 0)
    eq(rapidjson.encode({ a = d.ataques }), '{"a":[]}')
end

function T.nivel_cero_sin_ranuras()
    local d = Schema.normalize({ conjuros = { niveles = { ["0"] = { total = 4, usados = 1 } } } })
    eq(d.conjuros.niveles["0"].total, nil)
    eq(d.conjuros.niveles["0"].usados, nil)
    for n = 0, 9 do eq(type(d.conjuros.niveles[tostring(n)]), "table") end
end

function T.get_y_set_con_listas_y_objetos()
    local d = Schema.normalize(fixture("thalia.dnd"))
    eq(Schema.get(d, "ataques.2.nombre"), "Arco corto")
    Schema.set(d, "ataques.2.nombre", "Arco largo")
    eq(d.ataques[2].nombre, "Arco largo")
    eq(Schema.get(d, "conjuros.niveles.1.usados"), 1)
    Schema.set(d, "conjuros.niveles.3.usados", 2)
    eq(d.conjuros.niveles["3"].usados, 2)
    eq(Schema.get(d, "hp.actual"), 27)
    eq(Schema.get(d, "no.existe.nada"), nil)
end

function T.set_crea_tablas_intermedias()
    local d = {}
    Schema.set(d, "x.y.z", 1)
    eq(d.x.y.z, 1)
end

function T.set_en_lista_vacia_usa_indice_numerico()
    local d = Schema.normalize({})
    Schema.set(d, "ataques.1", { nombre = "Daga", bonus = "+1", dano = "1d4" })
    eq(d.ataques[1].nombre, "Daga")
end

function T.solo_lectura_y_migrate()
    local d = fixture("futuro.dnd")
    eq(Schema.is_readonly(d), true)
    Schema.migrate(d)
    eq(d.meta.schema, 99, "migrate no toca versiones futuras")
    eq(Schema.is_readonly(Schema.normalize({})), false)
    eq(d.campo_nuevo[2], 2)
end

function T.migrate_sin_meta()
    local d = Schema.migrate({})
    eq(type(d.meta), "table")
end

-- F-04: inspiración como contador (schema 2)
function T.migrate_inspiracion_schema2()
    local function mig(v)
        local d = { meta = { schema = 1 } }
        d.inspiracion = v
        return Schema.migrate(d)
    end
    eq(mig(true).inspiracion, 1)
    eq(mig(true).meta.schema, 3)
    eq(mig(false).inspiracion, 0)
    eq(mig(nil).inspiracion, 0)
    eq(mig("x").inspiracion, 0)
    eq(mig(3).inspiracion, 3)
    eq(mig(-4).inspiracion, 0)
    eq(mig(2.7).inspiracion, 2)
    eq(mig(3).meta.schema, 3)
    -- ya en schema 2: no se toca
    local d = Schema.migrate({ meta = { schema = 2 }, inspiracion = 5 })
    eq(d.inspiracion, 5)
end

function T.normalize_inspiracion()
    local function norm(v) return Schema.normalize({ inspiracion = v }).inspiracion end
    eq(norm("2"), 2)
    eq(norm(-1), 0)
    eq(norm(150), 99)
    eq(norm(true), 1)
    eq(norm(false), 0)
    eq(norm(nil), 0)
    eq(norm(2.9), 2)
    eq(Schema.defaults().inspiracion, 0)
    eq(Schema.CURRENT, 3)
end

-- F-08: rasgos_ref y ref opcional (schema 3)
function T.migrate_2_a_3_agrega_rasgos_ref_sin_tocar_nada()
    local d = Schema.migrate({ meta = { schema = 2 }, inspiracion = 2, ataques = { { nombre = "Daga" } },
        rasgos = "texto libre" })
    eq(d.meta.schema, 3)
    eq(#d.rasgos_ref, 0)
    eq(d.inspiracion, 2)
    eq(d.rasgos, "texto libre")
    eq(d.ataques[1].nombre, "Daga")
    -- desde schema 1 pasa por las dos migraciones
    local e = Schema.migrate({ meta = { schema = 1 }, inspiracion = true })
    eq(e.meta.schema, 3)
    eq(e.inspiracion, 1)
    eq(#e.rasgos_ref, 0)
    -- ya en schema 3: no se toca
    local f = Schema.migrate({ meta = { schema = 3 }, rasgos_ref = { { ref = "monk.slow-fall", nombre = "Slow Fall", nota = "" } } })
    eq(#f.rasgos_ref, 1)
end

function T.normalize_rasgos_ref_descarta_invalidos_sin_romper()
    local d = Schema.normalize({ rasgos_ref = {
        { ref = "monk.slow-fall", nombre = "Slow Fall", nota = "nivel 4" },
        "no es tabla",
        { nombre = "sin ref" },
        { ref = 12, nombre = "ref numérica" },
        { ref = "", nombre = "ref vacía" },
        { ref = "feat.alert" },
    } })
    eq(#d.rasgos_ref, 2)
    eq(d.rasgos_ref[1].ref, "monk.slow-fall")
    eq(d.rasgos_ref[1].nota, "nivel 4")
    eq(d.rasgos_ref[2].ref, "feat.alert")
    eq(d.rasgos_ref[2].nombre, "")
    eq(d.rasgos_ref[2].nota, "")
    -- no es lista → lista vacía
    eq(#Schema.normalize({ rasgos_ref = "x" }).rasgos_ref, 0)
    eq(#Schema.normalize({ rasgos_ref = true }).rasgos_ref, 0)
    eq(#Schema.normalize({}).rasgos_ref, 0)
end

function T.normalize_ref_opcional_en_conjuros_y_ataques()
    local d = Schema.normalize({
        ataques = { { nombre = "Bastón", ref = "weapon.quarterstaff" }, { nombre = "X", ref = 5 }, { nombre = "Y" } },
        conjuros = { niveles = { ["0"] = { lista = { { nombre = "Fire Bolt", ref = "spell.fire-bolt" }, { nombre = "Luz", ref = {} } } } } },
    })
    eq(d.ataques[1].ref, "weapon.quarterstaff")
    eq(d.ataques[2].ref, nil)
    eq(d.ataques[3].ref, nil)
    eq(d.conjuros.niveles["0"].lista[1].ref, "spell.fire-bolt")
    eq(d.conjuros.niveles["0"].lista[2].ref, nil)
    eq(#d.ataques, 3)
end

function T.rasgos_ref_vacio_se_guarda_como_array()
    local d = Schema.normalize({})
    Schema.fix_arrays(d)
    local s = rapidjson.encode(d.rasgos_ref)
    eq(s, "[]")
end

return T
