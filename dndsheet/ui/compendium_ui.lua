-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Compendio en la hoja (F-08): menús paginados (`Menu`, una sola ventana con pila de listas), búsqueda por nombre
(ícono 🔍 del título), visor de reglas (`TextViewer`) y "Agregar a mi hoja".

Navegación: Compendio → Clases → <clase> → Nivel → rasgo · Subclases → clase → subclase → rasgos ·
Especies → especie → rasgos · Dotes → categoría · Conjuros → clase → nivel · Armas → simples/marciales.
El ✕ del título vuelve a la lista anterior; en la primera cierra todo.

@module dndsheet.ui.compendium_ui
--]]
local ButtonDialog = require("ui/widget/buttondialog")
local Compendium = require("dndsheet/compendium")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local Rules = require("dndsheet/rules")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local View = require("dndsheet/compendium_view")
local T = require("dndsheet/i18n").T

local UI = {}

local FEAT_CATEGORIES = { "origin", "general", "fighting_style", "epic_boon" }

-- ── Instancia ───────────────────────────────────────────────────────────────

--- El compendio compartido, con la carpeta de entradas propias (`<carpeta de personajes>/compendio`).
function UI.compendium()
    local Characters = require("dndsheet/characters")
    return Compendium.get({
        lang = require("dndsheet/i18n").current(),
        custom_dir = Characters.folder() .. "/compendio",
    })
end

local function notify(text)
    UIManager:show(Notification:new{ text = text, source = Notification.SOURCE_ALWAYS_SHOW })
end

-- ── Visor ───────────────────────────────────────────────────────────────────

--- Muestra una regla. `hit` = { kind, entry, item? }. Con `sheet` y algo agregable, ofrece "Agregar a mi hoja".
function UI.view(sheet, hit, compendium, no_add)
    compendium = compendium or UI.compendium()
    local title, info, body = View.describe(compendium, hit)
    local viewer
    local row = {}
    local addable = not no_add and sheet and not sheet.readonly
        and (hit.item or hit.kind == "feats" or hit.kind == "spells" or hit.kind == "weapons")
    if addable then
        row[#row + 1] = { text = T("compendium.add"), callback = function()
            UI.add(sheet, hit, viewer)
        end }
    end
    row[#row + 1] = { text = T("common.close"), callback = function() UIManager:close(viewer) end }
    viewer = TextViewer:new{
        title = title,
        text = (info ~= "" and (info .. "\n\n") or "") .. (body or ""),
        buttons_table = { row },
        add_default_buttons = false,
    }
    UIManager:show(viewer)
    return viewer
end

--- Muestra la regla con id `ref` (la agregada a la hoja); si ya no existe, avisa.
function UI.view_ref(sheet, ref, name)
    local comp = UI.compendium()
    local hit = comp:resolve(ref)
    if not hit then
        UIManager:show(InfoMessage:new{ text = (name and name ~= "" and (name .. "\n\n") or "") .. T("compendium.no_rule") })
        return
    end
    return UI.view(sheet, hit, comp, true)
end

-- ── Agregar a la hoja ───────────────────────────────────────────────────────

local function weapon_dialog(sheet, weapon, proficient, previous)
    if previous then UIManager:close(previous) end
    local bonus, dano = Rules.weapon_attack(sheet.data, weapon, proficient)
    local dlg
    dlg = ButtonDialog:new{
        title = weapon.name .. "\n" .. T("weapon.add_text", bonus, dano),
        buttons = {
            {{ text = T("weapon.proficient", proficient and T("common.yes") or T("common.no")), callback = function()
                weapon_dialog(sheet, weapon, not proficient, dlg)
            end }},
            {
                { text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
                { text = T("weapon.add_button"), callback = function()
                    UIManager:close(dlg)
                    sheet:mutate(function(data) View.add_attack(data, weapon, proficient) end)
                    notify(T("compendium.added"))
                end },
            },
        },
    }
    UIManager:show(dlg)
    return dlg
end

--- "Agregar a mi hoja" para el resultado `hit`; `viewer` (opcional) se cierra al agregar.
function UI.add(sheet, hit, viewer)
    if sheet.readonly then return sheet:warnReadonly() end
    local e, result = hit.entry, nil
    if hit.kind == "weapons" then
        if viewer then UIManager:close(viewer) end
        return weapon_dialog(sheet, e, true)
    elseif hit.kind == "spells" then
        sheet:mutate(function(data) result = View.add_spell(data, e) end)
    else
        local ref = hit.item and hit.item.id or e.id
        local name = hit.item and hit.item.name or e.name
        sheet:mutate(function(data) result = View.add_feature(data, ref, name) end)
    end
    if viewer then UIManager:close(viewer) end
    notify(result == "added" and T("compendium.added") or T("compendium.exists"))
end

-- ── Menús ───────────────────────────────────────────────────────────────────

-- Empuja una lista nueva (el ✕ del título vuelve a la anterior).
local function push(menu, title, items, source)
    menu.item_table.title = menu.title
    table.insert(menu.item_stack_dnd, menu.dnd_source)
    table.insert(menu.item_table_stack, menu.item_table)
    menu.dnd_source = source
    menu:switchItemTable(title, items)
end

local function empty_items()
    return {{ text = T("compendium.empty"), select_enabled = false }}
end

local function names_of(list, fn)
    local items = {}
    for _i, e in ipairs(list) do items[#items + 1] = fn(e) end
    return #items > 0 and items or empty_items()
end

local function label(e)
    return e.source == "custom" and (e.name .. " " .. T("compendium.custom")) or e.name
end

-- Cada constructor devuelve la lista de ítems; `ctx` = { menu, sheet, comp }.
local build = {}

local function open_hit(ctx, hit)
    UI.view(ctx.sheet, hit, ctx.comp)
end

-- Rasgos de una entrada (clase por nivel, subclase, especie)
local function feature_items(ctx, kind, e, list, level_filter)
    local items = {}
    for _i, f in ipairs(list) do
        if not level_filter or f.level == level_filter then
            items[#items + 1] = {
                text = f.name,
                mandatory = f.level and tostring(f.level) or nil,
                callback = function() open_hit(ctx, { kind = kind, entry = e, item = f }) end,
            }
        end
    end
    return #items > 0 and items or empty_items()
end

function build.class(ctx, e)
    local items = {{
        text = T("compendium.overview"),
        callback = function() open_hit(ctx, { kind = "classes", entry = e }) end,
    }}
    local counts, max = {}, 0
    for _i, f in ipairs(e.features or {}) do
        local lv = f.level or 0
        counts[lv] = (counts[lv] or 0) + 1
        if lv > max then max = lv end
    end
    for lv = 0, max do
        if counts[lv] then
            items[#items + 1] = {
                text = T("spell.level", lv), mandatory = tostring(counts[lv]),
                callback = function()
                    push(ctx.menu, e.name .. " · " .. T("spell.level", lv), feature_items(ctx, "classes", e, e.features, lv))
                end,
            }
        end
    end
    return items
end

local function class_items(ctx, on_pick)
    return names_of(ctx.comp:entries("classes"), function(e)
        return { text = label(e), callback = function() on_pick(e) end }
    end)
end

local function subclass_items(ctx, list)
    return names_of(list, function(e)
        return { text = label(e), callback = function()
            push(ctx.menu, e.name, feature_items(ctx, "subclasses", e, e.features or {}))
        end }
    end)
end

local function species_items(ctx)
    return names_of(ctx.comp:entries("species"), function(e)
        return { text = label(e), callback = function()
            push(ctx.menu, e.name, feature_items(ctx, "species", e, e.traits or {}))
        end }
    end)
end

local function spell_items(ctx, list)
    return names_of(list, function(e)
        return {
            text = label(e), mandatory = e.level == 0 and "0" or tostring(e.level),
            callback = function() open_hit(ctx, { kind = "spells", entry = e }) end,
        }
    end)
end

local function by_level(list, level)
    local out = {}
    for _i, e in ipairs(list) do
        if level == nil or e.level == level then out[#out + 1] = e end
    end
    return out
end

local function by_class(list, class_name)
    local out = {}
    for _i, e in ipairs(list) do
        if not class_name then out[#out + 1] = e else
            for _j, c in ipairs(e.classes or {}) do
                if c == class_name then out[#out + 1] = e break end
            end
        end
    end
    return out
end

-- Conjuros: filtro por clase → nivel → lista. `level` (opcional) salta directo a ese nivel.
local function open_spells(ctx, class_name, level)
    local pool = by_class(ctx.comp:entries("spells"), class_name)
    local function levels_menu()
        local items = {{
            text = T("compendium.all"), mandatory = tostring(#pool),
            callback = function()
                push(ctx.menu, T("compendium.spells"), spell_items(ctx, pool), { kind = "spells", list = pool, build = spell_items })
            end,
        }}
        for lv = 0, 9 do
            local sub = by_level(pool, lv)
            if #sub > 0 then
                items[#items + 1] = {
                    text = lv == 0 and T("compendium.cantrips") or T("spell.level", lv), mandatory = tostring(#sub),
                    callback = function()
                        push(ctx.menu, lv == 0 and T("compendium.cantrips") or T("spell.level", lv),
                            spell_items(ctx, sub), { kind = "spells", list = sub, build = spell_items })
                    end,
                }
            end
        end
        return items
    end
    if level then
        local sub = by_level(pool, level)
        push(ctx.menu, level == 0 and T("compendium.cantrips") or T("spell.level", level),
            spell_items(ctx, sub), { kind = "spells", list = sub, build = spell_items })
    else
        push(ctx.menu, T("compendium.spells"), levels_menu())
    end
end

local function weapon_items(ctx, list)
    return names_of(list, function(e)
        return {
            text = label(e), mandatory = (e.damage or "") .. " " .. (e.damage_type or ""),
            callback = function() open_hit(ctx, { kind = "weapons", entry = e }) end,
        }
    end)
end

local function feat_items(ctx, list)
    return names_of(list, function(e)
        return { text = label(e), callback = function() open_hit(ctx, { kind = "feats", entry = e }) end }
    end)
end

-- ── Búsqueda ────────────────────────────────────────────────────────────────

local function search_all(ctx, query)
    local found = {}
    local kinds = { "classes", "subclasses", "species", "feats", "spells", "weapons" }
    for _i, kind in ipairs(kinds) do
        for _j, e in ipairs(ctx.comp:search(kind, query)) do
            local hit = { kind = kind, entry = e }
            local text = e.name
            if kind == "spells" then text = text .. "  (" .. (e.level == 0 and T("compendium.cantrip") or T("spell.level", e.level)) .. ")" end
            found[#found + 1] = {
                text = text,
                mandatory = T("compendium." .. kind),
                callback = function()
                    if kind == "classes" then
                        push(ctx.menu, e.name, build.class(ctx, e))
                    elseif kind == "subclasses" then
                        push(ctx.menu, e.name, feature_items(ctx, "subclasses", e, e.features or {}))
                    elseif kind == "species" then
                        push(ctx.menu, e.name, feature_items(ctx, "species", e, e.traits or {}))
                    else
                        open_hit(ctx, hit)
                    end
                end,
            }
        end
    end
    if #found == 0 then
        UIManager:show(InfoMessage:new{ text = T("compendium.search_none", query), timeout = 3 })
        return
    end
    push(ctx.menu, T("compendium.search_results", query), found)
end

local function search_in_list(ctx, query, source)
    local list = {}
    for _i, e in ipairs(source.list) do
        if Compendium.matches(e.name, query) then list[#list + 1] = e end
    end
    if #list == 0 then
        UIManager:show(InfoMessage:new{ text = T("compendium.search_none", query), timeout = 3 })
        return
    end
    push(ctx.menu, T("compendium.search_results", query), source.build(ctx, list), source)
end

local function ask_search(ctx)
    local dlg
    dlg = InputDialog:new{
        title = T("compendium.search_title"),
        input_hint = T("compendium.search_hint"),
        buttons = {{
            { text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
            { text = T("compendium.search"):gsub("…", ""), is_enter_default = true, callback = function()
                local q = dlg:getInputText()
                UIManager:close(dlg)
                if q and q:match("%S") then
                    local source = ctx.menu.dnd_source
                    if source then search_in_list(ctx, q, source) else search_all(ctx, q) end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

-- ── "Acerca del compendio" ──────────────────────────────────────────────────

local function coverage_text()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = src:match("^(.*)/dndsheet/ui/compendium_ui%.lua$") or "."
    local f = io.open(dir .. "/COBERTURA.md", "rb")
    if not f then return T("compendium.coverage_missing") end
    local s = f:read("*a")
    f:close()
    return s
end

function UI.about(comp)
    local a = comp:about()
    local m = a.meta
    local c = m.counts or {}
    local parts = {
        T("compendium.about_source", m.source or "SRD 5.2.1"),
        T("compendium.about_version", m.version or "5.2.1", a.lang),
        T("compendium.about_license", m.license or "CC-BY-4.0"),
        T("compendium.about_counts", c.classes or 0, c.subclasses or 0, c.species or 0, c.feats or 0, c.spells or 0, c.weapons or 0),
        "",
        T("compendium.about_custom", a.custom_entries, a.custom_files),
    }
    if a.custom_errors > 0 then parts[#parts + 1] = T("compendium.about_custom_errors", a.custom_errors) end
    if a.custom_dir then parts[#parts + 1] = T("compendium.about_folder", a.custom_dir) end
    parts[#parts + 1] = ""
    parts[#parts + 1] = m.attribution or ""
    local viewer
    viewer = TextViewer:new{
        title = T("compendium.about"),
        text = table.concat(parts, "\n"),
        buttons_table = {{
            { text = T("compendium.coverage"), callback = function()
                UIManager:show(TextViewer:new{ title = T("compendium.coverage"), text = coverage_text() })
            end },
            { text = T("common.close"), callback = function() UIManager:close(viewer) end },
        }},
        add_default_buttons = false,
    }
    UIManager:show(viewer)
    return viewer
end

-- ── Entrada ─────────────────────────────────────────────────────────────────

--- Abre el compendio. `opts.start` salta a una lista: "spells" (con `opts.level`), "weapons", "features".
-- @treturn table el `Menu`
function UI.open(sheet, opts)
    opts = opts or {}
    local comp = UI.compendium()
    local menu
    local ctx = { sheet = sheet, comp = comp }
    local function root_items()
        local function section(key, fn)
            return { text = T("compendium." .. key), callback = fn }
        end
        return {
            section("classes", function()
                push(menu, T("compendium.classes"), class_items(ctx, function(e) push(menu, e.name, build.class(ctx, e)) end))
            end),
            section("subclasses", function()
                push(menu, T("compendium.subclasses"), class_items(ctx, function(cls)
                    local subs = {}
                    for _i, s in ipairs(comp:entries("subclasses")) do
                        if s.class_id == cls.id then subs[#subs + 1] = s end
                    end
                    push(menu, cls.name, subclass_items(ctx, subs))
                end))
            end),
            section("species", function() push(menu, T("compendium.species"), species_items(ctx)) end),
            section("feats", function()
                local items = {}
                for _i, cat in ipairs(FEAT_CATEGORIES) do
                    local sub = {}
                    for _j, f in ipairs(comp:entries("feats")) do
                        if f.category == cat then sub[#sub + 1] = f end
                    end
                    if #sub > 0 then
                        items[#items + 1] = { text = T("featcat." .. cat), mandatory = tostring(#sub), callback = function()
                            push(menu, T("featcat." .. cat), feat_items(ctx, sub), { kind = "feats", list = sub, build = feat_items })
                        end }
                    end
                end
                push(menu, T("compendium.feats"), items)
            end),
            section("spells", function()
                push(menu, T("compendium.spells"), (function()
                    local items = {{ text = T("compendium.all"), callback = function() open_spells(ctx, nil) end }}
                    for _i, c in ipairs(comp:entries("classes")) do
                        local has = #by_class(comp:entries("spells"), c.name) > 0
                        if has then
                            items[#items + 1] = { text = c.name, callback = function() open_spells(ctx, c.name) end }
                        end
                    end
                    return items
                end)())
            end),
            section("weapons", function()
                local items = {}
                for _i, cat in ipairs({ "simple", "martial" }) do
                    local sub = {}
                    for _j, w in ipairs(comp:entries("weapons")) do
                        if w.category == cat then sub[#sub + 1] = w end
                    end
                    items[#items + 1] = { text = T("weapon." .. cat), mandatory = tostring(#sub), callback = function()
                        push(menu, T("weapon." .. cat), weapon_items(ctx, sub), { kind = "weapons", list = sub, build = weapon_items })
                    end }
                end
                push(menu, T("compendium.weapons"), items)
            end),
            { text = T("compendium.search"), callback = function() ask_search(ctx) end },
            { text = T("compendium.about"), callback = function() UI.about(comp) end },
        }
    end
    menu = Menu:new{
        title = T("compendium.title"),
        item_table = root_items(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_left_icon = "appbar.search",
        onLeftButtonTap = function() ask_search(ctx) end,
        close_callback = function() end, -- (el menú se cierra con UIManager:close en onCloseAllMenus)
    }
    menu.item_stack_dnd = {}
    menu.dnd_source = nil
    ctx.menu = menu
    -- ✕ del título: vuelve a la lista anterior (y restaura el alcance de la búsqueda)
    local base_close = menu.onClose
    menu.onClose = function(self)
        if #self.item_table_stack > 0 then self.dnd_source = table.remove(self.item_stack_dnd) end
        return base_close(self)
    end
    UIManager:show(menu)
    -- atajos desde las páginas de la hoja
    if opts.start == "spells" then
        open_spells(ctx, nil, opts.level)
    elseif opts.start == "weapons" then
        local sub = {}
        for _i, w in ipairs(comp:entries("weapons")) do sub[#sub + 1] = w end
        push(menu, T("compendium.weapons"), weapon_items(ctx, sub), { kind = "weapons", list = sub, build = weapon_items })
    end
    return menu
end

return UI
