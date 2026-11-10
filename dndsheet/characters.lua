-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Gestión de personajes: carpeta, nuevo (desde la plantilla), duplicar y "último abierto".
Nunca sobrescribe un .dnd existente: los nombres se hacen únicos (comparación SIN distinguir
mayúsculas, como en FAT) agregando -2, -3… (o "(copia)", "(copia 2)": según el idioma, "(copy)", "(copy 2)").

@module dndsheet.characters
--]]
local Device = require("device")
local Schema = require("dndsheet/schema")
local Settings = require("dndsheet/settings")
local Store = require("dndsheet/store")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local T = require("dndsheet/i18n").T

local Characters = {}

local EXT = ".dnd"
-- Caracteres inválidos en FAT (\ / : * ? " < > |) y de control
local INVALID = '[\\/:%*%?"<>|%c]'

-- Plantilla: <plugin>/templates/nuevo.dnd, deducida de la ruta de este archivo
local function template_path()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local plugin_dir = src:match("^(.*)/dndsheet/characters%.lua$") or "."
    return plugin_dir .. "/templates/nuevo.dnd"
end

--- Nombre de archivo válido para FAT a partir de un nombre de personaje (sin extensión).
function Characters.sanitize(name)
    name = tostring(name or ""):gsub(INVALID, "_"):gsub("%s+", " ")
    name = name:match("^[%s%.]*(.-)[%s%.]*$") -- sin espacios ni puntos en los extremos (FAT)
    if name == "" then return T("character.default_name") end
    return name:sub(1, 80)
end

--- Carpeta de personajes: la configurada o <home>/dnd.
function Characters.folder()
    local configured = Settings.get_value("folder")
    if type(configured) == "string" and configured ~= "" then
        return (configured:gsub("/+$", ""))
    end
    local home = G_reader_settings:readSetting("home_dir") or Device.home_dir or "."
    return (home:gsub("/+$", "")) .. "/dnd"
end

function Characters.set_folder(path)
    Settings.set_value("folder", path)
end

--- Crea la carpeta si no existe.
function Characters.ensure_folder()
    local dir = Characters.folder()
    if lfs.attributes(dir, "mode") ~= "directory" then
        util.makePath(dir)
    end
    return dir
end

-- Nombres existentes en minúsculas (FAT no distingue mayúsculas)
local function existing_names(dir)
    local set = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for entry in lfs.dir(dir) do set[entry:lower()] = true end
    end
    return set
end

--- Ruta libre en `dir` para `base`..suffix(n)..".dnd", probando n = 1, 2, 3… hasta que no exista.
local function unique_path(dir, base, suffix)
    local taken = existing_names(dir)
    local n = 1
    local candidate = base .. suffix(n) .. EXT
    while taken[candidate:lower()] do
        n = n + 1
        candidate = base .. suffix(n) .. EXT
    end
    return dir .. "/" .. candidate
end

--- Crea un personaje nuevo desde la plantilla. Devuelve la ruta o nil + mensaje.
function Characters.create(name)
    local dir = Characters.ensure_folder()
    local data, err = Store.load(template_path())
    if not data then return nil, err end
    data = Schema.normalize(data)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    data.nombre = name ~= "" and name or T("character.default_name")
    data.meta.creado = os.time()
    local path = unique_path(dir, Characters.sanitize(data.nombre), function(n) return n == 1 and "" or "-" .. n end)
    if lfs.attributes(path, "mode") then
        return nil, T("msg.file_exists") -- no se sobrescribe nunca
    end
    local ok, serr = Store.save(path, data)
    if not ok then return nil, serr end
    Settings.set_last_page(path, 1)
    logger.dbg("dndsheet: personaje creado", path)
    return path
end

--- Copia un personaje como "<archivo> (copia).dnd". Devuelve la ruta nueva o nil + mensaje.
function Characters.duplicate(path)
    local data, err = Store.load(path)
    if not data then return nil, err end
    local dir, file = path:match("^(.*)/([^/]+)$")
    dir = dir or "."
    local base = (file or path):gsub("%.[^.]+$", "")
    local new_path = unique_path(dir, base, function(n) return " " .. (n == 1 and T("character.copy") or T("character.copy_n", n)) end)
    if lfs.attributes(new_path, "mode") then
        return nil, T("msg.file_exists")
    end
    if Schema.is_readonly(data) then
        -- versión futura del formato: copia byte a byte (no se puede reescribir sin perder campos)
        local raw = util.readFromFile(path, "rb")
        local ok, werr = util.writeToFile(raw, new_path, true)
        if not ok then return nil, tostring(werr) end
        return new_path
    end
    Schema.migrate(data)
    if type(data.nombre) == "string" and data.nombre ~= "" then
        data.nombre = data.nombre .. " " .. T("character.copy")
    end
    data.meta.creado = os.time()
    local ok, serr = Store.save(new_path, data)
    if not ok then return nil, serr end
    return new_path
end

--- Recuerda el último personaje abierto (sobrevive a reiniciar KOReader).
function Characters.remember(path)
    Settings.set_value("last_file", path)
end

--- Último personaje abierto si el archivo todavía existe; si no, nil.
function Characters.last()
    local path = Settings.get_value("last_file")
    if type(path) == "string" and lfs.attributes(path, "mode") == "file" then
        return path
    end
    return nil
end

return Characters
