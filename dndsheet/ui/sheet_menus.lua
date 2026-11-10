-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Menús y acciones de la hoja (índice de páginas, menú ≡, ver archivo, duplicar, descansos).
Se instalan como métodos de `Sheet` para mantener cada archivo por debajo de ~400 líneas.

@module dndsheet.ui.sheet_menus
--]]
local ButtonDialog = require("ui/widget/buttondialog")
local Characters = require("dndsheet/characters")
local Editors = require("dndsheet/ui/editors")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local T = require("dndsheet/i18n").T

return function(Sheet)
    local PAGES = Sheet.PAGES

    --- Acciones de la hoja (botones de las páginas): long_rest, short_rest.
    function Sheet:act(name)
        if self.readonly then
            return self:warnReadonly()
        end
        if name == "long_rest" then
            return Editors.long_rest(self)
        elseif name == "short_rest" then
            return Editors.short_rest(self)
        end
        error("dndsheet: acción desconocida: " .. tostring(name))
    end

    --- Abre el compendio (F-08). `opts.start`: "spells" (con `opts.level`) o "weapons" saltan a esa lista.
    function Sheet:openCompendium(opts)
        return require("dndsheet/ui/compendium_ui").open(self, opts)
    end

    --- Muestra la regla agregada a la hoja con id `ref` (F-08).
    function Sheet:viewRule(ref, name)
        return require("dndsheet/ui/compendium_ui").view_ref(self, ref, name)
    end

    -- ── Menús ───────────────────────────────────────────────────────────────────

    function Sheet:showIndex()
        local dialog
        local buttons = {}
        for i, p in ipairs(PAGES) do
            buttons[i] = {{
                text = string.format("%s%d · %s", i == self.page and "● " or "", i, T(p.title_key)),
                callback = function()
                    UIManager:close(dialog)
                    self:goTo(i, 1)
                end,
            }}
        end
        dialog = ButtonDialog:new{ title = T("menu.goto_title"), buttons = buttons }
        UIManager:show(dialog)
        return dialog
    end

    function Sheet:showFileInfo()
        local saved = tonumber(self.data.meta and self.data.meta.guardado)
        local when = (saved and saved > 0) and os.date("%Y-%m-%d %H:%M", saved) or "—"
        UIManager:show(InfoMessage:new{
            text = string.format("%s\n\n%s: %s", self.path, T("file.last_saved"), when),
        })
    end

    --- Duplica el personaje (guarda antes lo pendiente) como "<archivo> (copia).dnd".
    function Sheet:duplicate()
        if not self:flushSave() then return end
        local path, err = Characters.duplicate(self.path)
        if not path then
            UIManager:show(InfoMessage:new{ text = err })
            return
        end
        UIManager:show(InfoMessage:new{
            text = string.format("%s\n%s", T("msg.duplicated"), path:match("([^/]+)$") or path),
        })
    end

    function Sheet:showMenu()
        local dialog
        local function item(id, text, fn)
            return {{ id = id, text = text, callback = function() UIManager:close(dialog) fn() end }}
        end
        dialog = ButtonDialog:new{
            buttons = {
                item("goto", T("menu.goto"), function() self:showIndex() end),
                item("compendium", T("menu.compendium"), function() self:openCompendium() end),
                item("long_rest", T("rest.long"), function() self:act("long_rest") end),
                item("short_rest", T("rest.short"), function() self:act("short_rest") end),
                item("duplicate", T("menu.duplicate"), function() self:duplicate() end),
                item("refresh", T("menu.refresh"), function() UIManager:setDirty(nil, "full") end),
                item("file", T("menu.view_file"), function() self:showFileInfo() end),
                item("close", T("common.close"), function() self:onClose() end),
            },
        }
        UIManager:show(dialog)
        return dialog
    end
end
