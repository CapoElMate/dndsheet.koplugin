-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 6 · Trasfondo: datos del personaje, aspecto físico, apariencia, aliados y organización,
e historia (llena el alto que sobra). Se reparte en subpáginas por bloque si no entra.

@module dndsheet.ui.pages.p6_background
--]]
local C = require("dndsheet/ui/components")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("dndsheet/i18n").T

local Page = {
    id = "background",
    title_key = "page.background",
}

local MIN_STORY_LINES = 4

local function text_field(L, sheet, data, key, label, w)
    return C.field(L, {
        label = label, value = data[key], w = w, show_parent = sheet,
        on_tap = function() sheet:edit(key, "text", { title = label }) end,
    })
end

local function number_field(L, sheet, data, key, label, w, min, max)
    return C.field(L, {
        label = label, value = data[key], w = w, show_parent = sheet,
        on_tap = function() sheet:edit(key, "int", { title = label, min = min, max = max, hold_step = 10 }) end,
    })
end

local function identity(L, sheet, data)
    local w = L.col_w
    local g = VerticalGroup:new{ align = "left" }
    local rows = {
        { text_field(L, sheet, data, "nombre", T("label.name"), w), text_field(L, sheet, data, "jugador", T("bg.player"), w) },
        { text_field(L, sheet, data, "clase_nivel", T("bg.class_level"), w),
          number_field(L, sheet, data, "nivel", T("bg.total_level"), w, 1, 20) },
        { text_field(L, sheet, data, "raza", T("bg.race"), w), text_field(L, sheet, data, "trasfondo", T("bg.background"), w) },
        { text_field(L, sheet, data, "alineamiento", T("bg.alignment"), w),
          number_field(L, sheet, data, "experiencia", T("bg.xp"), w, 0, 9999999) },
    }
    for _i, r in ipairs(rows) do table.insert(g, C.columns(L, r)) end
    return g
end

local function physical(L, sheet, data)
    local w = math.floor((L.body_w - 2 * L.gap) / 3)
    local function f(key, label)
        return C.field(L, {
            label = label, value = data.fisico[key], w = w, show_parent = sheet,
            on_tap = function() sheet:edit("fisico." .. key, "text", { title = label }) end,
        })
    end
    local function row(a, b, c)
        return HorizontalGroup:new{ align = "top", a, HorizontalSpan:new{ width = L.gap }, b,
            HorizontalSpan:new{ width = L.gap }, c }
    end
    return VerticalGroup:new{
        align = "left",
        C.hline(L, L.body_w),
        row(f("edad", T("bg.age")), f("altura", T("bg.height")), f("peso", T("bg.weight"))),
        row(f("ojos", T("bg.eyes")), f("piel", T("bg.skin")), f("pelo", T("bg.hair"))),
        C.hline(L, L.body_w),
    }
end

local function block(L, sheet, data, key, label, lines)
    return C.textblock(L, {
        w = L.body_w, label = label, max_lines = lines, text = data[key], show_parent = sheet,
        on_tap = function() sheet:edit(key, "longtext", { title = label }) end,
    })
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    local ident, phys = identity(L, sheet, data), physical(L, sheet, data)
    local appearance = block(L, sheet, data, "apariencia", T("bg.appearance"), 3)
    local allies = VerticalGroup:new{
        align = "left",
        block(L, sheet, data, "aliados", T("bg.allies"), 3),
        C.vspace(L),
        text_field(L, sheet, data, "organizacion", T("bg.symbol"), L.body_w),
    }
    -- "Historia" ocupa el alto que sobra (al menos MIN_STORY_LINES líneas)
    local used = ident:getSize().h + phys:getSize().h + appearance:getSize().h + allies:getSize().h + 5 * L.gap
    local label_h = C.label(L, "X", 100):getSize().h
    local left = L.body_h - used - label_h - 2 * (L.border + L.pad)
    local lines = math.max(MIN_STORY_LINES, math.floor(left / C.line_px(L)))
    local story = block(L, sheet, data, "historia", T("bg.history"), lines)
    return C.paginate(L, { ident, phys, appearance, allies, story }, ctx.subpage)
end

return Page
