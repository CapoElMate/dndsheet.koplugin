-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 5 · Conjuros: encabezado (clase, aptitud, CD, ataque), trucos, niveles con ranuras
y conjuros preparados. Solo se muestran los niveles con ranuras o conjuros; se reparten en subpáginas
por nivel completo (nunca se corta un nivel).

@module dndsheet.ui.pages.p5_spells
--]]
local C = require("dndsheet/ui/components")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local Labels = require("dndsheet/labels")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Rules = require("dndsheet/rules")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local rapidjson = require("rapidjson")
local T = require("dndsheet/i18n").T

local Page = {
    id = "spells",
    title_key = "page.spells",
}

local MARK_PREPARED, MARK_UNPREPARED = "◉", "○"

local function level_visible(lv)
    return lv and ((lv.total or 0) > 0 or #lv.lista > 0)
end

local function has_spells(data)
    for n = 0, 9 do
        if level_visible(data.conjuros.niveles[tostring(n)]) then return true end
    end
    return false
end

local function header(L, sheet, data)
    local w = L.body_w
    local gap = L.gap
    local ab = data.conjuros.aptitud
    local ab_label = Labels.ABILITY_BY_KEY[ab] and Labels.ability_abbr(ab) or "—"
    local clase_w = math.floor(w * 0.34)
    local small_w = math.floor((w - clase_w - 3 * gap) / 3)
    local dc, atk = Rules.spell_dc(data), Rules.spell_atk(data)
    local function auto(v) return v or 10 end
    return HorizontalGroup:new{
        align = "top",
        C.field(L, { label = T("spell.class"), value = data.conjuros.clase, w = clase_w, show_parent = sheet,
            on_tap = function() sheet:edit("conjuros.clase", "text", { title = T("spell.class_title") }) end }),
        HorizontalSpan:new{ width = gap },
        C.field(L, { label = T("spell.ability"), value = ab_label, w = small_w, show_parent = sheet,
            on_tap = function()
                sheet:edit("conjuros.aptitud", "rotate", { values = { "int", "sab", "car", rapidjson.null } })
            end }),
        HorizontalSpan:new{ width = gap },
        C.field(L, { label = T("spell.dc"), value = dc and tostring(dc) or "—", w = small_w, show_parent = sheet,
            on_tap = function()
                sheet:edit("ajustes.cd_conjuros", "override", {
                    title = T("spell.dc_title"), auto_value = auto(dc), min = 0, max = 40 })
            end }),
        HorizontalSpan:new{ width = gap },
        C.field(L, { label = T("label.attack"), value = atk and Rules.fmt_signed(atk) or "—", w = small_w, show_parent = sheet,
            on_tap = function()
                sheet:edit("ajustes.ataque_conjuros", "override", {
                    title = T("spell.attack_title"), auto_value = auto(atk), min = -10, max = 30 })
            end }),
    }
end

local function cantrips(L, sheet, data)
    local names = {}
    for _i, s in ipairs(data.conjuros.niveles["0"].lista) do names[#names + 1] = s.nombre end
    return C.textblock(L, {
        w = L.body_w, label = T("spell.cantrips"), max_lines = 2, text = table.concat(names, " · "),
        hint = T("spell.cantrips_hint"), show_parent = sheet,
        on_tap = function()
            sheet:edit("conjuros.niveles.0.lista", "namelist", { title = T("spell.cantrips") })
        end,
    })
end

local function level_block(L, sheet, data, n)
    local lv = data.conjuros.niveles[tostring(n)]
    local base = "conjuros.niveles." .. n
    local w = L.body_w
    local row_h = L.row_min + math.floor((L.row_h - L.row_min) / 2)
    local function set_total()
        sheet:edit(base .. ".total", "int", { title = T("spell.slots_title", n), min = 0, max = 20 })
    end

    local label = C.tappable{
        child = LeftContainer:new{
            dimen = Geom:new{ w = math.floor(w * 0.4), h = L.min_touch },
            TextWidget:new{ text = C.upper(T("spell.level", n)), face = L.font_label, bold = true },
        },
        on_hold = set_total, show_parent = sheet,
    }
    local pips = C.pips(L, {
        total = lv.total or 0, used = lv.usados or 0, show_parent = sheet,
        on_tap_index = function(i) sheet:edit(base .. ".usados", "pip", { index = i }) end,
        on_hold = set_total,
    })
    local pips_w = pips:getSize().w
    local head = HorizontalGroup:new{
        align = "center", label,
        HorizontalSpan:new{ width = math.max(L.gap, w - label:getSize().w - pips_w) },
        pips,
    }

    local g = VerticalGroup:new{ align = "left", head, C.hline(L, w) }
    for i, spell in ipairs(lv.lista) do
        table.insert(g, C.row(L, {
            w = w, h = row_h, show_parent = sheet,
            mark = spell.preparado == true and MARK_PREPARED or MARK_UNPREPARED,
            left = spell.nombre,
            on_tap = function() sheet:edit(base .. ".lista." .. i .. ".preparado", "toggle") end,
            on_hold = function() sheet:edit(base .. ".lista." .. i, "spell_menu") end,
        }))
    end
    table.insert(g, C.row(L, {
        w = w, h = row_h, show_parent = sheet, left = T("spell.add"),
        on_tap = function()
            sheet:edit(base .. ".lista", "record", {
                new = true, title = T("spell.new_title", n),
                fields = { { name = "nombre", hint = T("spell.name") } },
            })
        end,
    }))
    return g
end

local function empty_state(L, sheet)
    local text = TextWidget:new{ text = T("spell.empty"), face = L.font_value, max_width = L.body_w }
    return C.tappable{
        child = CenterContainer:new{ dimen = Geom:new{ w = L.body_w, h = L.body_h }, text },
        w = L.body_w, h = L.body_h, show_parent = sheet,
        on_tap = function()
            sheet:edit("conjuros.aptitud", "rotate", { values = { "int", "sab", "car", rapidjson.null } })
        end,
    }
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    if data.conjuros.aptitud == rapidjson.null and not has_spells(data) then
        return empty_state(L, sheet), 1
    end
    local blocks = { header(L, sheet, data), cantrips(L, sheet, data) }
    for n = 1, 9 do
        if level_visible(data.conjuros.niveles[tostring(n)]) then
            blocks[#blocks + 1] = level_block(L, sheet, data, n)
        end
    end
    blocks[#blocks + 1] = C.row(L, {
        w = L.body_w, show_parent = sheet, left = T("spell.add_level"),
        on_tap = function() sheet:edit("conjuros", "add_level") end,
    })
    blocks[#blocks + 1] = C.row(L, {
        w = L.body_w, show_parent = sheet, left = T("spell.add_compendium"),
        on_tap = function() sheet:openCompendium({ start = "spells" }) end,
    })
    return C.paginate(L, blocks, ctx.subpage)
end

return Page
