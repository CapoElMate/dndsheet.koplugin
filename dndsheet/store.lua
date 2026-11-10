-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Lectura y escritura del JSON del personaje (.dnd): `load`, `save` atómico y `backup` (.bak).

@module dndsheet.store
--]]
local logger = require("logger")
local rapidjson = require("rapidjson")
local util = require("util")
local Schema = require("dndsheet/schema")
local T = require("dndsheet/i18n").T

local Store = {}

local UTF8_BOM = "\239\187\191"

--- Lee y decodifica un .dnd.
-- Nunca lanza errores: ante cualquier problema devuelve nil y un mensaje
-- (ya en español y listo para un InfoMessage).
-- @string path ruta del archivo
-- @treturn table|nil datos del personaje
-- @treturn string|nil mensaje de error
function Store.load(path)
    local name = tostring(path):match("([^/\\]+)$") or tostring(path)

    local raw, rerr = util.readFromFile(path, "rb")
    if not raw then
        logger.warn("dndsheet: no se pudo leer", path, rerr)
        return nil, T("err.read", name)
    end
    -- Algunos editores de Windows agregan BOM UTF-8 y rapidjson no lo acepta
    if raw:sub(1, 3) == UTF8_BOM then
        raw = raw:sub(4)
    end

    local pok, data, derr = pcall(rapidjson.decode, raw)
    if not pok then
        derr, data = data, nil
    end
    if type(data) ~= "table" then
        logger.warn("dndsheet: JSON inválido", path, derr)
        return nil, T("err.invalid_json", name, tostring(derr or T("err.expected_object")))
    end
    if data[1] ~= nil then
        logger.warn("dndsheet: el JSON raíz es una lista", path)
        return nil, T("err.not_character", name)
    end
    return data
end

--- Codifica `data` a JSON legible. Nunca lanza errores.
local function encode(data)
    local ok, encoded = pcall(rapidjson.encode, data, { pretty = true })
    if not ok or type(encoded) ~= "string" then
        return nil, tostring(encoded)
    end
    return encoded
end

--- Guardado atómico: escribe `ruta.tmp` (con fsync) y lo renombra sobre el original.
-- Si algo falla, el original queda intacto y se devuelve nil + mensaje.
-- Los archivos de una versión futura (solo lectura) nunca se guardan.
-- @string path ruta del .dnd
-- @table data personaje (se le agrega meta.guardado)
-- @treturn true|nil
-- @treturn string|nil mensaje de error
function Store.save(path, data)
    if Schema.is_readonly(data) then
        return nil, T("err.readonly_future")
    end
    if type(data.meta) ~= "table" then data.meta = {} end
    Schema.fix_arrays(data)
    local previous = data.meta.guardado
    data.meta.guardado = os.time()
    local encoded, eerr = encode(data)
    if not encoded then
        data.meta.guardado = previous
        logger.warn("dndsheet: no se pudo serializar", eerr)
        return nil, T("err.serialize", eerr)
    end
    local tmp = path .. ".tmp"
    local wrote, werr = util.writeToFile(encoded, tmp, true)
    if not wrote then
        os.remove(tmp)
        data.meta.guardado = previous
        logger.warn("dndsheet: no se pudo escribir", tmp, werr)
        return nil, T("err.write", tostring(werr))
    end
    local renamed, rerr = os.rename(tmp, path)
    if not renamed then
        os.remove(tmp)
        data.meta.guardado = previous
        logger.warn("dndsheet: no se pudo renombrar", tmp, rerr)
        return nil, T("err.replace", tostring(rerr))
    end
    return true
end

--- Copia el original a `ruta.bak` (sobrescribe el .bak anterior).
-- Si el original no existe todavía, no hace nada y devuelve true.
function Store.backup(path)
    local raw = util.readFromFile(path, "rb")
    if not raw then return true end
    local ok, err = util.writeToFile(raw, path .. ".bak", true)
    if not ok then
        logger.warn("dndsheet: no se pudo crear el .bak", path, err)
        return nil, tostring(err)
    end
    return true
end

return Store
