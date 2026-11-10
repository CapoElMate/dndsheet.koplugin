-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Página 7 · Notas libres: texto sin estructura, paginado con un único TextBoxWidget
que se reposiciona por subpágina (se compone el texto una sola vez por cambio de texto o de medidas).

@module dndsheet.ui.pages.p7_notes
--]]
local C = require("dndsheet/ui/components")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Blitbuffer = require("ffi/blitbuffer")
local T = require("dndsheet/i18n").T

local Page = {
    id = "notes",
    title_key = "page.notes",
    no_cache = true, -- el TextBoxWidget compartido se reposiciona en cada build
}

-- TextBoxWidget compartido: se recompone solo si cambia el texto o las medidas
local shared = { key = nil, widget = nil }

function Page.release()
    if shared.widget then shared.widget:free(true) end
    shared.key, shared.widget = nil, nil
end

--- Muestra el TextBoxWidget a partir de la línea `line` (como scrollLines, pero sin acotar a la última página).
local function show_from_line(tb, line)
    if tb.virtual_line_num == line then return end
    tb.virtual_line_num = line
    tb:free(false)
    tb:_updateLayout()
end

local function get_text_box(L, text, width, height)
    local key = table.concat({ #text, text:sub(1, 64), text:sub(-64), width, height, L.font_text.size }, "|")
    if shared.key ~= key then
        Page.release()
        shared.widget = TextBoxWidget:new{ text = text, face = L.font_text, width = width, height = height }
        shared.key = key
    end
    return shared.widget
end

function Page.build(ctx)
    local L, sheet, data = ctx.layout, ctx.sheet, ctx.data
    local edit = function() sheet:edit("notas", "longtext", { title = T("page.notes"), nav_bar = true }) end

    local edit_btn = C.tappable{
        child = LeftContainer:new{
            dimen = Geom:new{ w = math.floor(L.body_w * 0.3), h = L.min_touch },
            TextWidget:new{ text = "✎ " .. T("common.edit"), face = L.font_value, max_width = math.floor(L.body_w * 0.3) },
        },
        on_tap = edit, show_parent = sheet,
    }
    local title = C.label(L, T("page.notes"), L.body_w - edit_btn:getSize().w)
    local head = HorizontalGroup:new{
        align = "center", title,
        HorizontalSpan:new{ width = L.body_w - title:getSize().w - edit_btn:getSize().w }, edit_btn,
    }
    local area_h = L.body_h - head:getSize().h - L.gap
    local pad = L.pad

    if data.notas == nil or data.notas == "" then
        local hint = TextWidget:new{ text = T("hint.tap_to_write"), face = L.font_text,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = L.body_w }
        return VerticalGroup:new{
            align = "left", head, C.vspace(L),
            C.tappable{
                child = LeftContainer:new{ dimen = Geom:new{ w = L.body_w, h = area_h }, hint },
                w = L.body_w, h = area_h, on_tap = edit, show_parent = sheet,
            },
        }, 1
    end

    local tb = get_text_box(L, data.notas, L.body_w - 2 * pad, area_h - 2 * pad)
    local lpp = math.max(1, tb.lines_per_page)
    local total = math.max(1, math.ceil(#tb.vertical_string_list / lpp))
    local sub = math.max(1, math.min(ctx.subpage or 1, total))
    show_from_line(tb, (sub - 1) * lpp + 1)

    local box = C.Frame:new{
        width = L.body_w, height = area_h, bordersize = 0, padding = pad, margin = 0,
        tb,
    }
    return VerticalGroup:new{
        align = "left", head, C.vspace(L),
        C.tappable{ child = box, w = L.body_w, h = area_h, on_tap = edit, show_parent = sheet },
    }, total
end

return Page
