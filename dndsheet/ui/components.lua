-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Piezas reutilizables de las páginas. Funciones puras de construcción:
reciben `(L, opts)`, donde L es el layout. Los textos se recortan con "…" (max_width),
nunca se cortan a ciegas. Todo lo tocable usa `show_parent = opts.show_parent`.

@module dndsheet.ui.components
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Utf8Proc = require("ffi/utf8proc")
local T = require("dndsheet/i18n").T

local C = {}

--- MAYÚSCULAS con soporte de tildes y ñ (string:upper() de Lua solo cambia ASCII).
local function upper(str)
    return Utf8Proc.uppercase_dumb(str)
end
C.upper = upper

-- FrameContainer de tamaño FIJO: el original ignora width/height en getSize() (solo los usa al
-- pintar), así que los grupos que lo contienen lo medirían por su contenido (framecontainer.lua:54-66).
local Frame = FrameContainer:extend{}
function Frame:getSize()
    local size = FrameContainer.getSize(self)
    return Geom:new{ w = self.width or size.w, h = self.height or size.h }
end
C.Frame = Frame

-- Marcas de competencia: ○ sin, ● competente, ◎ pericia
C.MARK = { [0] = "○", [1] = "●", [2] = "◎" }

local GRAY = Blitbuffer.COLOR_DARK_GRAY

local function text(L, str, face, max_w, opts)
    opts = opts or {}
    return TextWidget:new{
        text = str,
        face = face,
        bold = opts.bold,
        fgcolor = opts.fgcolor,
        max_width = max_w,
    }
end

--- Envuelve un widget para que responda a toque (y mantener presionado).
-- @tparam table opts child, on_tap, on_hold, show_parent
function C.tappable(opts)
    local size = opts.child:getSize()
    local w = InputContainer:new{
        dimen = Geom:new{ w = opts.w or size.w, h = opts.h or size.h },
        show_parent = opts.show_parent,
        opts.child,
    }
    w.ges_events = {}
    if opts.on_tap then
        w.ges_events.TapSelf = { GestureRange:new{ ges = "tap", range = function() return w.dimen end } }
        w.onTapSelf = function() opts.on_tap() return true end
    end
    if opts.on_hold then
        w.ges_events.HoldSelf = { GestureRange:new{ ges = "hold", range = function() return w.dimen end } }
        w.onHoldSelf = function() opts.on_hold() return true end
    end
    return w
end

--- Línea separadora horizontal.
function C.hline(L, w)
    return LineWidget:new{
        dimen = Geom:new{ w = w or L.body_w, h = L.border },
        background = Blitbuffer.COLOR_BLACK,
    }
end

function C.vspace(L, n)
    return VerticalSpan:new{ width = n or L.gap }
end

--- Título chico en MAYÚSCULAS (etiqueta de sección).
function C.label(L, str, w)
    return text(L, upper(str), L.font_label, w)
end

--- Título de sección + recuadro de borde fino con `child` dentro.
function C.section(L, title, child, w)
    w = w or L.col_w
    local inner_w = w - 2 * (L.border + L.pad)
    local framed = Frame:new{
        width = w,
        bordersize = L.border,
        radius = L.radius,
        padding = L.pad,
        margin = 0,
        child,
    }
    return VerticalGroup:new{
        align = "left",
        C.label(L, title, inner_w),
        VerticalSpan:new{ width = L.border + 1 },
        framed,
    }, inner_w
end

--- Recuadro con valor grande y etiqueta (CA, iniciativa, atributos…).
-- @tparam table opts label, value, sub (opcional, texto chico), on_tap, w, h, show_parent, thick
function C.statbox(L, opts)
    local w = opts.w or math.floor((L.body_w - 3 * L.gap) / 4)
    local inner_w = w - 2 * (L.border_thick + L.pad)
    local vg = VerticalGroup:new{ align = "center" }
    table.insert(vg, text(L, tostring(opts.value), L.font_big, inner_w, { bold = true }))
    if opts.sub then
        table.insert(vg, text(L, tostring(opts.sub), L.font_small, inner_w))
    end
    table.insert(vg, text(L, upper(opts.label), L.font_label, inner_w))
    local vg_h = vg:getSize().h
    local h = opts.h and (opts.h - 2 * (L.border_thick + L.pad)) or vg_h
    local box = Frame:new{
        width = w,
        height = opts.h,
        bordersize = opts.thick and L.border_thick or L.border,
        radius = L.radius,
        padding = L.pad,
        margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = h }, vg },
    }
    if opts.on_tap then
        return C.tappable{ child = box, on_tap = opts.on_tap, on_hold = opts.on_hold, show_parent = opts.show_parent }
    end
    return box
end

--- Etiqueta chica arriba + valor (campos de texto corto).
function C.field(L, opts)
    local w = opts.w or L.col_w
    local value = opts.value
    local vtext
    if value == nil or value == "" then
        vtext = text(L, "—", L.font_text, w, { fgcolor = GRAY })
    else
        vtext = text(L, tostring(value), L.font_text, w)
    end
    local vg = VerticalGroup:new{ align = "left", text(L, upper(opts.label), L.font_label, w), vtext }
    local box = Frame:new{ bordersize = 0, padding = 0, margin = 0, width = w, vg }
    -- el área táctil mide al menos min_touch de alto
    local h = math.max(vg:getSize().h, L.min_touch)
    return C.tappable{ child = box, w = w, h = h, on_tap = opts.on_tap, on_hold = opts.on_hold,
        show_parent = opts.show_parent }
end

--- Fila tocable: marca + texto a la izquierda y valor a la derecha.
-- @tparam table opts left, right, mark (○ ● ◎ ◉), on_tap, on_hold, w, show_parent
function C.row(L, opts)
    local w = opts.w or L.col_w
    local gap = L.gap
    local mark_w = 0
    local hg = HorizontalGroup:new{ align = "center" }
    if opts.mark then
        local m = text(L, opts.mark, L.font_value)
        mark_w = m:getSize().w + gap
        table.insert(hg, m)
        table.insert(hg, HorizontalSpan:new{ width = gap })
    end
    local right = opts.right and text(L, tostring(opts.right), L.font_value, nil, { bold = true })
    local right_w = right and right:getSize().w or 0
    local left_w = math.max(0, w - mark_w - right_w - (right and gap or 0))
    local left = text(L, tostring(opts.left or ""), L.font_text, left_w)
    table.insert(hg, left)
    if right then
        -- relleno para que el valor quede pegado al borde derecho
        table.insert(hg, HorizontalSpan:new{ width = math.max(gap, w - mark_w - left:getSize().w - right_w) })
        table.insert(hg, right)
    end
    local row_h = opts.h or L.row_h
    local row = LeftContainer:new{ dimen = Geom:new{ w = w, h = row_h }, hg }
    return C.tappable{ child = row, w = w, h = row_h, on_tap = opts.on_tap, on_hold = opts.on_hold,
        show_parent = opts.show_parent }
end

--- Pips tocables ●●○○. `used` marcados (●) de `total`.
-- on_tap_index(i) se llama con el índice tocado.
function C.pips(L, opts)
    local hg = HorizontalGroup:new{ align = "center" }
    for i = 1, opts.total do
        local glyph = text(L, i <= opts.used and "●" or "○", L.font_value)
        local cell = CenterContainer:new{
            dimen = Geom:new{ w = math.max(L.min_touch, glyph:getSize().w), h = L.min_touch },
            glyph,
        }
        table.insert(hg, C.tappable{
            child = cell,
            on_tap = opts.on_tap_index and function() opts.on_tap_index(i) end,
            on_hold = opts.on_hold,
            show_parent = opts.show_parent,
        })
    end
    return hg
end

--- Contador `−  27 / 38  +`.
-- @tparam table opts value (texto), on_minus, on_plus, on_tap, on_hold, w, show_parent
function C.counter(L, opts)
    local w = opts.w or L.body_w
    local btn_w = math.max(math.floor(L.min_touch * 1.5), math.floor(w * 0.2))
    local function btn(label, cb)
        return Button:new{
            text = label,
            width = btn_w,
            text_font_face = "tfont",
            text_font_size = L.btn_font_size,
            callback = cb,
            show_parent = opts.show_parent,
        }
    end
    local value_w = w - 2 * btn_w - 2 * L.gap
    local value = text(L, tostring(opts.value), L.font_big, value_w, { bold = true })
    local center = CenterContainer:new{ dimen = Geom:new{ w = value_w, h = math.max(L.min_touch, value:getSize().h) }, value }
    return HorizontalGroup:new{
        align = "center",
        btn("−", opts.on_minus),
        HorizontalSpan:new{ width = L.gap },
        C.tappable{ child = center, on_tap = opts.on_tap, on_hold = opts.on_hold, show_parent = opts.show_parent },
        HorizontalSpan:new{ width = L.gap },
        btn("+", opts.on_plus),
    }
end

--- Alto en px de una línea de TextBoxWidget con la fuente de texto del layout.
function C.line_px(L)
    return math.floor((1 + TextBoxWidget.line_height) * L.font_text.size + 0.5)
end

--- Fila de celdas de texto (tabla): cells = { {text=, w=, bold=}, … }.
-- @tparam table opts cells, h (alto, por defecto L.row_h), on_tap, on_hold, show_parent
function C.cells(L, opts)
    local h = opts.h or L.row_h
    local hg = HorizontalGroup:new{ align = "center" }
    local total_w = 0
    for _i, c in ipairs(opts.cells) do
        local empty = c.text == nil or c.text == ""
        local t = text(L, empty and "—" or c.text, c.face or L.font_text, c.w - L.gap,
            { bold = c.bold, fgcolor = (empty and not c.bold) and GRAY or nil })
        table.insert(hg, LeftContainer:new{ dimen = Geom:new{ w = c.w, h = h }, t })
        total_w = total_w + c.w
    end
    return C.tappable{ child = hg, w = total_w, h = h, on_tap = opts.on_tap, on_hold = opts.on_hold,
        show_parent = opts.show_parent }
end

--- Reparte bloques (widgets) en subpáginas SIN cortar ninguno: llena cada subpágina hasta L.body_h.
-- @tparam table blocks lista de widgets en orden
-- @int sub número de subpágina pedida (1-based)
-- @treturn widget contenido de esa subpágina
-- @treturn int total de subpáginas
function C.paginate(L, blocks, sub)
    local pages, current, used = {}, VerticalGroup:new{ align = "left" }, 0
    for i, b in ipairs(blocks) do
        local h = b:getSize().h
        if used > 0 and used + L.gap + h > L.body_h then
            table.insert(pages, current)
            current, used = VerticalGroup:new{ align = "left" }, 0
        end
        if used > 0 then
            table.insert(current, VerticalSpan:new{ width = L.gap })
            used = used + L.gap
        end
        table.insert(current, b)
        used = used + h
        if i == #blocks then table.insert(pages, current) end
    end
    if #pages == 0 then pages[1] = current end
    return pages[math.min(sub or 1, #pages)], #pages
end

--- Bloque de texto multilínea recortado a `max_lines` con "…" (un toque lo edita).
function C.textblock(L, opts)
    local w = opts.w or L.col_w
    local inner_w = w - 2 * (L.border + L.pad)
    local face = L.font_text
    -- alto de línea de TextBoxWidget: (1 + line_height) * tamaño de la fuente
    local line_px = math.floor((1 + TextBoxWidget.line_height) * face.size + 0.5)
    local lines = math.max(1, opts.max_lines or 3)
    local empty = opts.text == nil or opts.text == ""
    local body = TextBoxWidget:new{
        text = empty and (opts.hint or T("hint.tap_to_write")) or opts.text,
        face = face,
        width = inner_w,
        height = lines * line_px,
        height_overflow_show_ellipsis = true,
        fgcolor = empty and GRAY or nil,
    }
    local box = Frame:new{
        width = w, bordersize = L.border, radius = L.radius, padding = L.pad, margin = 0, body,
    }
    local vg = VerticalGroup:new{ align = "left" }
    if opts.label then table.insert(vg, C.label(L, opts.label, w)) end
    table.insert(vg, C.tappable{ child = box, on_tap = opts.on_tap, on_hold = opts.on_hold,
        show_parent = opts.show_parent })
    return vg
end

--- Dos columnas si hay lugar (`L.two_columns`); si no, una debajo de la otra.
function C.columns(L, cols, gap)
    gap = gap or L.gap
    if L.two_columns then
        return HorizontalGroup:new{ align = "top", cols[1], HorizontalSpan:new{ width = gap }, cols[2] }
    end
    return VerticalGroup:new{ align = "left", cols[1], VerticalSpan:new{ width = gap }, cols[2] }
end

return C
