-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
F-01: al despertar el dispositivo, otros plugins (p. ej. la pantalla de inicio de SimpleUI) pueden abrir
una ventana de pantalla completa encima de la hoja. Un poco después de `Resume` la hoja comprueba qué
ventana quedó arriba y, si la tapa una de pantalla completa, se vuelve a poner encima (una sola vez).
No modifica ni envuelve nada de otros plugins.

@module dndsheet.ui.sheet_resume
--]]
local UIManager = require("ui/uimanager")
local logger = require("logger")

local RERAISE_DELAY = 0.5 -- segundos: deja que el otro plugin termine su scheduleIn(0)

-- Ventanas que nunca se tapan (protector y bloqueo de pantalla): se reintenta con OutOfScreenSaver
local SCREENSAVER = { ScreenSaver = true, ScreenSaverLock = true }

--- Ventana visible de más arriba, ignorando toasts e invisibles
-- (como UIManager:getTopmostVisibleWidget, frontend/ui/uimanager.lua:780, pero salteando también los toasts).
local function topmost_window()
    local stack = UIManager._window_stack
    for i = #stack, 1, -1 do
        local widget = stack[i].widget
        if not widget.invisible and not widget.toast then
            return widget
        end
    end
end

return function(Sheet)
    Sheet.RERAISE_DELAY = RERAISE_DELAY

    --- Programa una (sola) comprobación; reemplaza la anterior si la hubiera.
    function Sheet:scheduleReraise()
        if not self.reraise_cb then
            self.reraise_cb = function() self:checkReraise() end
        end
        UIManager:unschedule(self.reraise_cb)
        UIManager:scheduleIn(RERAISE_DELAY, self.reraise_cb)
    end

    --- Cancela la comprobación pendiente (cierre real de la hoja).
    function Sheet:cancelReraise()
        self.reraise_pending = false
        if self.reraise_cb then
            UIManager:unschedule(self.reraise_cb)
        end
    end

    function Sheet:onResume()
        self.reraise_pending = true
        self:scheduleReraise()
        -- no se consume el evento: otros widgets también lo necesitan
    end

    function Sheet:onOutOfScreenSaver()
        if self.reraise_pending then
            self:scheduleReraise()
        end
    end

    --- ¿Hay que subirse? Si sí, se cierra y se vuelve a mostrar la hoja con los mismos datos.
    function Sheet:checkReraise()
        if not self.reraise_pending then
            return
        end
        if not UIManager:isWidgetShown(self) then
            self.reraise_pending = false
            return
        end
        local top = topmost_window()
        if top == self then
            self.reraise_pending = false
            return
        end
        if top and SCREENSAVER[top.name] then
            logger.dbg("dndsheet: reraise pospuesto (protector de pantalla)", top.name)
            return -- sigue pendiente: reintenta con OutOfScreenSaver
        end
        self.reraise_pending = false -- una sola vez por despertar
        if not top or top.covers_fullscreen ~= true or top.modal then
            logger.dbg("dndsheet: reraise no hace falta", top and (top.name or top.id))
            return
        end
        logger.dbg("dndsheet: reraise sobre", top.name or top.id or tostring(top))
        self.reraising = true -- onCloseWidget no libera data ni caché
        UIManager:close(self)
        UIManager:show(self)
        self.reraising = false
        UIManager:setDirty(self, "flashui") -- limpia los restos de la otra pantalla
    end
end
