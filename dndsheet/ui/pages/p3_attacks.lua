-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 3 · Ataques y equipo: tabla de ataques, monedas, equipo, tesoro y otras competencias.
Si no entra todo, se reparte en subpáginas por bloque (nunca se corta un bloque).

@module dndsheet.ui.pages.p3_attacks
--]]
local C = require("dndsheet/ui/components")
local UIDice = require("dndsheet/ui/dice")
local Editors = require("dndsheet/ui/editors")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("dndsheet/i18n").T

local Page = {
    id = "attacks",
    title_key = "page.attacks",
}

local MAX_ATTACK_ROWS = 6 -- más que esto: "Ver todos (n)"

local COINS = {
    { key = "pc", label_key = "coin.pc" }, { key = "pp", label_key = "coin.pp" }, { key = "pe", label_key = "coin.pe" },
    { key = "po", label_key = "coin.po" }, { key = "ppt", label_key = "coin.ppt" },
}

local function attack_fields()
    return {
        { name = "nombre", hint = T("label.name") },
        { name = "bonus", hint = T("attack.bonus_field") },
        { name = "dano", hint = T("attack.damage_field") },
    }
end

local function edit_attack(sheet, index)
    sheet:edit("ataques." .. index, "record", { fields = attack_fields(), title = T("label.attack") })
end

local function add_attack(sheet)
    sheet:edit("ataques", "record", { new = true, fields = attack_fields(), title = T("attack.new") })
end

local function confirm_delete(sheet, index, name)
    Editors.confirm(T("attack.delete_confirm", name ~= "" and name or "—"), T("common.delete"),
        function() sheet:removeItem("ataques", index) end)
end

-- Menú con TODOS los ataques (cuando no entran en la página)
local function show_all(sheet, data)
    local items = {}
    for i, a in ipairs(data.ataques) do
        items[#items + 1] = {
            text = string.format("%s   %s   %s", a.nombre, a.bonus, a.dano),
            callback = function() edit_attack(sheet, i) end,
            hold_callback = function() confirm_delete(sheet, i, a.nombre) end,
        }
    end
    local menu
    menu = Menu:new{
        title = T("attack.section"),
        item_table = items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
    return menu
end

local function attacks_block(L, sheet, data)
    local w = L.body_w
    local cw = { math.floor(w * 0.42), math.floor(w * 0.18), 0 }
    cw[3] = w - cw[1] - cw[2]
    local g = VerticalGroup:new{ align = "left", C.label(L, T("attack.table_title"), w), C.hline(L, w) }
    table.insert(g, C.cells(L, { h = L.row_min, cells = {
        { text = T("label.name"), w = cw[1], face = L.font_small, bold = true },
        { text = T("attack.bonus"), w = cw[2], face = L.font_small, bold = true },
        { text = T("attack.damage"), w = cw[3], face = L.font_small, bold = true },
    } }))
    local n = #data.ataques
    local shown = math.min(n, MAX_ATTACK_ROWS)
    for i = 1, shown do
        local a = data.ataques[i]
        table.insert(g, C.cells(L, {
            show_parent = sheet,
            cells = { { text = a.nombre, w = cw[1] }, { text = a.bonus, w = cw[2] }, { text = a.dano, w = cw[3] } },
            on_tap = function() edit_attack(sheet, i) end,
            on_hold = function() confirm_delete(sheet, i, a.nombre) end,
        }))
    end
    if n > shown then
        table.insert(g, C.row(L, { w = w, show_parent = sheet, left = T("attack.view_all", n),
            on_tap = function() show_all(sheet, data) end }))
    end
    table.insert(g, C.row(L, { w = w, show_parent = sheet, left = T("attack.add"),
        on_tap = function() add_attack(sheet) end }))
    table.insert(g, C.row(L, { w = w, show_parent = sheet, left = T("attack.add_compendium"),
        on_tap = function() sheet:openCompendium({ start = "weapons" }) end }))
    return g
end

local function attack_notes_block(L, sheet, data)
    return C.textblock(L, {
        w = L.body_w, max_lines = 3, text = data.ataques_notas, hint = T("attack.notes_hint"),
        show_parent = sheet,
        on_tap = function() sheet:edit("ataques_notas", "longtext", { title = T("attack.notes") }) end,
    })
end

local function coins_block(L, sheet, data)
    local w = L.body_w
    local cell_w = math.floor((w - (#COINS - 1) * L.gap) / #COINS)
    local row = HorizontalGroup:new{ align = "top" }
    for i, coin in ipairs(COINS) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = L.gap }) end
        table.insert(row, C.field(L, {
            label = T(coin.label_key), value = data.monedas[coin.key], w = cell_w, show_parent = sheet,
            on_tap = function()
                sheet:edit("monedas." .. coin.key, "coins", { key = coin.key, title = T(coin.label_key .. ".name") })
            end,
        }))
    end
    return (C.section(L, T("gear.coins"), row, w))
end

local function text_block(L, sheet, data, key, label, lines, title)
    return C.textblock(L, {
        w = L.body_w, label = label, max_lines = lines, text = data[key], show_parent = sheet,
        on_tap = function() sheet:edit(key, "longtext", { title = title or label }) end,
    })
end

-- Cambiar de página, suspender o cerrar la hoja cancela las animaciones de dados (F-06)
Page.leave = UIDice.cancel_all
Page.release = UIDice.cancel_all

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    -- La franja de dados es fija al pie: se reserva su alto ANTES de paginar el resto (F-06)
    local strip = UIDice.build(L, sheet)
    local strip_h = strip:getSize().h
    local L2 = setmetatable({ body_h = L.body_h - strip_h - L.gap }, { __index = L })
    local content, total = C.paginate(L2, {
        attacks_block(L, sheet, data),
        attack_notes_block(L, sheet, data),
        coins_block(L, sheet, data),
        text_block(L, sheet, data, "equipo", T("gear.equipment"), 6),
        text_block(L, sheet, data, "tesoro", T("gear.treasure"), 2),
        text_block(L, sheet, data, "otras_competencias", T("gear.proficiencies"), 3),
    }, ctx.subpage)
    -- el contenido ocupa el alto restante; la franja queda pegada al pie
    local spare = math.max(0, L2.body_h - content:getSize().h)
    return VerticalGroup:new{ align = "left", content, VerticalSpan:new{ width = spare + L.gap }, strip }, total
end

return Page
