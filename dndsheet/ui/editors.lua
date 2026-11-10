-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Editores: abren el widget nativo de KOReader adecuado para un tipo de campo y devuelven
el cambio a la hoja (`sheet:setValue`, `sheet:mutate`). Punto de entrada: `Editors.edit`.

Tipos: int, text, longtext, toggle, cycle, pip, override, record, hp.

@module dndsheet.ui.editors
--]]
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Rules = require("dndsheet/rules")
local Schema = require("dndsheet/schema")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local rapidjson = require("rapidjson")
local T = require("dndsheet/i18n").T

local Editors = {}

local function number_or(v, default)
    return type(v) == "number" and v or default
end

-- ── Sin diálogo ─────────────────────────────────────────────────────────────

local function toggle(sheet, path)
    sheet:setValue(path, Schema.get(sheet.data, path) ~= true)
end

local function cycle(sheet, path, opts)
    local max = opts.max or 2
    sheet:setValue(path, (number_or(Schema.get(sheet.data, path), 0) + 1) % (max + 1))
end

-- Tocar el pip i fija `usados = i` (o i-1 si ya era el último marcado)
local function pip(sheet, path, opts)
    local used = number_or(Schema.get(sheet.data, path), 0)
    local i = opts.index
    sheet:setValue(path, used == i and i - 1 or i)
end

-- ── Números ─────────────────────────────────────────────────────────────────

--- Pide un número con teclado (InputDialog numérico), lo acota a [min, max] y llama a `on_value(n)`.
-- Si el texto no es un número: aviso corto y el diálogo queda abierto (F-05).
-- @tparam table opts title, value (valor actual), min, max
function Editors.type_number(opts, on_value)
    local min, max = opts.min or 0, opts.max or 9999
    local dlg
    dlg = InputDialog:new{
        title = opts.title or "",
        input = tostring(opts.value or ""),
        input_hint = string.format("%d – %d", min, max),
        input_type = "number",
        buttons = {{
            { id = "cancel", text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
            {
                id = "ok",
                text = T("common.ok"),
                is_enter_default = true,
                callback = function()
                    local n = tonumber(dlg:getInputText())
                    if not n or n ~= n then
                        UIManager:show(InfoMessage:new{ text = T("msg.invalid_number"), timeout = 2 })
                        return
                    end
                    UIManager:close(dlg)
                    on_value(math.max(min, math.min(max, math.floor(n + 0.5))))
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

-- SpinWidget con el botón "Escribir…" (F-05). Tener `extra_text` u `option_text` evita que SimpleUI lo
-- reemplace por su diálogo con barra y deja el nativo, donde además se puede tocar el número para escribirlo.
-- `extra` ({text, callback}) es un botón propio del editor (p. ej. "Automático"): pasa a `extra_*` y
-- "Escribir…" a `option_*`; sin `extra`, "Escribir…" es el `extra_*`.
local function spin(sheet, opts, on_value, extra)
    local min, max = opts.min or 0, opts.max or 9999
    local function write(w)
        Editors.type_number({ title = opts.title, value = w.value, min = min, max = max }, on_value)
    end
    local widget = SpinWidget:new{
        title_text = opts.title or "",
        info_text = opts.info,
        value = opts.value,
        value_min = min,
        value_max = max,
        value_step = opts.step or 1,
        value_hold_step = opts.hold_step or 5,
        ok_text = T("common.ok"),
        cancel_text = T("common.cancel"),
        ok_always_enabled = true,
        extra_text = extra and extra.text or T("common.type"),
        extra_callback = extra and extra.callback or write,
        option_text = extra and T("common.type") or nil,
        option_callback = extra and write or nil,
        callback = function(w) on_value(w.value) end,
    }
    UIManager:show(widget)
    return widget
end

local function int(sheet, path, opts)
    return spin(sheet, {
        title = opts.title, info = opts.info, min = opts.min, max = opts.max, step = opts.step,
        hold_step = opts.hold_step, value = number_or(Schema.get(sheet.data, path), opts.min or 0),
    }, function(v) sheet:setValue(path, v) end)
end

-- Valor calculado con botón "Automático" que borra el ajuste manual (null)
local function override(sheet, path, opts)
    local manual = Schema.get(sheet.data, path)
    local current = number_or(manual, opts.auto_value or 0)
    local dlg
    dlg = spin(sheet, {
        title = opts.title, info = opts.info, min = opts.min or -20, max = opts.max or 99,
        value = current,
    }, function(v) sheet:setValue(path, v) end, {
        text = T("common.auto"),
        callback = function()
            sheet:setValue(path, rapidjson.null)
            if dlg then UIManager:close(dlg) end
        end,
    })
    return dlg
end

-- ── Texto ───────────────────────────────────────────────────────────────────

local function input(sheet, path, opts, multiline)
    local dlg
    dlg = InputDialog:new{
        title = opts.title or "",
        input = tostring(Schema.get(sheet.data, path) or ""),
        fullscreen = multiline or nil,
        allow_newline = multiline or nil,
        add_nav_bar = (multiline and opts.nav_bar) or nil,
        buttons = {{
            { id = "cancel", text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
            {
                id = "save",
                text = T("common.save"),
                is_enter_default = not multiline,
                callback = function()
                    local value = dlg:getInputText()
                    UIManager:close(dlg)
                    sheet:setValue(path, value)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

-- ── Registro (ataque, conjuro…) ─────────────────────────────────────────────

-- opts.fields = { {name = "nombre", hint = "Nombre"}, … }; opts.new = true para agregar a la lista `path`
local function record(sheet, path, opts)
    local record_data = opts.new and {} or (Schema.get(sheet.data, path) or {})
    local fields = {}
    for i, f in ipairs(opts.fields) do
        fields[i] = { text = tostring(record_data[f.name] or ""), hint = f.hint or f.name }
    end
    local dlg
    local buttons = {{
        { id = "cancel", text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
    }}
    if not opts.new then
        table.insert(buttons[1], {
            id = "delete",
            text = T("common.delete"),
            callback = function()
                UIManager:close(dlg)
                local list_path, idx = path:match("^(.*)%.(%d+)$")
                sheet:removeItem(list_path, tonumber(idx))
            end,
        })
    end
    table.insert(buttons[1], {
        id = "save",
        text = T("common.save"),
        callback = function()
            local values = dlg:getFields()
            UIManager:close(dlg)
            local result = {}
            for i, f in ipairs(opts.fields) do result[f.name] = values[i] end
            if opts.new then
                local list = Schema.get(sheet.data, path)
                sheet:setValue(path .. "." .. (#list + 1), result)
            else
                sheet:mutate(function(data)
                    for name, v in pairs(result) do Schema.set(data, path .. "." .. name, v) end
                end)
            end
        end,
    })
    dlg = MultiInputDialog:new{ title = opts.title or "", fields = fields, buttons = buttons }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

-- ── Puntos de golpe ─────────────────────────────────────────────────────────

local function hp(sheet)
    local data = sheet.data
    local dlg
    local function ask(title, on_value, start, min)
        UIManager:close(dlg)
        spin(sheet, { title = title, value = start, min = min or 0, max = 9999, hold_step = 5 }, on_value)
    end
    dlg = ButtonDialog:new{
        title = string.format("%d / %d", data.hp.actual, data.hp.maximo),
        buttons = {
            {
                { id = "damage", text = T("hp.damage"), callback = function()
                    ask(T("hp.damage_title"), function(n)
                        sheet:mutate(function(d) Rules.apply_damage(d, n) end)
                    end, 1, 0)
                end },
                { id = "heal", text = T("hp.heal"), callback = function()
                    ask(T("hp.heal_title"), function(n)
                        sheet:mutate(function(d) Rules.apply_heal(d, n) end)
                    end, 1, 0)
                end },
            },
            {
                { id = "set", text = T("hp.set"), callback = function()
                    ask(T("hp.set_title"), function(n) sheet:setValue("hp.actual", n) end, data.hp.actual)
                end },
                { id = "temp", text = T("hp.temp"), callback = function()
                    ask(T("hp.temp_title"), function(n) sheet:setValue("hp.temporal", n) end, data.hp.temporal)
                end },
            },
            {
                { id = "max", text = T("hp.max"), callback = function()
                    ask(T("hp.max_title"), function(n) sheet:setValue("hp.maximo", n) end, data.hp.maximo)
                end },
            },
        },
    }
    UIManager:show(dlg)
    return dlg
end

-- ── Conjuros ────────────────────────────────────────────────────────────────

-- Rota entre los valores de opts.values (puede incluir rapidjson.null): int → sab → car → ninguna
local function rotate(sheet, path, opts)
    local values = opts.values
    local current = Schema.get(sheet.data, path)
    local next_i = 1
    for i, v in ipairs(values) do
        if v == current then next_i = i % #values + 1 break end
    end
    sheet:setValue(path, values[next_i])
end

-- Lista de nombres, uno por línea (trucos): reemplaza la lista conservando los datos de los que siguen
local function namelist(sheet, path, opts)
    local list = Schema.get(sheet.data, path) or {}
    local names = {}
    for _i, item in ipairs(list) do names[#names + 1] = item.nombre end
    local dlg
    dlg = InputDialog:new{
        title = opts.title or "",
        description = T("hint.one_per_line"),
        input = table.concat(names, "\n"),
        fullscreen = true,
        allow_newline = true,
        buttons = {{
            { id = "cancel", text = T("common.cancel"), callback = function() UIManager:close(dlg) end },
            { id = "save", text = T("common.save"), callback = function()
                local text = dlg:getInputText()
                UIManager:close(dlg)
                sheet:mutate(function(data)
                    local old = {}
                    for _i, item in ipairs(Schema.get(data, path) or {}) do old[item.nombre] = item end
                    local new = {}
                    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                        line = line:match("^%s*(.-)%s*$")
                        if line ~= "" then new[#new + 1] = old[line] or { nombre = line } end
                    end
                    Schema.set(data, path, new)
                end)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
    return dlg
end

-- Mantener presionado un conjuro: Renombrar / Borrar (path = "conjuros.niveles.N.lista.i")
local function spell_menu(sheet, path)
    local dlg
    local spell = Schema.get(sheet.data, path) or {}
    local row = {}
    if type(spell.ref) == "string" then
        row[#row + 1] = { id = "view", text = T("spell.view_rule"), callback = function()
            UIManager:close(dlg)
            sheet:viewRule(spell.ref, spell.nombre)
        end }
    end
    local buttons = {}
    if #row > 0 then buttons[1] = row end
    buttons[#buttons + 1] = {
        { id = "rename", text = T("common.rename"), callback = function()
            UIManager:close(dlg)
            input(sheet, path .. ".nombre", { title = T("spell.name") }, false)
        end },
        { id = "delete", text = T("common.delete"), callback = function()
            UIManager:close(dlg)
            local list_path, idx = path:match("^(.*)%.(%d+)$")
            sheet:removeItem(list_path, tonumber(idx))
        end },
    }
    dlg = ButtonDialog:new{ title = spell.nombre or "", buttons = buttons }
    UIManager:show(dlg)
    return dlg
end

-- Mantener presionado un rasgo del compendio (rasgos_ref.i): Nota / Quitar
local function ref_menu(sheet, path)
    local item = Schema.get(sheet.data, path) or {}
    local dlg
    dlg = ButtonDialog:new{
        title = item.nombre or "",
        buttons = {{
            { id = "note", text = T("trait.ref_note"), callback = function()
                UIManager:close(dlg)
                input(sheet, path .. ".nota", { title = T("trait.ref_note_title", item.nombre or "") }, true)
            end },
            { id = "remove", text = T("trait.ref_remove"), callback = function()
                UIManager:close(dlg)
                local list_path, idx = path:match("^(.*)%.(%d+)$")
                sheet:removeItem(list_path, tonumber(idx))
            end },
        }},
    }
    UIManager:show(dlg)
    return dlg
end

-- "+ Agregar nivel": elige un nivel (1-9) que todavía no se muestra y le pone el total de ranuras
local function add_level(sheet)
    local levels = sheet.data.conjuros.niveles
    local buttons, row = {}, {}
    local dlg
    for n = 1, 9 do
        local lv = levels[tostring(n)]
        if lv and (lv.total or 0) == 0 and #lv.lista == 0 then
            row[#row + 1] = { id = "level" .. n, text = tostring(n), callback = function()
                UIManager:close(dlg)
                spin(sheet, { title = T("spell.slots_title", n), value = 1, min = 1, max = 20 },
                    function(total) sheet:setValue("conjuros.niveles." .. n .. ".total", total) end)
            end }
            if #row == 3 then buttons[#buttons + 1] = row row = {} end
        end
    end
    if #row > 0 then buttons[#buttons + 1] = row end
    if #buttons == 0 then
        UIManager:show(InfoMessage:new{ text = T("spell.all_levels") })
        return
    end
    dlg = ButtonDialog:new{ title = T("spell.add_level_title"), buttons = buttons }
    UIManager:show(dlg)
    return dlg
end

--- Confirmación simple (borrar, descansos).
function Editors.confirm(text, ok_text, on_ok)
    local box = ConfirmBox:new{ text = text, ok_text = ok_text, cancel_text = T("common.cancel"), ok_callback = on_ok }
    UIManager:show(box)
    return box
end

--- Descanso largo: confirma y restaura (rules.long_rest).
function Editors.long_rest(sheet)
    return Editors.confirm(
        T("rest.long_confirm"),
        T("rest.confirm_button"),
        function() sheet:mutate(Rules.long_rest) end)
end

--- Descanso corto: pregunta cuántos dados de golpe se gastan y los descuenta.
-- El jugador tira los dados y suma el HP a mano con "Curar".
function Editors.short_rest(sheet)
    local left = number_or(sheet.data.dados_golpe.restantes, 0)
    if left <= 0 then
        UIManager:show(InfoMessage:new{ text = T("rest.no_dice") })
        return
    end
    return spin(sheet, {
        title = T("rest.short"), info = T("rest.short_info"),
        value = 1, min = 0, max = left,
    }, function(n)
        sheet:mutate(function(d)
            d.dados_golpe.restantes = math.max(0, left - n)
            Rules.short_rest(d)
        end)
    end)
end

local HANDLERS = {
    int = int, text = function(s, p, o) return input(s, p, o, false) end,
    longtext = function(s, p, o) return input(s, p, o, true) end,
    toggle = toggle, cycle = cycle, pip = pip, override = override, record = record, hp = hp,
    rotate = rotate, namelist = namelist, add_level = add_level,
    spell_menu = function(s, p) return spell_menu(s, p) end,
    ref_menu = function(s, p) return ref_menu(s, p) end,
    -- diálogo de monedas (F-05); se carga al usarlo porque ui/coins requiere este módulo
    coins = function(s, _p, o) return require("dndsheet/ui/coins").open(s, o) end,
}

--- Abre el editor del tipo `kind` para la ruta `path` del modelo.
-- @tparam table sheet la hoja (expone .data, setValue, mutate, removeItem)
-- @string path ruta del modelo ("hp.actual", "ataques.2"…)
-- @string kind tipo de editor
-- @tparam table opts opciones del tipo (title, min, max, index, fields, auto_value…)
function Editors.edit(sheet, path, kind, opts)
    local handler = HANDLERS[kind]
    if not handler then
        error("dndsheet: tipo de editor desconocido: " .. tostring(kind))
    end
    return handler(sheet, path, opts or {})
end

return Editors
