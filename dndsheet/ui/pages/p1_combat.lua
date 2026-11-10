-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 1 · Combate: lo que se consulta en cada turno.

@module dndsheet.ui.pages.p1_combat
--]]
local Button = require("ui/widget/button")
local C = require("dndsheet/ui/components")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Rules = require("dndsheet/rules")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("dndsheet/i18n").T

local Page = {
    id = "combat",
    title_key = "page.combat",
}

local function stat_row(L, sheet, data, width)
    local gap = L.gap
    local w = math.floor((width - 3 * gap) / 4)
    local function box(label, value, on_tap)
        return C.statbox(L, { label = label, value = value, w = w, show_parent = sheet, on_tap = on_tap })
    end
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, box(T("combat.ac"), data.ca, function()
        sheet:edit("ca", "int", { title = T("combat.ac_title"), min = 0, max = 40 })
    end))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, box(T("combat.initiative"), Rules.fmt_signed(Rules.initiative(data)), function()
        sheet:edit("ajustes.iniciativa", "override", {
            title = T("combat.initiative"), auto_value = Rules.initiative(data), min = -20, max = 30,
        })
    end))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, box(T("combat.speed"), data.velocidad ~= "" and data.velocidad or "—", function()
        sheet:edit("velocidad", "text", { title = T("combat.speed") })
    end))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, C.statbox(L, {
        label = T("combat.inspiration"), value = data.inspiracion, w = w, show_parent = sheet,
        on_tap = function() -- tocar: elegir la cantidad
            sheet:edit("inspiracion", "int", { title = T("combat.inspiration"), min = 0, max = 99 })
        end,
        on_hold = function() -- mantener presionado: gastar una (-1, mínimo 0)
            if data.inspiracion > 0 then
                sheet:mutate(function(d) d.inspiracion = d.inspiracion - 1 end)
            end
        end,
    }))
    return row
end

local function hp_block(L, sheet, data, width)
    local hp = data.hp
    local inner = VerticalGroup:new{ align = "center" }
    local inner_w = width - 2 * (L.border_thick + L.pad)
    table.insert(inner, C.counter(L, {
        value = string.format("%d / %d", hp.actual, hp.maximo),
        w = inner_w,
        show_parent = sheet,
        on_minus = function()
            sheet:mutate(function(d) d.hp.actual = math.max(0, d.hp.actual - 1) end)
        end,
        on_plus = function()
            sheet:mutate(function(d) Rules.apply_heal(d, 1) end)
        end,
        on_tap = function() sheet:edit("hp", "hp") end,
    }))
    local sub = string.format("%s: %d", T("hp.temporary"), hp.temporal)
    if hp.actual == 0 then
        sub = T("hp.unconscious") .. "  ·  " .. sub
    end
    table.insert(inner, C.tappable{
        child = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = L.min_touch },
            TextWidget:new{ text = sub, face = L.font_value, bold = hp.actual == 0, max_width = inner_w },
        },
        on_tap = function() sheet:edit("hp.temporal", "int", { title = T("hp.temp_title"), min = 0, max = 999 }) end,
        show_parent = sheet,
    })
    local block = C.section(L, T("combat.hp"), inner, width)
    return block
end

local function hit_dice_row(L, sheet, data, width)
    local gap = L.gap
    local label_w = math.floor(width * 0.4)
    local total = Rules.hit_dice_count(data.dados_golpe.total)
    local dice = C.field(L, {
        label = T("combat.hit_dice"), value = data.dados_golpe.total, w = label_w, show_parent = sheet,
        on_tap = function() sheet:edit("dados_golpe.total", "text", { title = T("combat.hit_dice_field") }) end,
    })
    local rest = data.dados_golpe.restantes
    local counter = C.counter(L, {
        value = string.format("%d / %s", rest, total and tostring(total) or "?"),
        w = width - label_w - gap,
        show_parent = sheet,
        on_minus = function()
            sheet:mutate(function(d) d.dados_golpe.restantes = math.max(0, d.dados_golpe.restantes - 1) end)
        end,
        on_plus = function()
            sheet:mutate(function(d)
                d.dados_golpe.restantes = math.min(total or 999, d.dados_golpe.restantes + 1)
            end)
        end,
    })
    return HorizontalGroup:new{ align = "center", dice, HorizontalSpan:new{ width = gap }, counter }
end

local function death_saves(L, sheet, data, width, stack)
    local w = stack and width or L.col_w
    local function column(label, path, count)
        return HorizontalGroup:new{
            align = "center",
            TextWidget:new{ text = label, face = L.font_text, max_width = math.floor(w * 0.4) },
            HorizontalSpan:new{ width = L.gap },
            C.pips(L, {
                total = 3, used = count, show_parent = sheet,
                on_tap_index = function(i) sheet:edit(path, "pip", { index = i }) end,
            }),
        }
    end
    local a = column(T("death.successes"), "muerte.exitos", data.muerte.exitos)
    local b = column(T("death.failures"), "muerte.fallos", data.muerte.fallos)
    local both
    if stack then
        both = VerticalGroup:new{ align = "left", a, b }
    else
        both = C.columns(L, { a, b })
    end
    return (C.section(L, T("combat.death_saves"), both, width))
end

local function derived_row(L, sheet, data, width)
    local w = math.floor((width - L.gap) / 2)
    return HorizontalGroup:new{
        align = "top",
        C.field(L, {
            label = T("derived.passive"), value = Rules.passive(data), w = w, show_parent = sheet,
            on_tap = function()
                sheet:edit("ajustes.percepcion_pasiva", "override", {
                    title = T("derived.passive"), auto_value = Rules.passive(data), min = 0, max = 60,
                })
            end,
        }),
        HorizontalSpan:new{ width = L.gap },
        C.field(L, {
            label = T("derived.proficiency"), value = Rules.fmt_signed(Rules.prof(data)), w = w, show_parent = sheet,
            on_tap = function()
                sheet:edit("ajustes.competencia", "override", {
                    title = T("derived.proficiency_title"), auto_value = Rules.prof(data), min = 0, max = 12,
                })
            end,
        }),
    }
end

local function rest_buttons(L, sheet, width)
    local w = math.floor((width - L.gap) / 2)
    local function btn(text, action)
        return Button:new{ text = text, width = w, callback = function() sheet:act(action) end, show_parent = sheet }
    end
    return HorizontalGroup:new{
        align = "center",
        btn(T("rest.short"), "short_rest"),
        HorizontalSpan:new{ width = L.gap },
        btn(T("rest.long"), "long_rest"),
    }
end

-- Los 6 bloques de la página con el ancho `width` (stack = pips de muerte uno debajo del otro)
local function blocks_for(L, sheet, data, width, stack)
    return {
        stat_row(L, sheet, data, width),
        hp_block(L, sheet, data, width),
        hit_dice_row(L, sheet, data, width),
        death_saves(L, sheet, data, width, stack),
        derived_row(L, sheet, data, width),
        rest_buttons(L, sheet, width),
    }
end

local function stack_height(L, blocks, first, last)
    local h = 0
    for i = first, last do h = h + blocks[i]:getSize().h + (i > first and L.gap or 0) end
    return h
end

local function vgroup(L, blocks, first, last)
    local g = VerticalGroup:new{ align = "left" }
    for i = first, last do
        if i > first then table.insert(g, C.vspace(L)) end
        table.insert(g, blocks[i])
    end
    return g
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    -- 1) una columna a todo el ancho (pantalla vertical)
    local blocks = blocks_for(L, sheet, data, L.body_w, false)
    if stack_height(L, blocks, 1, #blocks) <= L.body_h then
        return vgroup(L, blocks, 1, #blocks), 1
    end
    -- 2) pantalla horizontal: recuadros a todo el ancho y, debajo, dos columnas:
    --    HP y dados | salvaciones de muerte, derivados y descansos
    if L.two_columns then
        local cols = blocks_for(L, sheet, data, L.col_w, true)
        local top = blocks[1]
        local left_h, right_h = stack_height(L, cols, 2, 3), stack_height(L, cols, 4, 6)
        if top:getSize().h + L.gap + math.max(left_h, right_h) <= L.body_h then
            return VerticalGroup:new{
                align = "left", top, C.vspace(L),
                C.columns(L, { vgroup(L, cols, 2, 3), vgroup(L, cols, 4, 6) }),
            }, 1
        end
    end
    -- 3) pantallas muy bajas: subpáginas por bloque
    return C.paginate(L, blocks, ctx.subpage)
end

return Page
