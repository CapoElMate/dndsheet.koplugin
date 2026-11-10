-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 2 · Atributos y habilidades.
Con espacio: grilla de atributos arriba y, debajo, salvaciones | habilidades en dos columnas.
Sin espacio (pantalla chica o fila demasiado baja): subpágina 1 = atributos + salvaciones, 2 = habilidades.

@module dndsheet.ui.pages.p2_abilities
--]]
local C = require("dndsheet/ui/components")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Labels = require("dndsheet/labels")
local Rules = require("dndsheet/rules")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("dndsheet/i18n").T

local Page = {
    id = "abilities",
    title_key = "page.abilities",
}

local N_SKILLS = #Labels.SKILLS

local function attribute_grid(L, sheet, data)
    local per = L.attr_per_row
    local w = math.floor((L.body_w - (per - 1) * L.gap) / per)
    local grid = VerticalGroup:new{ align = "left" }
    local row
    for i, ab in ipairs(Labels.ABILITIES) do
        if (i - 1) % per == 0 then
            if row then table.insert(grid, VerticalSpan:new{ width = L.gap }) end
            row = HorizontalGroup:new{ align = "top" }
            table.insert(grid, row)
        else
            table.insert(row, HorizontalSpan:new{ width = L.gap })
        end
        local score = data.atributos[ab.key]
        table.insert(row, C.statbox(L, {
            label = string.format("%s · %d", Labels.ability_name(ab.key), score), value = Rules.fmt_signed(Rules.mod(score)), w = w,
            show_parent = sheet,
            on_tap = function()
                sheet:edit("atributos." .. ab.key, "int", { title = Labels.ability_name(ab.key), min = 1, max = 30 })
            end,
        }))
    end
    return grid
end

local function list(L, title, rows, w)
    local g = VerticalGroup:new{ align = "left", C.label(L, title, w), C.hline(L, w) }
    for _i, r in ipairs(rows) do table.insert(g, r) end
    return g
end

local function save_rows(L, sheet, data, w, h)
    local rows = {}
    for _i, ab in ipairs(Labels.ABILITIES) do
        local k = ab.key
        table.insert(rows, C.row(L, {
            w = w, h = h, show_parent = sheet,
            mark = data.salvaciones[k] and C.MARK[1] or C.MARK[0],
            left = Labels.ability_name(ab.key), right = Rules.fmt_signed(Rules.save(data, k)),
            on_tap = function() sheet:edit("salvaciones." .. k, "toggle") end,
        }))
    end
    table.insert(rows, C.row(L, {
        w = w, h = h, show_parent = sheet, left = T("derived.proficiency"), right = Rules.fmt_signed(Rules.prof(data)),
        on_tap = function()
            sheet:edit("ajustes.competencia", "override", {
                title = T("derived.proficiency_title"), auto_value = Rules.prof(data), min = 0, max = 12,
            })
        end,
    }))
    table.insert(rows, C.row(L, {
        w = w, h = h, show_parent = sheet, left = T("derived.passive"), right = tostring(Rules.passive(data)),
        on_tap = function()
            sheet:edit("ajustes.percepcion_pasiva", "override", {
                title = T("derived.passive"), auto_value = Rules.passive(data), min = 0, max = 60,
            })
        end,
    }))
    return rows
end

local function skill_rows(L, sheet, data, w, h)
    local rows = {}
    for _i, s in ipairs(Labels.SKILLS) do
        local rank = data.habilidades[s.key]
        table.insert(rows, C.row(L, {
            w = w, h = h, show_parent = sheet,
            mark = C.MARK[rank] or C.MARK[0],
            left = Labels.skill_name(s.key), right = Rules.fmt_signed(Rules.skill(data, s.key)),
            on_tap = function() sheet:edit("habilidades." .. s.key, "cycle", { max = 2 }) end,
        }))
    end
    return rows
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    local grid = attribute_grid(L, sheet, data)
    local grid_h = grid:getSize().h
    local header_h = C.label(L, "X", 100):getSize().h + L.border

    -- ¿Entran las 18 habilidades en dos columnas, con filas de al menos L.row_min?
    local avail = L.body_h - grid_h - L.gap - header_h
    local row_h = math.min(L.row_h, math.floor(avail / N_SKILLS))
    if L.two_columns and row_h >= L.row_min then
        local left = list(L, T("section.saves"), save_rows(L, sheet, data, L.col_w, row_h), L.col_w)
        local right = list(L, T("section.skills"), skill_rows(L, sheet, data, L.col_w, row_h), L.col_w)
        return VerticalGroup:new{
            align = "left", grid, C.vspace(L), C.columns(L, { left, right }),
        }, 1
    end

    -- Subpáginas por bloques: atributos + salvaciones (si caben juntos) y habilidades (en una o dos listas)
    local save_avail = L.body_h - grid_h - L.gap - header_h
    local h_save = math.max(L.row_min, math.min(L.row_h, math.floor(save_avail / 8)))
    local blocks = {
        grid,
        list(L, T("section.saves"), save_rows(L, sheet, data, L.body_w, h_save), L.body_w),
    }
    local all_skills = Labels.SKILLS
    local h_skill = math.min(L.row_h, math.floor((L.body_h - header_h) / N_SKILLS))
    if h_skill >= L.row_min then
        blocks[#blocks + 1] = list(L, T("section.skills"), skill_rows(L, sheet, data, L.body_w, h_skill), L.body_w)
    else
        -- ni así entran las 18 filas con el alto mínimo: dos listas de 9
        local h_half = math.max(L.row_min, math.min(L.row_h, math.floor((L.body_h - header_h) / 9)))
        local rows = skill_rows(L, sheet, data, L.body_w, h_half)
        for part = 1, 2 do
            local chunk = {}
            for i = (part - 1) * 9 + 1, math.min(part * 9, #all_skills) do chunk[#chunk + 1] = rows[i] end
            blocks[#blocks + 1] = list(L, string.format("%s %d/2", T("section.skills"), part), chunk, L.body_w)
        end
    end
    return C.paginate(L, blocks, ctx.subpage)
end

return Page
