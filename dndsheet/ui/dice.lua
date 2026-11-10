-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Bandeja de dados (F-06): franja fija al pie de la página 3 con los 7 dados de D&D como cuadraditos.
Al tocar uno, el número "gira" unos instantes (solo ese cuadrado, refresco rápido) y queda el resultado.
Los resultados viven solo en memoria: no se guardan en el .dnd ni marcan el personaje como modificado.

Excepción explícita del usuario al principio "sin animaciones": corta (< 1 s), local, solo al tocar.
Todo se ajusta con las constantes de abajo; `ANIMATE = false` es el respaldo si en el Kindle se ve mal.

@module dndsheet.ui.dice
--]]
local Blitbuffer = require("ffi/blitbuffer")
local C = require("dndsheet/ui/components")
local CenterContainer = require("ui/widget/container/centercontainer")
local Dice = require("dndsheet/dice")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Layout = require("dndsheet/layout")
local T = require("dndsheet/i18n").T

local UIDice = {}

-- ── Ajustes ──────────────────────────────────
UIDice.ANIMATE = true
UIDice.ANIM_DELAYS = { 0.06, 0.07, 0.09, 0.12, 0.16, 0.22 } -- segundos entre cuadros: desacelera
UIDice.ANIM_REFRESH = "fast" -- "fast" o "ui"; el cuadro final siempre usa "ui"
UIDice.FINAL_REFRESH = "ui"
UIDice.SIDE_DP = 64 -- lado máximo de un cuadradito
UIDice.rng = math.random -- inyectable en las pruebas

-- La semilla se fija UNA vez al cargar el módulo y se descartan los primeros valores
math.randomseed(os.time())
for _ = 1, 5 do math.random() end

-- Estado en memoria (sobrevive a las reconstrucciones de la página 3)
local results = {} -- results[caras] = { value = n, natural = bool }
local history = {} -- { {faces=, value=}, … } el más reciente primero
local current -- franja viva: { sheet=, L=, widget=, cells = {[caras] = cell}, history_frame=, history_text= }
local rolling = {} -- rolling[caras] = cell con una animación en curso

--- Estado interno (para pruebas).
function UIDice.state() return { results = results, history = history, rolling = rolling, strip = current } end

function UIDice.reset()
    UIDice.cancel_all()
    results, history = {}, {}
    current = nil
end

-- ── Dibujo de un cuadradito ─────────────────────────────────────────────────

local function history_string()
    if #history == 0 then return nil end
    local parts = {}
    for _, e in ipairs(history) do parts[#parts + 1] = string.format("d%d → %d", e.faces, e.value) end
    return table.concat(parts, " · ")
end

-- Contenido del cuadrado: sin tirar → "d20" grande; con resultado → número grande y "d20" chico debajo
local function cell_content(L, cell, value, inverted)
    local inner = cell.side - 2 * L.border_thick
    local fg = inverted and Blitbuffer.COLOR_WHITE or nil
    local label = "d" .. cell.faces
    local vg = VerticalGroup:new{ align = "center" }
    if value then
        table.insert(vg, TextWidget:new{ text = tostring(value), face = cell.face_big, bold = true, fgcolor = fg,
            max_width = inner })
        table.insert(vg, TextWidget:new{ text = label, face = L.font_small, fgcolor = fg, max_width = inner })
    else
        table.insert(vg, TextWidget:new{ text = label, face = L.font_value, bold = true, max_width = inner })
    end
    return CenterContainer:new{ dimen = Geom:new{ w = inner, h = inner }, vg }
end

-- Redibuja el cuadrado con (value, inverted). No refresca la pantalla.
local function render(cell, value, inverted)
    local frame = cell.frame
    if frame[1] and frame[1].free then frame[1]:free() end
    frame[1] = cell_content(cell.L, cell, value, inverted)
    frame.background = inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

local function render_final(cell)
    local r = results[cell.faces]
    render(cell, r and r.value, r and r.natural)
end

local function refresh(strip, widget, mode)
    local d = widget.dimen
    UIManager:setDirty(strip.sheet, mode, d and d.x and Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h } or nil)
end

local function update_history(strip, redraw)
    local s = history_string()
    strip.history_text:setText(s and T("dice.history", s) or T("dice.hint"))
    strip.history_text.fgcolor = s and nil or Blitbuffer.COLOR_DARK_GRAY
    if redraw then refresh(strip, strip.history_frame, UIDice.FINAL_REFRESH) end
end

-- ── Animación ───────────────────────────────────────────────────────────────

local function finish(cell, final, redraw)
    rolling[cell.faces] = nil
    cell.timer = nil
    results[cell.faces] = { value = final, natural = Dice.is_natural(cell.faces, final) }
    Dice.push_history(history, { faces = cell.faces, value = final })
    render_final(cell)
    update_history(cell.strip, redraw)
    if redraw then refresh(cell.strip, cell.frame, UIDice.FINAL_REFRESH) end
end

--- Tira el dado `faces` de la franja `strip`. Un toque sobre un dado que está girando se ignora.
function UIDice.roll_die(strip, faces)
    local cell = strip.cells[faces]
    if not cell or rolling[faces] then return end
    local final = Dice.roll(faces, UIDice.rng)
    if not UIDice.ANIMATE then
        rolling[faces] = cell
        return finish(cell, final, true)
    end
    rolling[faces] = cell
    cell.final = final
    local delays = UIDice.ANIM_DELAYS
    local prev = results[faces] and results[faces].value

    local function show_frame()
        prev = Dice.next_frame_value(faces, prev, UIDice.rng)
        render(cell, prev, false)
        refresh(strip, cell.frame, UIDice.ANIM_REFRESH)
    end
    local function advance(k)
        cell.timer = function()
            if k >= #delays then
                finish(cell, final, true)
            else
                show_frame()
                advance(k + 1)
            end
        end
        UIManager:scheduleIn(delays[k], cell.timer)
    end
    show_frame()
    advance(1)
end

--- Cancela las animaciones pendientes: cada dado que giraba queda con su resultado final, sin animar.
-- Se llama al cambiar de página, al suspender, al cerrar la hoja y al reconstruir la página.
function UIDice.cancel_all()
    for faces, cell in pairs(rolling) do
        if cell.timer then UIManager:unschedule(cell.timer) end
        cell.timer = nil
        rolling[faces] = nil
        if cell.final then
            results[faces] = { value = cell.final, natural = Dice.is_natural(faces, cell.final) }
            Dice.push_history(history, { faces = faces, value = cell.final })
            render_final(cell)
            if cell.strip then update_history(cell.strip, false) end
        end
    end
end

-- ── Construcción de la franja ───────────────────────────────────────────────

-- Tamaño de los cuadraditos y reparto en filas: 7 en una fila, o 4 + 3 si no entran con el mínimo táctil
local function plan(L)
    local n, w = #Dice.FACES, L.body_w
    local max_side = Layout.dp(UIDice.SIDE_DP)
    local one_row = math.floor((w - (n - 1) * L.gap) / n)
    if one_row >= L.min_touch then
        return math.min(max_side, one_row), { n }
    end
    return math.min(max_side, math.floor((w - 3 * L.gap) / 4)), { 4, n - 4 }
end

local function build_row(L, strip, faces_list, side, w)
    local count = #faces_list
    local spare = w - count * side
    local between = count > 1 and math.max(L.gap, math.floor(spare / (count - 1))) or 0
    if count < 7 then between = L.gap end -- en dos filas, agrupados a la izquierda
    local row = HorizontalGroup:new{ align = "top" }
    for i, faces in ipairs(faces_list) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = between }) end
        local cell = { faces = faces, side = side, L = L, strip = strip,
            face_big = Font:getFace("tfont", faces == 100 and 22 or 26) }
        cell.frame = C.Frame:new{
            width = side, height = side, bordersize = L.border_thick, radius = L.radius, padding = 0, margin = 0,
            background = Blitbuffer.COLOR_WHITE, VerticalGroup:new{},
        }
        render_final(cell)
        cell.touch = C.tappable{ child = cell.frame, w = side, h = side, show_parent = strip.sheet,
            on_tap = function() UIDice.roll_die(strip, faces) end }
        strip.cells[faces] = cell
        table.insert(row, cell.touch)
    end
    return row
end

--- Construye la franja (o reutiliza la viva de esta hoja y este layout) y la deja con los resultados actuales.
-- Reconstruir cancela las animaciones pendientes.
-- @tparam table L layout de la hoja
-- @tparam table sheet la hoja
-- @treturn widget franja
function UIDice.build(L, sheet)
    UIDice.cancel_all()
    if current and current.sheet == sheet and current.L == L then
        for _, cell in pairs(current.cells) do render_final(cell) end
        update_history(current, false)
        return current.widget
    end
    local strip = { sheet = sheet, L = L, cells = {} }
    local side, rows = plan(L)
    local vg = VerticalGroup:new{ align = "left", C.label(L, T("dice.title"), L.body_w), C.vspace(L, L.border + 1) }
    local idx = 1
    for r, count in ipairs(rows) do
        local faces_list = {}
        for i = idx, idx + count - 1 do faces_list[#faces_list + 1] = Dice.FACES[i] end
        idx = idx + count
        if r > 1 then table.insert(vg, VerticalSpan:new{ width = L.gap }) end
        table.insert(vg, build_row(L, strip, faces_list, side, L.body_w))
    end
    strip.history_text = TextWidget:new{ text = " ", face = L.font_small, max_width = L.body_w }
    strip.history_frame = C.Frame:new{
        width = L.body_w, height = strip.history_text:getSize().h + L.gap, bordersize = 0, padding = 0, margin = 0,
        strip.history_text,
    }
    update_history(strip, false)
    table.insert(vg, VerticalSpan:new{ width = L.gap })
    table.insert(vg, strip.history_frame)
    strip.widget = vg
    current = strip
    return vg
end

return UIDice
