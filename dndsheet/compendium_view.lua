-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Texto de las reglas del compendio (visor) y alta en la hoja (F-08). Módulo PURO: no usa widgets.

- `describe(compendium, hit)` arma título, línea de datos y cuerpo de una entrada o de un rasgo.
- `add_feature`, `add_spell`, `add_attack` modifican los datos del personaje (se llaman dentro de `sheet:mutate`).

@module dndsheet.compendium_view
--]]
local Rules = require("dndsheet/rules")
local T = require("dndsheet/i18n").T

local View = {}

local function str(v)
    return type(v) == "string" and v ~= "" and v or nil
end

local function join(parts, sep)
    local out = {}
    for _i, p in ipairs(parts) do
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, sep or " · ")
end

-- origen: "SRD 5.2.1 (CC-BY-4.0)" o "(propia)" (y si reemplaza una regla del SRD, se aclara)
local function origin(entry)
    if entry.source == "custom" then
        return entry.override and T("compendium.custom_override") or T("compendium.custom")
    end
    return T("compendium.source_srd")
end
View.origin = origin

local function class_name(compendium, class_id)
    local hit = class_id and compendium.index[class_id]
    return hit and hit.entry.name or str(class_id) or ""
end

-- Une líneas con "\n": nil/false se omiten y "" queda como línea en blanco (sin blancos en los extremos).
local function lines(...)
    local out = {}
    for i = 1, select("#", ...) do
        local l = select(i, ...)
        if l then out[#out + 1] = l end
    end
    local text = table.concat(out, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
    return text
end

-- ── Descripción ─────────────────────────────────────────────────────────────

local function describe_spell(e)
    local head = e.level == 0 and T("compendium.cantrip") or T("spell.level", e.level)
    local info = join({ head, e.school, e.casting_time, e.range })
    local body = lines(
        T("compendium.components", e.components or ""),
        T("compendium.duration", e.duration or ""),
        #(e.classes or {}) > 0 and T("compendium.classes_list", table.concat(e.classes, ", ")) or nil,
        "",
        e.text,
        str(e.higher_levels) and "" or nil,
        str(e.higher_levels))
    return e.name, info, body
end

local function describe_weapon(e)
    local cat = e.category == "simple" and T("weapon.simple_one") or T("weapon.martial_one")
    local kind = e.kind == "ranged" and T("weapon.ranged") or T("weapon.melee")
    local dmg = join({ str(e.damage), str(e.damage_type) }, " ")
    local info = join({ cat, kind, dmg })
    local props = str(e.properties_text) or table.concat(e.properties or {}, ", ")
    local body = lines(
        props ~= "" and T("weapon.properties", props) or nil,
        str(e.versatile) and T("weapon.versatile", e.versatile) or nil,
        str(e.range) and T("weapon.range", e.range) or nil,
        str(e.mastery) and T("weapon.mastery", e.mastery) or nil,
        str(e.weight) and T("weapon.weight", e.weight) or nil,
        str(e.cost) and T("weapon.cost", e.cost) or nil)
    return e.name, info, body
end

local function describe_feat(e)
    local cat = str(e.category) and T("feat." .. e.category) or nil
    local info = join({ cat, str(e.prerequisite) and T("compendium.prerequisite", e.prerequisite) or nil })
    return e.name, info, e.text
end

local function describe_class(compendium, e)
    local info = join({ e.name, T("compendium.overview") })
    local body = lines(
        e.hit_die and T("compendium.hit_die", e.hit_die) or nil,
        str(e.primary_ability) and T("compendium.primary", e.primary_ability) or nil,
        #(e.saving_throws or {}) > 0 and T("compendium.saves", table.concat(e.saving_throws, ", ")) or nil,
        #(e.subclass_ids or {}) > 0 and T("compendium.subclasses_list", (function()
            local names = {}
            for _i, sid in ipairs(e.subclass_ids) do
                local hit = compendium.index[sid]
                names[#names + 1] = hit and hit.entry.name or sid
            end
            return table.concat(names, ", ")
        end)()) or nil)
    return e.name, info, body
end

--- Título, línea de datos y cuerpo del visor para un resultado de `Compendium:resolve` / de una lista.
-- @tparam table compendium instancia (para nombres de clase)
-- @tparam table hit { kind, entry, item? [, overview=true] }
-- @treturn string título
-- @treturn string línea de datos (incluye el origen)
-- @treturn string cuerpo
function View.describe(compendium, hit)
    local e, it, kind = hit.entry, hit.item, hit.kind
    local title, info, body
    if it then
        if kind == "classes" then
            info = join({ e.name .. (it.level and (" " .. it.level) or ""), str(it.group) })
        elseif kind == "subclasses" then
            info = join({ e.name .. (it.level and (" " .. it.level) or ""), class_name(compendium, e.class_id) })
        else
            info = e.name
        end
        title, body = it.name, it.text
    elseif kind == "spells" then
        title, info, body = describe_spell(e)
    elseif kind == "weapons" then
        title, info, body = describe_weapon(e)
    elseif kind == "feats" then
        title, info, body = describe_feat(e)
    elseif kind == "classes" then
        title, info, body = describe_class(compendium, e)
    else
        title, info, body = e.name, "", ""
    end
    local src = origin(e)
    return title, join({ info, src }), body
end

-- ── Alta en la hoja (se llaman dentro de `sheet:mutate`) ────────────────────

--- Rasgo / dote / rasgo de especie → `rasgos_ref`. Devuelve "added" o "exists".
function View.add_feature(data, ref, name)
    if type(data.rasgos_ref) ~= "table" then data.rasgos_ref = {} end
    for _i, r in ipairs(data.rasgos_ref) do
        if r.ref == ref then return "exists" end
    end
    data.rasgos_ref[#data.rasgos_ref + 1] = { ref = ref, nombre = name, nota = "" }
    return "added"
end

--- Conjuro → lista de su nivel. Devuelve "added" o "exists" y el nivel.
function View.add_spell(data, spell)
    local lv = data.conjuros.niveles[tostring(spell.level)]
    if type(lv) ~= "table" then return "exists", spell.level end
    for _i, s in ipairs(lv.lista) do
        if s.ref == spell.id then return "exists", spell.level end
    end
    local item = { nombre = spell.name, ref = spell.id }
    if spell.level > 0 then item.preparado = false end
    lv.lista[#lv.lista + 1] = item
    return "added", spell.level
end

--- Arma → ataque con valores calculados (se pueden editar después como cualquier ataque).
function View.add_attack(data, weapon, proficient)
    local bonus, dano = Rules.weapon_attack(data, weapon, proficient)
    data.ataques[#data.ataques + 1] = { nombre = weapon.name, bonus = bonus, dano = dano, ref = weapon.id }
    return bonus, dano
end

return View
