-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Vectores de reglas compartidos con la web (format/vectors/*.json): rules.lua tiene que dar lo mismo que ellos.
local Rules = require("dndsheet/rules")
local Schema = require("dndsheet/schema")
local rapidjson = require("rapidjson")

local NULL = rapidjson.null

-- el repo de desarrollo tiene format/ junto a dndsheet.koplugin/; el público lo tiene en la raíz del plugin
local function load(name)
    for _i, dir in ipairs({ "format/vectors/", "../format/vectors/" }) do
        local f = io.open(dir .. name, "rb")
        if f then
            local doc = assert(rapidjson.decode(f:read("*a")))
            f:close()
            return doc
        end
    end
    error("no encuentro format/vectors/" .. name)
end

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local function nul(v) if v == NULL then return nil end return v end

local ABIL = { "fue", "des", "con", "int", "sab", "car" }
local T = {}

function T.modificadores_y_competencia()
    local doc = load("rules-basic.json")
    for _i, m in ipairs(doc.mods) do eq(Rules.mod(m.score), m.mod, "mod(" .. m.score .. ")") end
end

function T.derivados_de_cada_caso()
    local doc = load("rules-basic.json")
    assert(#doc.cases >= 15, "faltan casos")
    for _i, c in ipairs(doc.cases) do
        local d = Schema.normalize(c.input)
        local e = c.expect
        local ctx = c.name .. ": "
        eq(Rules.prof(d), e.prof, ctx .. "prof")
        for _j, a in ipairs(ABIL) do
            eq(Rules.mod(d.atributos[a]), e.mod[a], ctx .. "mod " .. a)
            eq(Rules.save(d, a), e.save[a], ctx .. "save " .. a)
        end
        local n = 0
        for skill, v in pairs(e.skill) do
            eq(Rules.skill(d, skill), v, ctx .. "skill " .. skill)
            n = n + 1
        end
        eq(n, 18, ctx .. "18 habilidades")
        eq(Rules.initiative(d), e.initiative, ctx .. "initiative")
        eq(Rules.passive(d), e.passive, ctx .. "passive")
        eq(Rules.spell_dc(d), nul(e.spell_dc), ctx .. "spell_dc")
        eq(Rules.spell_atk(d), nul(e.spell_atk), ctx .. "spell_atk")
    end
end

function T.ataques_con_arma()
    local doc = load("weapon-attacks.json")
    for _i, c in ipairs(doc.cases) do
        local d = Schema.normalize(c.input)
        local bonus, dano, ab = Rules.weapon_attack(d, c.weapon, c.proficient)
        eq(bonus, c.expect.bonus, c.name .. ": bonus")
        eq(dano, c.expect.damage, c.name .. ": daño")
        eq(ab, c.expect.ability, c.name .. ": atributo")
    end
end

function T.hp_y_descansos()
    local doc = load("hp-and-rests.json")
    for _i, c in ipairs(doc.cases) do
        local d = Schema.normalize(c.input)
        for _j, op in ipairs(c.ops) do
            if op[1] == "damage" then Rules.apply_damage(d, op[2])
            elseif op[1] == "heal" then Rules.apply_heal(d, op[2])
            elseif op[1] == "long_rest" then Rules.long_rest(d)
            else error("operación desconocida " .. tostring(op[1])) end
        end
        local e = c.expect
        for k, v in pairs(e.hp or {}) do eq(d.hp[k], v, c.name .. ": hp." .. k) end
        for k, v in pairs(e.muerte or {}) do eq(d.muerte[k], v, c.name .. ": muerte." .. k) end
        for k, v in pairs(e.dados_golpe or {}) do eq(d.dados_golpe[k], v, c.name .. ": dados_golpe." .. k) end
        for lv, v in pairs(e.slots_usados or {}) do eq(d.conjuros.niveles[lv].usados, v, c.name .. ": usados " .. lv) end
    end
    for _i, pair in ipairs(doc.hit_dice_count) do
        eq(Rules.hit_dice_count(nul(pair[1])), nul(pair[2]), "hit_dice_count(" .. tostring(pair[1]) .. ")")
    end
end

-- igualdad profunda (tablas vacías = listas vacías; null = null)
local function same(a, b, path)
    if type(a) ~= type(b) then error(path .. ": tipos distintos " .. type(a) .. " / " .. type(b), 0) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b), 0) end
        return
    end
    if a == NULL or b == NULL then
        if a ~= b then error(path .. ": null", 0) end
        return
    end
    for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. ": falta", 0) end end
end

function T.normalize_coincide_con_los_vectores()
    local doc = load("normalize.json")
    assert(#doc.cases >= 15, "faltan casos")
    for _i, c in ipairs(doc.cases) do
        local d = Schema.normalize(Schema.migrate(c.input))
        Schema.fix_arrays(d)
        same(d, c.expect, c.name)
    end
end

return T
