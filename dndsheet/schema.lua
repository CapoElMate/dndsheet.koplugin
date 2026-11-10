-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Esquema del .dnd v1: valores por defecto, normalización, migración y rutas.
Módulo PURO (solo usa rapidjson para `null` y `array`).

@module dndsheet.schema
--]]
local rapidjson = require("rapidjson")

local Schema = {}

Schema.CURRENT = 3

local NULL = rapidjson.null
local function array() return rapidjson.array({}) end

local ABILITIES = { "fue", "des", "con", "int", "sab", "car" }
local SKILLS = {
    "acrobacias", "trato_animales", "arcanos", "atletismo", "engano", "historia",
    "perspicacia", "intimidacion", "investigacion", "medicina", "naturaleza", "percepcion",
    "interpretacion", "persuasion", "religion", "juego_manos", "sigilo", "supervivencia",
}
local SPELL_ABILITIES = { int = true, sab = true, car = true }

--- Personaje nuevo con todos los valores por defecto (tabla recién creada).
function Schema.defaults()
    local atributos, salvaciones, habilidades, niveles = {}, {}, {}, {}
    for _i, k in ipairs(ABILITIES) do
        atributos[k] = 10
        salvaciones[k] = false
    end
    for _i, k in ipairs(SKILLS) do habilidades[k] = 0 end
    niveles["0"] = { lista = array() }
    for n = 1, 9 do
        niveles[tostring(n)] = { total = 0, usados = 0, lista = array() }
    end
    return {
        meta = { schema = Schema.CURRENT, app = "dndsheet", creado = 0, guardado = 0 },
        nombre = "", clase_nivel = "", nivel = 1, trasfondo = "", jugador = "", raza = "",
        alineamiento = "", experiencia = 0,
        atributos = atributos, salvaciones = salvaciones, habilidades = habilidades,
        inspiracion = 0,
        ca = 10, velocidad = "",
        hp = { maximo = 10, actual = 10, temporal = 0 },
        dados_golpe = { total = "1d8", restantes = 1 },
        muerte = { exitos = 0, fallos = 0 },
        ajustes = {
            competencia = NULL, iniciativa = NULL, percepcion_pasiva = NULL,
            cd_conjuros = NULL, ataque_conjuros = NULL,
        },
        ataques = array(), ataques_notas = "",
        monedas = { pc = 0, pp = 0, pe = 0, po = 0, ppt = 0 },
        equipo = "", otras_competencias = "",
        rasgos = "", rasgos_ref = array(),
        personalidad = { rasgos = "", ideales = "", vinculos = "", defectos = "" },
        fisico = { edad = "", altura = "", peso = "", ojos = "", piel = "", pelo = "" },
        apariencia = "", aliados = "", organizacion = "", rasgos_adicionales = "",
        historia = "", tesoro = "",
        conjuros = { clase = "", aptitud = NULL, niveles = niveles },
        notas = "",
    }
end

-- ── Utilidades ──────────────────────────────────────────────────────────────

local function is_array_marked(t)
    local mt = getmetatable(t)
    return type(mt) == "table" and mt.__jsontype == "array"
end

--- ¿Es una lista? (tiene elementos 1..n o está marcada como array)
local function is_list(t)
    return #t > 0 or is_array_marked(t)
end

local function is_plain_table(v)
    return type(v) == "table"
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function to_int(v, default, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then n = default end
    n = math.floor(n)
    if lo then n = clamp(n, lo, hi or n) end
    return n
end

local function to_string(v, default)
    if type(v) == "string" then return v end
    if type(v) == "number" then return tostring(v) end
    return default
end

-- Completa y corrige `dst` según `def` (solo diccionarios; las listas van aparte).
local function fill(dst, def)
    for k, dv in pairs(def) do
        local v = dst[k]
        if v == NULL and dv ~= NULL then v = nil end
        if dv == NULL then
            -- ajuste manual o aptitud: número/texto válido o null (se revisa después)
            if v == nil then dst[k] = NULL end
        elseif type(dv) == "table" then
            if not is_plain_table(v) or v == NULL then
                dst[k] = Schema.defaults_copy_of(dv)
            elseif not is_list(dv) then
                fill(v, dv)
            end
        elseif type(dv) == "number" then
            dst[k] = to_int(v, dv)
        elseif type(dv) == "string" then
            dst[k] = to_string(v, dv)
        elseif type(dv) == "boolean" then
            dst[k] = (v == true)
        end
    end
end

-- Copia profunda (conserva rapidjson.null y marca los arrays).
function Schema.defaults_copy_of(t)
    local out = is_array_marked(t) and array() or {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and Schema.defaults_copy_of(v) or v
    end
    return out
end

local function normalize_list(t, key, item_def, fix_item)
    local list = t[key]
    if type(list) ~= "table" or list == NULL then
        t[key] = array()
        return
    end
    local clean = {}
    for _i, item in ipairs(list) do
        if type(item) == "table" and item ~= NULL then
            fill(item, item_def)
            if not fix_item or fix_item(item) ~= false then
                clean[#clean + 1] = item
            end
        end
    end
    if #clean == 0 then
        t[key] = array()
    else
        for i = #list, 1, -1 do list[i] = nil end
        for i, item in ipairs(clean) do list[i] = item end
    end
end

-- `ref` opcional (F-08): id de una entrada del compendio; si no es texto, se descarta
local function fix_ref(item)
    if item.ref ~= nil and (type(item.ref) ~= "string" or item.ref == "") then item.ref = nil end
end

-- rasgos_ref (F-08): { ref, nombre, nota }; sin `ref` de texto el elemento se descarta
local function normalize_refs(data)
    local list = data.rasgos_ref
    if type(list) ~= "table" or list == NULL then
        data.rasgos_ref = array()
        return
    end
    local clean = {}
    for _i, item in ipairs(list) do
        if type(item) == "table" and item ~= NULL and type(item.ref) == "string" and item.ref ~= "" then
            fill(item, { ref = "", nombre = "", nota = "" })
            clean[#clean + 1] = item
        end
    end
    for i = #list, 1, -1 do list[i] = nil end
    if #clean == 0 then
        data.rasgos_ref = array()
    else
        for i, item in ipairs(clean) do list[i] = item end
    end
end

--- Garantiza que las listas vacías se guarden como `[]` y no como `{}`.
function Schema.fix_arrays(data)
    local function fix(t, key)
        if type(t) == "table" and type(t[key]) == "table" and #t[key] == 0 and not is_array_marked(t[key]) then
            t[key] = array()
        end
    end
    fix(data, "ataques")
    fix(data, "rasgos_ref")
    local niveles = type(data.conjuros) == "table" and data.conjuros.niveles
    if type(niveles) == "table" then
        for _k, lv in pairs(niveles) do
            if type(lv) == "table" then fix(lv, "lista") end
        end
    end
end

-- ── Normalización ───────────────────────────────────────────────────────────

local RANGES = {
    { "nivel", 1, 20 }, { "experiencia", 0 }, { "inspiracion", 0, 99 }, { "ca", 0 },
    { "hp.maximo", 0 }, { "hp.actual", 0 }, { "hp.temporal", 0 },
    { "muerte.exitos", 0, 3 }, { "muerte.fallos", 0, 3 },
    { "dados_golpe.restantes", 0 },
    { "monedas.pc", 0 }, { "monedas.pp", 0 }, { "monedas.pe", 0 },
    { "monedas.po", 0 }, { "monedas.ppt", 0 },
}

--- Completa y corrige tipos y rangos. Nunca falla. Conserva las claves desconocidas.
-- @treturn table el mismo `data` (modificado) o uno nuevo si no era una tabla
function Schema.normalize(data)
    if type(data) ~= "table" or data == NULL then data = {} end
    local def = Schema.defaults()
    -- inspiracion: acepta booleanos por robustez (archivo editado a mano, o anterior al schema 2)
    if data.inspiracion == true then data.inspiracion = 1 elseif data.inspiracion == false then data.inspiracion = 0 end
    -- ajustes y aptitud admiten null: se separan antes de `fill` para no perder el valor
    fill(data, def)

    for _i, k in ipairs(ABILITIES) do
        data.atributos[k] = clamp(data.atributos[k], 1, 30)
    end
    for _i, k in ipairs(SKILLS) do
        local v = data.habilidades[k]
        data.habilidades[k] = (v == 1 or v == 2) and v or 0
    end
    for _i, r in ipairs(RANGES) do
        local parent, key = r[1]:match("^(.-)%.?([^.]+)$")
        local t = parent ~= "" and data[parent] or data
        t[key] = r[3] and clamp(t[key], r[2], r[3]) or math.max(r[2], t[key])
    end

    -- ajustes manuales: número o null
    for k, v in pairs(data.ajustes) do
        if v ~= NULL then
            local n = tonumber(v)
            data.ajustes[k] = n and math.floor(n) or NULL
        end
    end
    -- aptitud: "int" | "sab" | "car" | null
    if not SPELL_ABILITIES[data.conjuros.aptitud] then data.conjuros.aptitud = NULL end

    -- listas
    normalize_list(data, "ataques", { nombre = "", bonus = "", dano = "" }, fix_ref)
    normalize_refs(data)
    local niveles = data.conjuros.niveles
    for n = 0, 9 do
        local key = tostring(n)
        local lv = niveles[key]
        if type(lv) ~= "table" or lv == NULL then
            niveles[key] = def.conjuros.niveles[key]
        else
            if n == 0 then
                lv.total, lv.usados = nil, nil
            else
                lv.total = to_int(lv.total, 0, 0, 99)
                lv.usados = to_int(lv.usados, 0, 0, lv.total)
            end
            normalize_list(lv, "lista", n == 0 and { nombre = "" } or { nombre = "", preparado = false }, fix_ref)
        end
    end
    return data
end

--- ¿El archivo es de una versión futura? (se abre en solo lectura y no se guarda)
function Schema.is_readonly(data)
    local v = type(data) == "table" and type(data.meta) == "table" and tonumber(data.meta.schema)
    return v ~= nil and v ~= false and v > Schema.CURRENT
end

-- ── Migraciones ─────────────────────────────────────────────────────────────

local MIGRATIONS = {
    -- schema 2 (F-04): `inspiracion` pasa de booleano a entero >= 0
    [2] = function(data)
        local v = data.inspiracion
        if v == true then
            data.inspiracion = 1
        elseif type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
            data.inspiracion = math.max(0, math.floor(v))
        else
            data.inspiracion = 0
        end
        data.meta.schema = 2
    end,
    -- schema 3 (F-08): lista `rasgos_ref` (reglas del compendio agregadas a la hoja); lo demás no cambia
    [3] = function(data)
        if type(data.rasgos_ref) ~= "table" or data.rasgos_ref == NULL then data.rasgos_ref = array() end
        data.meta.schema = 3
    end,
}

--- Lleva `data` a la versión actual. No toca archivos de versiones futuras.
function Schema.migrate(data)
    if type(data.meta) ~= "table" then data.meta = {} end
    local v = tonumber(data.meta.schema) or 1
    if v > Schema.CURRENT then return data end
    for target = v + 1, Schema.CURRENT do
        MIGRATIONS[target](data)
    end
    return data
end

-- ── Validación (depuración) ─────────────────────────────────────────────────

--- Lista de advertencias legibles; no modifica nada.
function Schema.validate(data)
    local w = {}
    local function check(path, cond)
        if not cond then w[#w + 1] = path end
    end
    if type(data) ~= "table" then return { "raíz: no es un objeto" } end
    for _i, k in ipairs(ABILITIES) do
        local v = data.atributos and data.atributos[k]
        check("atributos." .. k, type(v) == "number" and v >= 1 and v <= 30)
    end
    check("nivel", type(data.nivel) == "number" and data.nivel >= 1 and data.nivel <= 20)
    check("hp", type(data.hp) == "table" and type(data.hp.actual) == "number" and type(data.hp.maximo) == "number")
    check("ataques", type(data.ataques) == "table")
    check("conjuros.niveles", type(data.conjuros) == "table" and type(data.conjuros.niveles) == "table")
    return w
end

-- ── Rutas ───────────────────────────────────────────────────────────────────

local function segments(path)
    local out = {}
    for s in tostring(path):gmatch("[^.]+") do out[#out + 1] = s end
    return out
end

local function key_for(parent, seg)
    if is_list(parent) and tonumber(seg) then return tonumber(seg) end
    return seg
end

--- Lee el valor en una ruta ("hp.actual", "ataques.2.nombre"); nil si no existe.
function Schema.get(data, path)
    local cur = data
    for _i, seg in ipairs(segments(path)) do
        if type(cur) ~= "table" then return nil end
        cur = cur[key_for(cur, seg)]
    end
    return cur
end

--- Escribe un valor en una ruta, creando las tablas intermedias que falten.
function Schema.set(data, path, value)
    local segs = segments(path)
    local cur = data
    for i = 1, #segs - 1 do
        local k = key_for(cur, segs[i])
        if type(cur[k]) ~= "table" then cur[k] = {} end
        cur = cur[k]
    end
    cur[key_for(cur, segs[#segs])] = value
end

return Schema
