-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 4 · Rasgos y personalidad: personalidad en grilla 2×2 (o 4×1 sin dos columnas),
rasgos y atributos (llena el alto que sobra) y rasgos adicionales.

@module dndsheet.ui.pages.p4_traits
--]]
local C = require("dndsheet/ui/components")
local Compendium = require("dndsheet/compendium")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("dndsheet/i18n").T

local Page = {
    id = "traits",
    title_key = "page.traits",
}

local PERSONALITY = {
    { key = "rasgos", label_key = "trait.personality" },
    { key = "ideales", label_key = "trait.ideals" },
    { key = "vinculos", label_key = "trait.bonds" },
    { key = "defectos", label_key = "trait.flaws" },
}

local MIN_TRAIT_LINES = 4 -- mínimo de líneas visibles de "Rasgos y atributos"

local function block(L, sheet, path, text, label, lines, w)
    return C.textblock(L, {
        w = w, label = label, max_lines = lines, text = text, show_parent = sheet,
        on_tap = function() sheet:edit(path, "longtext", { title = label }) end,
    })
end

local function personality_grid(L, sheet, data)
    local w = L.col_w
    local cells = {}
    for i, p in ipairs(PERSONALITY) do
        cells[i] = block(L, sheet, "personalidad." .. p.key, data.personalidad[p.key], T(p.label_key), 3, w)
    end
    if L.two_columns then
        return VerticalGroup:new{
            align = "left",
            C.columns(L, { cells[1], cells[2] }), C.vspace(L),
            C.columns(L, { cells[3], cells[4] }),
        }
    end
    local g = VerticalGroup:new{ align = "left" }
    for i, c in ipairs(cells) do
        if i > 1 then table.insert(g, C.vspace(L)) end
        table.insert(g, c)
    end
    return g
end

-- Reglas agregadas desde el compendio (F-08): arriba del texto libre, que no se toca.
-- No se lee ningún JSON: "(sin regla)" solo se marca si el compendio ya estaba abierto en memoria.
local function ref_label(item)
    local name = item.nombre ~= "" and item.nombre or item.ref
    if Compendium.peekShared(item.ref) == false then name = T("trait.ref_missing", name) end
    if item.nota ~= "" then name = name .. " — " .. item.nota end
    return name
end

-- Devuelve bloques (cada uno entra en una página): título + filas + "+ Desde el compendio".
local function refs_blocks(L, sheet, data)
    local w = L.body_w
    local rows = {}
    for i, item in ipairs(data.rasgos_ref) do
        rows[#rows + 1] = C.row(L, {
            w = w, show_parent = sheet, left = ref_label(item),
            on_tap = function() sheet:viewRule(item.ref, item.nombre) end,
            on_hold = function() sheet:edit("rasgos_ref." .. i, "ref_menu") end,
        })
    end
    rows[#rows + 1] = C.row(L, { w = w, show_parent = sheet, left = T("trait.add_compendium"),
        on_tap = function() sheet:openCompendium({ start = "features" }) end })
    local head_h = C.label(L, "X", w):getSize().h + C.hline(L, w):getSize().h
    local row_h = rows[1]:getSize().h
    local fit = math.max(1, math.floor((L.body_h - head_h - L.gap) / row_h))
    local blocks = {}
    local i = 1
    while i <= #rows do
        local g = VerticalGroup:new{ align = "left" }
        if i == 1 then
            table.insert(g, C.label(L, T("trait.refs_title"), w))
            table.insert(g, C.hline(L, w))
        end
        local n = 0
        while i <= #rows and n < fit do
            table.insert(g, rows[i])
            i, n = i + 1, n + 1
        end
        blocks[#blocks + 1] = g
    end
    return blocks
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    local grid = personality_grid(L, sheet, data)
    local extra = block(L, sheet, "rasgos_adicionales", data.rasgos_adicionales, T("trait.additional"), 3, L.body_w)

    local refs = refs_blocks(L, sheet, data)
    local refs_h = 0
    for _i, b in ipairs(refs) do refs_h = refs_h + b:getSize().h + L.gap end

    -- "Rasgos y atributos" se queda con el alto que sobra (al menos MIN_TRAIT_LINES líneas)
    local label_h = C.label(L, "X", 100):getSize().h
    local frame_h = 2 * (L.border + L.pad)
    local left = L.body_h - grid:getSize().h - refs_h - extra:getSize().h - 3 * L.gap - label_h - frame_h
    local lines = math.max(MIN_TRAIT_LINES, math.floor(left / C.line_px(L)))
    local traits = block(L, sheet, "rasgos", data.rasgos, T("trait.features"), lines, L.body_w)

    local blocks = { grid }
    for _i, b in ipairs(refs) do blocks[#blocks + 1] = b end
    blocks[#blocks + 1] = traits
    blocks[#blocks + 1] = extra
    return C.paginate(L, blocks, ctx.subpage)
end

return Page
