-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Compendio de reglas (F-08): carga PEREZOSA de los JSON de `compendium/srd521/<idioma>/`, entradas propias del
usuario, índice por `id` y búsqueda por nombre. Módulo sin interfaz: la lectura de archivos se puede inyectar
(`read_file`, `list_dir`) para probarlo con luajit solo.

Nada se lee hasta que se pide una lista (`entries`) o una regla (`resolve`). `Compendium.release()` libera todo
(la hoja lo llama al cerrarse).

@module dndsheet.compendium
--]]
local rapidjson = require("rapidjson")

local Compendium = {}
Compendium.__index = Compendium

Compendium.KINDS = { "classes", "subclasses", "species", "feats", "spells", "weapons" }

-- prefijo del `id` → archivo donde buscarlo primero (sin prefijo conocido: clases)
local PREFIX_KIND = {
    spell = "spells", weapon = "weapons", feat = "feats", species = "species", subclass = "subclasses",
}

local function warn(...)
    local ok, logger = pcall(require, "logger")
    if ok then logger.warn("dndsheet:", ...) end
end

local function str(v)
    return type(v) == "string" and v ~= "" and v or nil
end

-- ── Entorno por defecto ─────────────────────────────────────────────────────

local function plugin_dir()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    return src:match("^(.*)/dndsheet/compendium%.lua$") or "."
end

local function default_read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function default_list_dir(path)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then return {} end
    local okd, iter, dir_obj = pcall(lfs.dir, path)
    if not okd then return {} end
    local names = {}
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

-- ── Validación de entradas propias ──────────────────────────────────────────

local function valid_items(list, with_level)
    if list == nil then return true end
    if type(list) ~= "table" then return false, "lista inválida" end
    for _i, it in ipairs(list) do
        if type(it) ~= "table" or not str(it.id) or not str(it.name) or type(it.text) ~= "string" then
            return false, "rasgo sin id, name o text"
        end
        if with_level and type(it.level) ~= "number" then return false, "rasgo sin level" end
    end
    return true
end

--- ¿Es válida la entrada `e` del tipo `kind`? (se usa para las entradas propias)
-- @treturn boolean ok
-- @treturn string motivo si no lo es
function Compendium.validate(kind, e)
    if type(e) ~= "table" or not str(e.id) or not str(e.name) then return false, "falta id o name" end
    if kind == "classes" then
        return valid_items(e.features, true)
    elseif kind == "subclasses" then
        if not str(e.class_id) then return false, "falta class_id" end
        return valid_items(e.features, true)
    elseif kind == "species" then
        return valid_items(e.traits, false)
    elseif kind == "feats" then
        if type(e.text) ~= "string" then return false, "falta text" end
    elseif kind == "spells" then
        if type(e.level) ~= "number" or e.level < 0 or e.level > 9 then return false, "level fuera de 0-9" end
        if type(e.text) ~= "string" then return false, "falta text" end
    elseif kind == "weapons" then
        if not str(e.damage) or not str(e.category) or not str(e.kind) then return false, "faltan damage, category o kind" end
    else
        return false, "tipo desconocido"
    end
    return true
end

-- ── Búsqueda ────────────────────────────────────────────────────────────────

-- minúsculas sin tildes (UTF-8 latino); solo para comparar nombres
local FOLD = {
    ["á"] = "a", ["à"] = "a", ["ä"] = "a", ["â"] = "a", ["ã"] = "a", ["å"] = "a",
    ["é"] = "e", ["è"] = "e", ["ë"] = "e", ["ê"] = "e",
    ["í"] = "i", ["ì"] = "i", ["ï"] = "i", ["î"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ö"] = "o", ["ô"] = "o", ["õ"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["ü"] = "u", ["û"] = "u",
    ["ñ"] = "n", ["ç"] = "c",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n", ["Ü"] = "u",
}

--- Minúsculas y sin tildes ("Cuación Mágica" ~ "cuacion magica").
function Compendium.fold(s)
    s = tostring(s or "")
    s = s:gsub("\xC3[\x80-\xBF]", function(ch) return FOLD[ch] or ch end)
    s = s:gsub("\xE2\x80\x99", "'")
    return s:lower()
end

--- ¿El nombre contiene la consulta? (ignora mayúsculas y tildes; consulta vacía → siempre)
function Compendium.matches(name, query)
    local q = Compendium.fold(query):match("^%s*(.-)%s*$")
    if q == "" then return true end
    return Compendium.fold(name):find(q, 1, true) ~= nil
end

-- ── Instancia ───────────────────────────────────────────────────────────────

--- Crea un compendio.
-- @tparam table opts root (carpeta `compendium`), lang (código), custom_dir (entradas propias),
--   read_file(path)→texto|nil, list_dir(path)→{nombres}, decode(texto)→tabla
function Compendium.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Compendium)
    self.root = opts.root or (plugin_dir() .. "/compendium")
    self.custom_dir = opts.custom_dir
    self.read_file = opts.read_file or default_read_file
    self.list_dir = opts.list_dir or default_list_dir
    self.decode = opts.decode or rapidjson.decode
    -- idioma de los datos: el del plugin si existe esa carpeta; si no, inglés
    local lang = opts.lang or "en"
    self.lang = lang
    if lang ~= "en" and not self.read_file(self.root .. "/srd521/" .. lang .. "/meta.json") then
        self.lang = "en"
    end
    self.dir = self.root .. "/srd521/" .. self.lang
    self.lists = {}   -- kind → lista fusionada (SRD + propias)
    self.index = {}   -- id → { kind, entry, item }
    self.custom = nil -- se lee la primera vez que hace falta
    return self
end

local function read_json(self, path)
    local text = self.read_file(path)
    if not text then return nil, "no se pudo leer" end
    local ok, data, err = pcall(self.decode, text)
    if not ok then return nil, tostring(data) end
    if data == nil then return nil, tostring(err) end
    return data
end

--- Entradas propias: todos los *.json de `custom_dir`. Un archivo es un objeto con listas por tipo
-- (`{ "spells": [...], "feats": [...] }`) o una lista cuyo tipo sale del nombre (`spells.json`).
function Compendium:loadCustom()
    if self.custom then return self.custom end
    local custom = { by_kind = {}, files = 0, entries = 0, errors = 0 }
    self.custom = custom
    if not self.custom_dir then return custom end
    for _i, name in ipairs(self.list_dir(self.custom_dir)) do
        if name:match("%.json$") then
            custom.files = custom.files + 1
            local data, err = read_json(self, self.custom_dir .. "/" .. name)
            if type(data) ~= "table" then
                custom.errors = custom.errors + 1
                warn("compendio propio ilegible:", name, err)
            else
                local groups = {}
                local stem = name:match("^(.-)%.json$")
                if #data > 0 then
                    groups[stem] = data
                else
                    for _j, kind in ipairs(Compendium.KINDS) do
                        if type(data[kind]) == "table" then groups[kind] = data[kind] end
                    end
                end
                for kind, list in pairs(groups) do
                    for _j, e in ipairs(list) do
                        local ok, why = Compendium.validate(kind, e)
                        if ok then
                            e.source = "custom"
                            custom.by_kind[kind] = custom.by_kind[kind] or {}
                            table.insert(custom.by_kind[kind], e)
                            custom.entries = custom.entries + 1
                        else
                            custom.errors = custom.errors + 1
                            warn("entrada propia inválida en", name, ":", tostring(why))
                        end
                    end
                end
            end
        end
    end
    return custom
end

local function index_entry(self, kind, e)
    self.index[e.id] = { kind = kind, entry = e }
    for _i, it in ipairs(e.features or {}) do self.index[it.id] = { kind = kind, entry = e, item = it } end
    for _i, it in ipairs(e.traits or {}) do self.index[it.id] = { kind = kind, entry = e, item = it } end
end

--- Lista fusionada del tipo (SRD + propias; si una propia repite un `id`, gana la propia y queda `override`).
function Compendium:entries(kind)
    if self.lists[kind] then return self.lists[kind] end
    local list = read_json(self, self.dir .. "/" .. kind .. ".json")
    if type(list) ~= "table" then
        warn("no se pudo leer el compendio:", kind)
        list = {}
    end
    local pos = {}
    for i, e in ipairs(list) do pos[e.id] = i end
    for _i, e in ipairs(self:loadCustom().by_kind[kind] or {}) do
        if pos[e.id] then
            e.override = true
            list[pos[e.id]] = e
        else
            list[#list + 1] = e
        end
    end
    for _i, e in ipairs(list) do index_entry(self, kind, e) end
    self.lists[kind] = list
    return list
end

--- Busca un `id` (entrada o rasgo) y devuelve { kind, entry, item } o nil. Carga solo el archivo probable.
function Compendium:resolve(ref)
    if not str(ref) then return nil end
    local guess = PREFIX_KIND[ref:match("^(%a+)%.") or ""] or "classes"
    self:entries(guess)
    if self.index[ref] then return self.index[ref] end
    -- id propio con otro prefijo: se prueban los demás tipos
    for _i, kind in ipairs(Compendium.KINDS) do
        if kind ~= guess then
            self:entries(kind)
            if self.index[ref] then return self.index[ref] end
        end
    end
    return nil
end

--- ¿Existe `ref`? Sin leer nada: `true`/`false` si ya se cargó el tipo probable, `nil` si todavía no se sabe.
function Compendium:peek(ref)
    if not str(ref) then return false end
    if self.index[ref] then return true end
    local guess = PREFIX_KIND[ref:match("^(%a+)%.") or ""] or "classes"
    if self.lists[guess] and self.custom then
        local all = true
        for _i, kind in ipairs(Compendium.KINDS) do
            if not self.lists[kind] then all = false end
        end
        if all then return false end
    end
    return nil
end

function Compendium:isLoaded()
    return next(self.lists) ~= nil
end

--- Metadatos de `meta.json` + estado de las entradas propias (para "Acerca del compendio").
function Compendium:about()
    local meta = read_json(self, self.dir .. "/meta.json") or {}
    local custom = self:loadCustom()
    return {
        meta = meta, lang = self.lang, custom_dir = self.custom_dir,
        custom_files = custom.files, custom_entries = custom.entries, custom_errors = custom.errors,
    }
end

--- Entradas del tipo `kind` cuyo nombre contiene `query`.
function Compendium:search(kind, query)
    local out = {}
    for _i, e in ipairs(self:entries(kind)) do
        if Compendium.matches(e.name, query) then out[#out + 1] = e end
    end
    return out
end

-- ── Instancia compartida (se libera al cerrar la hoja) ──────────────────────

local shared

--- La instancia compartida; se crea con `opts` la primera vez.
function Compendium.get(opts)
    if not shared then shared = Compendium.new(opts) end
    return shared
end

--- Libera todos los datos cargados.
function Compendium.release()
    shared = nil
end

--- Como `peek`, pero sin crear nada: `nil` si todavía no hay compendio cargado (la hoja no debe leerlo sola).
function Compendium.peekShared(ref)
    if not shared then return nil end
    return shared:peek(ref)
end

--- ¿Hay una instancia con datos en memoria? (la hoja sin compendio no debe tener ninguna)
function Compendium.is_loaded()
    return shared ~= nil and shared:isLoaded()
end

return Compendium
