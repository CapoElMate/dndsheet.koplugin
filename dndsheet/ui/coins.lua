-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Diálogo de monedas (F-05): valor grande + botones de paso (−50k … +50k) + Sumar… / Restar… / Escribir….

Es un widget PROPIO (InputContainer + FrameContainer + TitleBar + ButtonTable): no es SpinWidget, ButtonDialog,
ConfirmBox ni InputDialog, que SimpleUI puede reemplazar por su propio diálogo.
Cada cambio actualiza `sheet.data.monedas[key]` y programa el guardado (`markChanged`); al cerrar se
reconstruye la página y se fuerza `flushSave`.

@module dndsheet.ui.coins
--]]
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Editors = require("dndsheet/ui/editors")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Layout = require("dndsheet/layout")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Blitbuffer = require("ffi/blitbuffer")
local T = require("dndsheet/i18n").T
local Screen = Device.screen

local Coins = InputContainer:extend{
    name = "dndsheet_coins",
    -- OJO: NO es `modal`: UIManager:show apila los modales por encima de todo lo no modal, y los InputDialog
    -- de Sumar…/Restar…/Escribir… quedarían DETRÁS de este diálogo (uimanager.lua:178).
    sheet = nil,    -- la hoja (data, markChanged, flushSave…)
    key = nil,      -- "po", "pc"…
    title = "",
}

Coins.MIN = 0
Coins.MAX = 999999
-- (etiqueta, paso). La etiqueta "50k" evita botones anchos.
Coins.STEPS_DOWN = { { "−50k", -50000 }, { "−1000", -1000 }, { "−100", -100 }, { "−10", -10 }, { "−1", -1 } }
Coins.STEPS_UP = { { "+1", 1 }, { "+10", 10 }, { "+100", 100 }, { "+1000", 1000 }, { "+50k", 50000 } }

local function clamp(n)
    return math.max(Coins.MIN, math.min(Coins.MAX, n))
end

function Coins:init()
    local L = Layout.compute(Screen:getWidth(), Screen:getHeight(), 0)
    self.L = L
    self.value = clamp(self.sheet.data.monedas[self.key] or 0)
    self.changed = false

    if Device:isTouchDevice() then
        -- los toques fuera del cuadro se tragan (no cierran): evita perder el contexto por un toque accidental
        self.ges_events.TapOutside = { GestureRange:new{
            ges = "tap", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        } }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.94)
    local inner_w = self.width - 2 * Size.border.window

    self.title_bar = TitleBar:new{
        width = inner_w,
        title = self.title,
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    self.value_widget = TextWidget:new{ text = tostring(self.value), face = Font:getFace("tfont", 40), bold = true }
    -- alto fijo para el valor más ancho posible: el diálogo no cambia de tamaño al cambiar el número
    local probe = TextWidget:new{ text = tostring(Coins.MAX), face = self.value_widget.face, bold = true }
    local value_h = probe:getSize().h + 2 * L.gap
    probe:free()
    self.value_box = CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = value_h }, self.value_widget }

    local function step_row(defs)
        local row = {}
        for _, def in ipairs(defs) do
            row[#row + 1] = { text = def[1], callback = function() self:setValue(self.value + def[2]) end }
        end
        return row
    end
    self.button_table = ButtonTable:new{
        width = inner_w - 2 * L.gap,
        show_parent = self,
        buttons = {
            step_row(Coins.STEPS_DOWN),
            step_row(Coins.STEPS_UP),
            {
                { id = "add", text = T("coins.add"), callback = function() self:ask("add") end },
                { id = "sub", text = T("coins.sub"), callback = function() self:ask("sub") end },
                { id = "write", text = T("common.type"), callback = function() self:ask("write") end },
            },
            {
                { id = "done", text = T("common.done"), callback = function() self:onClose() end },
            },
        },
    }

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        VerticalGroup:new{
            align = "center",
            self.title_bar,
            VerticalSpan:new{ width = L.gap },
            self.value_box,
            VerticalSpan:new{ width = L.gap },
            self.button_table,
            VerticalSpan:new{ width = L.gap },
        },
    }
    self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.frame }
end

--- Fija el valor (acotado), lo muestra y lo escribe en el modelo. Refresca solo la región del número.
function Coins:setValue(n)
    n = clamp(n)
    if n == self.value then return end
    self.value = n
    self.changed = true
    self.sheet.data.monedas[self.key] = n
    self.sheet:markChanged()
    self.value_widget:setText(tostring(n))
    UIManager:setDirty(self, function()
        return "ui", self:valueRegion()
    end)
end

--- Región de pantalla del número. CenterContainer no actualiza el x/y de su `dimen` (queda en 0,0), así que
-- se calcula desde el marco, que sí se posiciona al pintar.
function Coins:valueRegion()
    local f = self.frame.dimen
    if not (f and f.x) then return nil end
    return Geom:new{
        x = f.x + Size.border.window,
        y = f.y + Size.border.window + self.title_bar:getSize().h + self.L.gap,
        w = self.value_box.dimen.w,
        h = self.value_box.dimen.h,
    }
end

--- Sumar… / Restar… / Escribir…: pide un número con teclado.
function Coins:ask(mode)
    local title = T(mode == "add" and "coins.add_title" or mode == "sub" and "coins.sub_title" or "coins.write_title")
    Editors.type_number({
        title = title, value = mode == "write" and self.value or nil, min = Coins.MIN, max = Coins.MAX,
    }, function(n)
        if mode == "add" then
            self:setValue(self.value + n)
        elseif mode == "sub" then
            self:setValue(self.value - n)
        else
            self:setValue(n)
        end
    end)
end

function Coins:onTapOutside()
    return true
end

--- ✕, Listo o Atrás: cierra, reconstruye la página 3 y guarda ya.
function Coins:onClose()
    UIManager:close(self)
    if self.changed then
        self.changed = false
        self.sheet:mutate(function() end) -- reconstruye la página y refresca (ya está marcado como modificado)
        self.sheet:flushSave()
    end
    return true
end

function Coins:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
end

function Coins:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "flashui", self.frame.dimen
    end)
end

--- Abre el diálogo para la moneda `opts.key` (editor "coins").
function Coins.open(sheet, opts)
    local dlg = Coins:new{ sheet = sheet, key = opts.key, title = opts.title }
    UIManager:show(dlg)
    return dlg
end

return Coins
