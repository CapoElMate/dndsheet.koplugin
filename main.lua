-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
dndsheet: abre archivos .dnd (JSON) como hojas de personaje compatibles con la 5e.

@module koplugin.dndsheet
--]]
local Characters = require("dndsheet/characters")
local DocumentRegistry = require("document/documentregistry")
local Dispatcher = require("dispatcher")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local T = require("dndsheet/i18n").T
local VERSION = require("dndsheet/version")

local Sheet = require("dndsheet/ui/sheet")
local Perf = require("dndsheet/perf")
local Schema = require("dndsheet/schema")
local Store = require("dndsheet/store")

local EXT = "dnd"

-- 1) Mostrar los .dnd en el explorador.
-- El filtro del explorador usa hasProvider(), que ignora los proveedores auxiliares
-- (documentregistry.lua:63-85). main.lua se ejecuta una sola vez por sesión
-- (PluginLoader cachea los módulos); el guard evita encadenar el parche dos veces.
if not DocumentRegistry._dndsheet_patched then
    local orig_hasProvider = DocumentRegistry.hasProvider
    function DocumentRegistry:hasProvider(file, mimetype, include_aux)
        if type(file) == "string" and file:lower():match("%." .. EXT .. "$") then
            return true
        end
        return orig_hasProvider(self, file, mimetype, include_aux)
    end
    DocumentRegistry._dndsheet_patched = true
end

local DndSheet = WidgetContainer:extend{
    name = "dndsheet",   -- coincide con la carpeta sin ".koplugin"
    is_doc_only = false, -- también se instancia en el explorador (FileManager)
}

function DndSheet:init()
    -- FileManager:registerModule() renombra self.name a "filemanager" .. name
    -- DESPUÉS de init() (filemanager.lua:379-383). Guardar la clave ahora.
    self.provider_key = self.name

    -- 2) Proveedor auxiliar: aparece en "Abrir con…" y permite openFile().
    DocumentRegistry:addAuxProvider({
        provider_name = T("app.name"),
        provider = self.provider_key,
        order = 40, -- posición en "Abrir con…" (texteditor usa 30)
    })

    -- 3) Asociar la extensión al plugin (igual que setProvider(file, provider, true),
    -- documentregistry.lua:210-222). Sin esto getProvider() no encuentra proveedor.
    local assoc = G_reader_settings:readSetting("provider", {})
    if assoc[EXT] ~= self.provider_key then
        assoc[EXT] = self.provider_key
        G_reader_settings:saveSetting("provider", assoc)
    end

    -- Acción asignable a un gesto (Configuración → Gestos)
    Dispatcher:registerAction("dndsheet_open_last", {
        category = "none", event = "DndsheetOpenLast", general = true,
        title = T("action.open_last"),
    })

    self.ui.menu:registerToMainMenu(self)
end

function DndSheet:onDndsheetOpenLast()
    local last = Characters.last()
    if last then
        self:openFile(last)
    else
        UIManager:show(InfoMessage:new{ text = T("msg.no_last") })
    end
    return true
end

--- Pide el nombre, crea el personaje desde la plantilla y lo abre.
function DndSheet:newCharacter()
    local dlg
    dlg = InputDialog:new{
        title = T("character.new_title"),
        input = "",
        input_hint = T("character.name_hint"),
        buttons = {{
            { id = "cancel", text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
            { id = "create", text = T("common.create"), is_enter_default = true, callback = function()
                local name = dlg:getInputText()
                UIManager:close(dlg)
                local path, err = Characters.create(name)
                if not path then
                    UIManager:show(InfoMessage:new{ text = err })
                    return
                end
                self:openFile(path)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

function DndSheet:chooseFolder()
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        select_file = false,
        path = Characters.ensure_folder(),
        onConfirm = function(dir)
            Characters.set_folder(dir)
            UIManager:show(InfoMessage:new{ text = T("msg.folder") .. "\n" .. dir, timeout = 3 })
        end,
    })
end

function DndSheet:openFolder()
    local dir = Characters.ensure_folder()
    self.ui.file_chooser:changeToPath(dir)
end

--- Submenú "Idioma / Language": Automático + cada idioma disponible (lang/*.lua). Aplica al reiniciar.
function DndSheet:languageItems()
    local I18n = require("dndsheet/i18n")
    local Settings = require("dndsheet/settings")
    local function choose(code)
        if Settings.get_value("language", "auto") == code then return end
        Settings.set_value("language", code)
        UIManager:askForRestart(T("lang.restart"))
    end
    local items = {
        {
            text = T("lang.auto"),
            checked_func = function() return Settings.get_value("language", "auto") == "auto" end,
            callback = function() choose("auto") end,
        },
    }
    for _i, lang in ipairs(I18n.available()) do
        items[#items + 1] = {
            text = lang.name,
            checked_func = function() return Settings.get_value("language", "auto") == lang.code end,
            callback = function() choose(lang.code) end,
        }
    end
    return items
end

function DndSheet:addToMainMenu(menu_items)
    menu_items.dndsheet = {
        text = T("app.name"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = T("menu.new"),
                callback = function() self:newCharacter() end,
            },
            {
                text = T("menu.open_last"),
                enabled_func = function() return Characters.last() ~= nil end,
                callback = function() self:onDndsheetOpenLast() end,
            },
            {
                text = T("menu.open_folder"),
                enabled_func = function() return self.ui.file_chooser ~= nil end,
                callback = function() self:openFolder() end,
            },
            {
                text = T("menu.set_folder"),
                keep_menu_open = true,
                callback = function() self:chooseFolder() end,
            },
            {
                -- siempre bilingüe: se tiene que poder encontrar aunque el idioma elegido no se lea
                text = "Idioma / Language",
                sub_item_table_func = function() return self:languageItems() end,
            },
            {
                text = T("menu.about"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T("about.text") .. "\n\n" .. T("about.version", VERSION),
                    })
                end,
            },
        },
    }
end

-- Lo consulta el diálogo "Abrir con…" para decidir si ofrecer este plugin.
function DndSheet:isFileTypeSupported(file)
    return file:lower():match("%." .. EXT .. "$") ~= nil
end

-- Lo llama FileManager:openFile() (filemanager.lua:1614) cuando el proveedor
-- asociado es este plugin.
function DndSheet:openFile(file)
    local t_open = Perf.start()
    local data, err = Store.load(file)
    if not data then
        UIManager:show(InfoMessage:new{ text = err })
        return
    end
    -- Versión futura del formato: se abre en solo lectura (no se guarda nunca)
    local readonly = Schema.is_readonly(data)
    Schema.migrate(data)
    data = Schema.normalize(data)
    Characters.remember(file)
    logger.dbg("dndsheet: abriendo", file, readonly and "(solo lectura)" or "")
    UIManager:show(Sheet:new{ path = file, data = data, readonly = readonly })
    Perf.stop("open", t_open, file)
    if readonly then
        UIManager:show(InfoMessage:new{
            text = T("msg.future_format"),
        })
    end
end

return DndSheet
