-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Ajustes propios del plugin (koreader/settings/dndsheet.lua): última página por archivo.

@module dndsheet.settings
--]]
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Settings = {}

local settings -- se abre la primera vez que se usa

local function get()
    if not settings then
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/dndsheet.lua")
    end
    return settings
end

--- Última página vista de un personaje (nil si no hay dato).
function Settings.last_page(path)
    local pages = get():readSetting("pages", {})
    return tonumber(pages[path])
end

function Settings.set_last_page(path, page)
    local pages = get():readSetting("pages", {})
    pages[path] = page
end

--- Valor genérico (carpeta de personajes, último archivo…).
function Settings.get_value(key, default)
    return get():readSetting(key, default)
end

function Settings.set_value(key, value)
    get():saveSetting(key, value)
    get():flush()
end

--- Escribe a disco (se llama al cerrar, suspender o guardar; no en cada cambio de página).
function Settings.flush()
    if settings then settings:flush() end
end

--- Para las pruebas: vuelve a abrir el archivo desde disco.
function Settings.reset()
    settings = nil
end

return Settings
