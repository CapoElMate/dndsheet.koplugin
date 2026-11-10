-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Idiomas del plugin (F-02): un archivo por idioma en `dndsheet/lang/<código>.lua`.
`T(clave, ...)` busca en el idioma activo, luego en inglés (respaldo) y, si no está, devuelve "[clave]".
El idioma se resuelve una sola vez (al primer uso) y se cachea: cambiarlo pide reiniciar KOReader.

`resolve` y `T` no dependen de la interfaz, así que se prueban con LuaJIT solo.

@module dndsheet.i18n
--]]
local I18n = {}

local DEFAULT = "en"

local state = {
    code = nil, -- idioma activo (resuelto)
    tables = {}, -- código -> tabla de textos
    warned = {}, -- claves ya avisadas
    available = nil, -- cache de available_codes()
}

local function dbg(...)
    local ok, logger = pcall(require, "logger")
    if ok then logger.dbg(...) end
end

--- Carpeta de los archivos de idioma (junto a este archivo).
local function lang_dir()
    local src = debug.getinfo(1, "S").source:sub(2)
    return (src:match("^(.*)/[^/]+$") or ".") .. "/lang"
end

--- Códigos disponibles (archivos lang/*.lua), ordenados. "en" siempre está.
function I18n.available_codes()
    if state.available then return state.available end
    local codes = {}
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok then
        local okd, iter, dir_obj = pcall(lfs.dir, lang_dir())
        if okd then
            for name in iter, dir_obj do
                local code = name:match("^([%w_]+)%.lua$")
                if code then codes[#codes + 1] = code end
            end
        end
    end
    if #codes == 0 then codes[1] = DEFAULT end
    table.sort(codes)
    state.available = codes
    return codes
end

--- Normaliza el idioma de KOReader: "C"/vacío → "en"; quita ".codificación" y "@modificador"; "-" → "_".
local function normalize_system(system)
    if type(system) ~= "string" or system == "" or system == "C" or system == "POSIX" then
        return DEFAULT
    end
    system = system:gsub("[%.@].*$", ""):gsub("%-", "_")
    return system
end

--- Resuelve qué idioma usar (pura).
-- @tparam string|nil pref preferencia guardada: "auto" o un código
-- @tparam string|nil system idioma de KOReader (`G_reader_settings:readSetting("language")`)
-- @tparam table|nil available lista de códigos disponibles (por defecto, los archivos de lang/)
function I18n.resolve(pref, system, available)
    available = available or I18n.available_codes()
    local set = {}
    for _i, c in ipairs(available) do set[c] = true end
    -- 1) preferencia explícita (si existe)
    if pref and pref ~= "auto" and set[pref] then return pref end
    local sys = normalize_system(system)
    -- 3) coincidencia exacta (es_MX → es_MX)
    if set[sys] then return sys end
    -- 4) por idioma base (es_MX → es)
    local base = sys:match("^([^_]+)") or sys
    if set[base] then return base end
    -- 5) otra variante del mismo idioma base, en orden alfabético (es → es_AR)
    local variants = {}
    for _i, c in ipairs(available) do
        if c ~= base and (c:match("^([^_]+)") == base) then variants[#variants + 1] = c end
    end
    table.sort(variants)
    if variants[1] then return variants[1] end
    return DEFAULT
end

--- Carga (y cachea) la tabla de un idioma. nil si no existe o falla.
local function load_table(code)
    if state.tables[code] ~= nil then return state.tables[code] or nil end
    local t
    if code:match("^[%w_]+$") then
        local ok, res = pcall(require, "dndsheet/lang/" .. code)
        if ok and type(res) == "table" then
            t = res
        else
            dbg("dndsheet: no se pudo cargar el idioma", code, res)
        end
    end
    state.tables[code] = t or false
    return t
end

--- Idioma activo (lo resuelve la primera vez a partir de los ajustes y del idioma de KOReader).
function I18n.current()
    if not state.code then
        local pref = "auto"
        local okS, Settings = pcall(require, "dndsheet/settings")
        if okS then
            local okV, v = pcall(Settings.get_value, "language", "auto")
            if okV and type(v) == "string" then pref = v end
        end
        local system = G_reader_settings and G_reader_settings:readSetting("language") or nil
        state.code = I18n.resolve(pref, system)
        dbg("dndsheet: idioma", state.code, "pref", pref, "sistema", system)
    end
    return state.code
end

--- Fuerza un idioma (pruebas y capturas). No se guarda en los ajustes.
function I18n.set_language(code)
    state.code = (code and load_table(code)) and code or DEFAULT
    state.warned = {}
end

--- Olvida el idioma resuelto (se vuelve a resolver en el próximo uso).
function I18n.reset()
    state.code = nil
    state.warned = {}
end

--- Lista de idiomas disponibles: { { code = "es", name = "Español" }, … }
function I18n.available()
    local out = {}
    for _i, code in ipairs(I18n.available_codes()) do
        local t = load_table(code)
        out[#out + 1] = { code = code, name = t and t._name or code }
    end
    return out
end

--- Traduce `key`; `%1`, `%2`… se reemplazan con los argumentos (como ffi/util.template).
function I18n.T(key, ...)
    local cur = load_table(I18n.current())
    local s = cur and cur[key]
    if s == nil then
        local fb = load_table(DEFAULT)
        s = fb and fb[key]
    end
    if s == nil then
        if not state.warned[key] then
            state.warned[key] = true
            dbg("dndsheet: falta la clave de idioma", key)
        end
        return "[" .. key .. "]"
    end
    if select("#", ...) == 0 then return s end
    return require("ffi/util").template(s, ...)
end

return I18n
