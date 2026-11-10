-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Medidas para cualquier pantalla: ÚNICA fuente de tamaños del plugin.
Anchos proporcionales; altos y áreas táctiles en dp (Screen:scaleBySize); fuentes por alias.

@module dndsheet.layout
--]]
local Device = require("device")
local Font = require("ui/font")
local Size = require("ui/size")
local Screen = Device.screen

local Layout = {}

--- Factor px por dp (scaleBySize redondea hacia arriba, así que se mide con una base grande).
function Layout.dp_scale()
    return Screen:scaleBySize(1000) / 1000
end

--- dp → px (KOReader escala según el tamaño/densidad de la pantalla).
function Layout.dp(n)
    return Screen:scaleBySize(n)
end

--- Calcula las medidas.
-- @int w ancho de la ventana
-- @int h alto de la ventana
-- @int chrome_h alto del título + pie (lo mide la hoja); 0 si todavía no se conoce
-- @treturn table L
function Layout.compute(w, h, chrome_h)
    local dp = Layout.dp
    local L = { w = w, h = h }
    L.portrait = h >= w
    L.margin = math.floor(math.min(w, h) * 0.025)
    L.gap = dp(6)
    L.min_touch = dp(40)
    L.body_w = w - 2 * L.margin
    L.body_h = h - (chrome_h or 0) - 2 * L.margin

    -- El ancho en dp decide las columnas
    local body_dp = L.body_w / Layout.dp_scale()
    L.two_columns = body_dp >= 500
    L.col_w = L.two_columns and math.floor((L.body_w - L.gap) / 2) or L.body_w
    L.attr_per_row = (not L.portrait and body_dp >= 900) and 6 or 3
    L.row_h = math.max(L.min_touch, dp(36))
    -- alto mínimo de una fila de lista densa (18 habilidades): 4,2 mm reales (el ancho completo es táctil)
    L.row_min = math.ceil(Screen:getDPI() * 4.2 / 25.4)

    -- Tipografía: una sola familia (la de KOReader). Los tamaños son dp de fuente.
    L.font_label = Font:getFace("smallinfofontbold", 14)
    L.font_text = Font:getFace("cfont", 18)
    L.font_value = Font:getFace("cfont", 20)
    L.font_big = Font:getFace("tfont", 30)
    L.font_small = Font:getFace("xx_smallinfofont", 14)
    L.btn_font_size = 28 -- tamaño (dp de fuente) del texto de los botones − + ‹ ›
    L.border = Size.border.thin
    L.border_thick = Size.border.thick
    L.radius = Size.radius.default
    L.pad = Size.padding.default
    return L
end

return Layout
