-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Claves y estructura de las tablas fijas (atributos, habilidades, páginas).
El ORDEN de cada tabla es el orden en pantalla. Los nombres visibles salen de `i18n`
(`ability.<clave>`, `ability.<clave>.short`, `skill.<clave>`, `page.<id>`): ver dndsheet/lang/.

@module dndsheet.labels
--]]
local T = require("dndsheet/i18n").T

local Labels = {}

-- Atributos (claves del .dnd)
Labels.ABILITIES = {
    { key = "fue" }, { key = "des" }, { key = "con" }, { key = "int" }, { key = "sab" }, { key = "car" },
}

-- Habilidades: clave y atributo asociado (orden de la hoja oficial)
Labels.SKILLS = {
    { key = "acrobacias",     ability = "des" },
    { key = "trato_animales", ability = "sab" },
    { key = "arcanos",        ability = "int" },
    { key = "atletismo",      ability = "fue" },
    { key = "engano",         ability = "car" },
    { key = "historia",       ability = "int" },
    { key = "perspicacia",    ability = "sab" },
    { key = "intimidacion",   ability = "car" },
    { key = "investigacion",  ability = "int" },
    { key = "medicina",       ability = "sab" },
    { key = "naturaleza",     ability = "int" },
    { key = "percepcion",     ability = "sab" },
    { key = "interpretacion", ability = "car" },
    { key = "persuasion",     ability = "car" },
    { key = "religion",       ability = "int" },
    { key = "juego_manos",    ability = "des" },
    { key = "sigilo",         ability = "des" },
    { key = "supervivencia",  ability = "sab" },
}

-- Páginas de la hoja; el título es T("page.<id>")
Labels.PAGES = {
    { id = "combat" }, { id = "abilities" }, { id = "attacks" }, { id = "traits" },
    { id = "spells" }, { id = "background" }, { id = "notes" },
}

-- Atributos de lanzamiento de conjuros, en el orden en que rota el toque
Labels.SPELL_ABILITIES = { "int", "sab", "car" }

-- Textos visibles (en el idioma activo)
function Labels.ability_name(key) return T("ability." .. key) end
function Labels.ability_abbr(key) return T("ability." .. key .. ".short") end
function Labels.skill_name(key) return T("skill." .. key) end
function Labels.page_title(id) return T("page." .. id) end

-- Búsquedas por clave (se calculan una vez)
Labels.SKILL_AB = {}
for _i, s in ipairs(Labels.SKILLS) do
    Labels.SKILL_AB[s.key] = s.ability
end
Labels.ABILITY_BY_KEY = {}
for _i, a in ipairs(Labels.ABILITIES) do
    Labels.ABILITY_BY_KEY[a.key] = a
end

return Labels
