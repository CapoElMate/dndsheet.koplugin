-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Ventana de la hoja de personaje: marco (título, cuerpo, pie), navegación entre páginas,
caché de páginas, edición, y guardado con debounce.

@module dndsheet.ui.sheet
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local C = require("dndsheet/ui/components")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Editors = require("dndsheet/ui/editors")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Layout = require("dndsheet/layout")
local Perf = require("dndsheet/perf")
local Schema = require("dndsheet/schema")
local Settings = require("dndsheet/settings")
local Store = require("dndsheet/store")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen
local T = require("dndsheet/i18n").T

-- Las 7 páginas, en orden. Cada módulo exporta id, title y build(ctx).
local PAGES = {
    require("dndsheet/ui/pages/p1_combat"),
    require("dndsheet/ui/pages/p2_abilities"),
    require("dndsheet/ui/pages/p3_attacks"),
    require("dndsheet/ui/pages/p4_traits"),
    require("dndsheet/ui/pages/p5_spells"),
    require("dndsheet/ui/pages/p6_background"),
    require("dndsheet/ui/pages/p7_notes"),
}

local SAVE_DELAY = 1.5 -- segundos de debounce del guardado

--- Devuelve el valor como texto no vacío, o nil.
local function text_or_nil(v)
    if type(v) == "string" and v ~= "" then
        return v
    end
    return nil
end

local DIAGONALS = { northeast = true, northwest = true, southeast = true, southwest = true }

local Sheet = InputContainer:extend{
    path = nil, -- ruta del .dnd (obligatorio)
    data = nil, -- tabla decodificada del JSON (obligatorio)
    readonly = false, -- true si el .dnd es de una versión futura: no se guarda
    page = nil, -- página inicial (por defecto, la última vista)
}

Sheet.PAGES = PAGES
require("dndsheet/ui/sheet_menus")(Sheet) -- menús y acciones (showIndex, showMenu, duplicate, act…)
require("dndsheet/ui/sheet_resume")(Sheet) -- volver a ponerse arriba al despertar (F-01)

function Sheet:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true -- pista para UIManager: tapa toda la pantalla
    self.cache = {}
    self.dirty = false
    self.sub = 1
    self.page = math.max(1, math.min(#PAGES, self.page or Settings.last_page(self.path) or 1))
    self.save_debounced = UIManager:debounce(SAVE_DELAY, false, function() self:flushSave() end)

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
        }
    end
    self:buildLayout()
    self:setPageWidget()
end

-- ── Marco ───────────────────────────────────────────────────────────────────

function Sheet:buildFooter(L, w)
    local side_w = math.floor(w * 0.25)
    local function arrow(label, cb)
        return Button:new{
            text = label, width = side_w, bordersize = 0, text_font_size = L.btn_font_size, text_font_face = "tfont",
            callback = cb, show_parent = self,
        }
    end
    self.page_label = TextWidget:new{ text = "", face = L.font_label, fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w - 2 * side_w }
    local prev, nxt = arrow("‹", function() self:goPrev() end), arrow("›", function() self:goNext() end)
    local center_h = prev:getSize().h
    local center = C.tappable{
        child = CenterContainer:new{ dimen = Geom:new{ w = w - 2 * side_w, h = center_h }, self.page_label },
        on_tap = function() self:showIndex() end,
        show_parent = self,
    }
    return C.Frame:new{
        bordersize = 0, padding = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", C.hline(L, w), HorizontalGroup:new{ align = "center", prev, center, nxt } },
    }
end

function Sheet:buildLayout()
    local w, h = self.dimen.w, self.dimen.h
    -- 1) medidas provisionales para construir el marco; 2) medidas definitivas con el alto real
    local L0 = Layout.compute(w, h, 0)
    local subtitle = text_or_nil(self.data.clase_nivel)
    if self.readonly then
        subtitle = (subtitle and (subtitle .. " · ") or "") .. T("sheet.readonly_tag")
    end
    self.title_bar = TitleBar:new{
        width = w,
        fullscreen = true,
        title = text_or_nil(self.data.nombre) or T("sheet.unnamed"),
        subtitle = subtitle,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self.footer = self:buildFooter(L0, w)
    local chrome_h = self.title_bar:getSize().h + self.footer:getSize().h
    self.L = Layout.compute(w, h, chrome_h)
    self.body = C.Frame:new{
        width = w,
        height = h - chrome_h,
        bordersize = 0,
        padding = self.L.margin,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{},
    }
    self[1] = C.Frame:new{
        width = w, height = h, background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0,
        VerticalGroup:new{ align = "left", self.title_bar, self.body, self.footer },
    }
end

-- ── Páginas ─────────────────────────────────────────────────────────────────

--- Devuelve (widget, total_subpáginas) de una página; la construye la primera vez y la cachea.
function Sheet:getPage(page, sub)
    local key = page .. ":" .. sub
    local hit = self.cache[key]
    if hit then return hit.widget, hit.total end
    local module = PAGES[page]
    local t0 = Perf.start()
    local ok, widget, total = pcall(module.build, {
        data = self.data, layout = self.L, sheet = self, subpage = sub,
    })
    if not ok then
        -- una página con error no debe tumbar la hoja
        logger.err("dndsheet: error al construir la página", module.id, widget)
        widget = TextWidget:new{ text = T("sheet.page_error"), face = self.L.font_text, max_width = self.L.body_w }
        total = 1
    end
    Perf.stop("build p" .. page, t0, key)
    if not module.no_cache then -- p7 reutiliza un único TextBoxWidget reposicionado por subpágina
        self.cache[key] = { widget = widget, total = total or 1 }
    end
    return widget, total or 1
end

local function region(widget, fallback)
    local d = widget and widget.dimen
    if d and d.w and d.w > 0 then
        return Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h }
    end
    return fallback
end

function Sheet:refreshRegion(name, widget, fallback)
    local r = region(widget, fallback)
    logger.dbg("dndsheet: setDirty", name, r and r.x, r and r.y, r and r.w, r and r.h)
    UIManager:setDirty(self, "ui", r)
end

--- Pone el widget de la página actual en el cuerpo y actualiza el pie (sin refrescar).
function Sheet:setPageWidget()
    local widget, total = self:getPage(self.page, self.sub)
    if self.sub > total then
        self.sub = total
    end
    self.body[1] = widget
    local label = string.format("%d / %d", self.page, #PAGES)
    if total > 1 then
        label = string.format("%s · %d/%d", label, self.sub, total)
    end
    self.page_label:setText(label .. " · " .. T(PAGES[self.page].title_key))
end

--- Avisa a la página visible que se va (cancela animaciones pendientes: F-06).
function Sheet:leavePage()
    local module = PAGES[self.page]
    if module and module.leave then module.leave() end
end

--- Muestra una página y refresca SOLO el cuerpo y el pie.
function Sheet:goTo(page, sub)
    local t0 = Perf.start()
    page = math.max(1, math.min(#PAGES, page))
    local changed = page ~= self.page
    self:leavePage()
    self.page, self.sub = page, sub or 1
    if sub == "last" then
        self.sub = select(2, self:getPage(page, 1))
    end
    self:setPageWidget()
    if changed then
        Settings.set_last_page(self.path, self.page)
    end
    self:refreshBodyAndFooter()
    Perf.stop("goTo", t0, page .. ":" .. self.sub)
end

function Sheet:refreshBodyAndFooter()
    local title_h = self.title_bar:getSize().h
    local footer_h = self.footer:getSize().h
    self:refreshRegion("cuerpo", self.body,
        Geom:new{ x = 0, y = title_h, w = self.dimen.w, h = self.dimen.h - title_h - footer_h })
    self:refreshRegion("pie", self.footer,
        Geom:new{ x = 0, y = self.dimen.h - footer_h, w = self.dimen.w, h = footer_h })
end

function Sheet:goNext()
    local total = select(2, self:getPage(self.page, self.sub))
    if self.sub < total then
        self:goTo(self.page, self.sub + 1)
    elseif self.page < #PAGES then
        self:goTo(self.page + 1, 1)
    else
        self:goTo(1, 1) -- vuelta circular (F-03)
    end
end

function Sheet:goPrev()
    if self.sub > 1 then
        self:goTo(self.page, self.sub - 1)
    elseif self.page > 1 then
        self:goTo(self.page - 1, "last")
    else
        self:goTo(#PAGES, "last") -- vuelta circular (F-03)
    end
end

-- ── Edición ─────────────────────────────────────────────────────────────────

--- Abre el editor de `kind` para `path` (ver ui/editors.lua).
function Sheet:edit(path, kind, opts)
    if self.readonly then
        return self:warnReadonly()
    end
    return Editors.edit(self, path, kind, opts)
end

function Sheet:warnReadonly()
    UIManager:show(InfoMessage:new{ text = T("msg.readonly") })
end

--- Aplica un cambio al modelo: marca como modificado, invalida la caché y reconstruye la página visible.
function Sheet:mutate(fn)
    if self.readonly then
        return self:warnReadonly()
    end
    local t0 = Perf.start()
    fn(self.data)
    self:markChanged()
    self:setPageWidget()
    self:refreshBodyAndFooter()
    Perf.stop("edit->refresh", t0)
end

function Sheet:setValue(path, value)
    self:mutate(function(data) Schema.set(data, path, value) end)
end

function Sheet:removeItem(list_path, index)
    self:mutate(function(data)
        local list = Schema.get(data, list_path)
        if list then table.remove(list, index) end
    end)
end

-- ── Guardado ────────────────────────────────────────────────────────────────

--- Hay cambios sin guardar: invalida la caché (los derivados cruzan páginas) y programa el guardado.
function Sheet:markChanged()
    self.dirty = true
    self.cache = {}
    self.save_debounced()
end

--- Guarda si hay cambios pendientes. Si falla, avisa y deja `dirty` para reintentar.
function Sheet:flushSave()
    if not self.dirty or not self.data or self.readonly then
        return true
    end
    if not self.backed_up then
        -- .bak solo en el primer guardado de cada apertura
        Store.backup(self.path)
        self.backed_up = true
    end
    local t0 = Perf.start()
    local ok, err = Store.save(self.path, self.data)
    Perf.stop("save", t0)
    if not ok then
        UIManager:show(InfoMessage:new{ text = err })
        return false
    end
    self.dirty = false
    Settings.flush()
    return true
end

-- ── Eventos ─────────────────────────────────────────────────────────────────

function Sheet:onShow()
    UIManager:setDirty(self, "ui")
end

function Sheet:onSwipe(_arg, ges_ev)
    local dir = ges_ev.direction
    if dir == "west" then
        self:goNext()
    elseif dir == "east" then
        self:goPrev()
    elseif dir == "south" then
        -- cerrar solo si el gesto empieza en la barra de título (como KeyValuePage)
        if ges_ev.pos and ges_ev.pos.y <= self.title_bar:getSize().h then
            return self:onClose()
        end
    elseif DIAGONALS[dir] then
        UIManager:setDirty(nil, "full") -- limpia fantasmas
    else
        return
    end
    return true
end

function Sheet:onSuspend()
    self:leavePage()
    self:flushSave()
    Settings.flush()
end

function Sheet:onFlushSettings()
    self:flushSave()
    Settings.flush()
end

function Sheet:onResize()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.cache = {}
    self:buildLayout()
    self:setPageWidget()
    UIManager:setDirty(self, "ui")
end

Sheet.onScreenResize = Sheet.onResize
Sheet.onSetRotationMode = Sheet.onResize

function Sheet:onClose()
    self:flushSave()
    Settings.flush()
    -- "flashui" al cerrar evita fantasmas de la e-ink sobre el explorador
    UIManager:close(self, "flashui")
    return true
end

function Sheet:onCloseWidget()
    self:flushSave()
    if self.reraising then
        return -- re-subida al despertar (F-01): la hoja sigue viva, se conservan data y caché
    end
    self:cancelReraise()
    require("dndsheet/compendium").release() -- F-08: libera los JSON del compendio (si se abrió)
    for _i, module in ipairs(PAGES) do
        if module.release then module.release() end
    end
    self.cache = nil
    self.data = nil
end

return Sheet
