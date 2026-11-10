-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Cálculos de D&D 5e. Módulo PURO: no toca la interfaz ni el disco.

@module dndsheet.rules
--]]
local Labels = require("dndsheet/labels")

local Rules = {}

local function clamp(n, lo, hi)
    return math.max(lo, math.min(hi, n))
end

local function num(v)
    return type(v) == "number" and v or nil
end

local function ability_score(data, ab)
    return num(data.atributos and data.atributos[ab]) or 10
end

--- Modificador de un atributo.
function Rules.mod(score)
    return math.floor((score - 10) / 2)
end

local function ability_mod(data, ab)
    return Rules.mod(ability_score(data, ab))
end

--- Bonificador de competencia (ajuste manual o según el nivel total).
function Rules.prof(data)
    local manual = num(data.ajustes and data.ajustes.competencia)
    if manual then return manual end
    local level = clamp(math.floor(num(data.nivel) or 1), 1, 20)
    return 2 + math.floor((level - 1) / 4)
end

--- Salvación de un atributo.
function Rules.save(data, ab)
    local proficient = data.salvaciones and data.salvaciones[ab] == true
    return ability_mod(data, ab) + (proficient and Rules.prof(data) or 0)
end

--- Habilidad: 0 = sin competencia, 1 = competente, 2 = pericia.
function Rules.skill(data, key)
    local ab = Labels.SKILL_AB[key]
    if not ab then return nil end
    local rank = clamp(num(data.habilidades and data.habilidades[key]) or 0, 0, 2)
    return ability_mod(data, ab) + Rules.prof(data) * rank
end

function Rules.initiative(data)
    return num(data.ajustes and data.ajustes.iniciativa) or ability_mod(data, "des")
end

function Rules.passive(data)
    return num(data.ajustes and data.ajustes.percepcion_pasiva) or (10 + Rules.skill(data, "percepcion"))
end

local function spell_ability(data)
    local ab = data.conjuros and data.conjuros.aptitud
    if type(ab) == "string" and Labels.ABILITY_BY_KEY[ab] then
        return ab
    end
    return nil
end

--- CD de salvación de conjuros (nil si no hay aptitud ni ajuste).
function Rules.spell_dc(data)
    local manual = num(data.ajustes and data.ajustes.cd_conjuros)
    if manual then return manual end
    local ab = spell_ability(data)
    if not ab then return nil end
    return 8 + Rules.prof(data) + ability_mod(data, ab)
end

--- Bonificador de ataque de conjuros (nil si no hay aptitud ni ajuste).
function Rules.spell_atk(data)
    local manual = num(data.ajustes and data.ajustes.ataque_conjuros)
    if manual then return manual end
    local ab = spell_ability(data)
    if not ab then return nil end
    return Rules.prof(data) + ability_mod(data, ab)
end

--- Daño: primero el HP temporal, el resto al actual, con mínimo 0.
function Rules.apply_damage(data, n)
    n = math.floor(num(n) or 0)
    if n <= 0 then return end
    local hp = data.hp
    local temp = hp.temporal or 0
    local absorbed = math.min(temp, n)
    hp.temporal = temp - absorbed
    hp.actual = math.max(0, (hp.actual or 0) - (n - absorbed))
end

--- Curación: suma hasta el máximo (no baja un HP que ya lo supera).
function Rules.apply_heal(data, n)
    n = math.floor(num(n) or 0)
    if n <= 0 then return end
    local hp = data.hp
    local actual = hp.actual or 0
    hp.actual = math.max(actual, math.min(hp.maximo or 0, actual + n))
end

--- Cantidad de dados de golpe de un texto: "5d8" → 5, "3d10+2d8" → 5, inválido → nil.
function Rules.hit_dice_count(total)
    if type(total) ~= "string" then return nil end
    local sum, found = 0, false
    for piece in total:gsub("%s", ""):gmatch("[^+]+") do
        local count = piece:match("^(%d+)[dD]%d+$")
        if count then
            sum = sum + tonumber(count)
            found = true
        elseif not piece:match("^%d+$") then
            return nil
        end
    end
    return found and sum or nil
end

--- Descanso largo: HP al máximo, temporal 0, ranuras, salvaciones de muerte y la mitad de los dados.
function Rules.long_rest(data)
    local hp = data.hp
    hp.actual = hp.maximo or 0
    hp.temporal = 0
    data.muerte = { exitos = 0, fallos = 0 }
    local levels = data.conjuros and data.conjuros.niveles
    if levels then
        for n = 1, 9 do
            local lv = levels[tostring(n)]
            if lv then lv.usados = 0 end
        end
    end
    local dice = Rules.hit_dice_count(data.dados_golpe and data.dados_golpe.total)
    if dice then
        local recovered = math.max(1, math.floor(dice / 2))
        local left = num(data.dados_golpe.restantes) or 0
        data.dados_golpe.restantes = math.min(dice, left + recovered)
    end
end

--- Descanso corto: sin cambios automáticos (el jugador gasta dados y cura a mano).
function Rules.short_rest(_data)
end

local function has_property(weapon, name)
    for _i, p in ipairs(weapon.properties or {}) do
        if p == name then return true end
    end
    return false
end

local function dmg_expr(expr, mod)
    if mod == 0 then return expr end
    return expr .. string.format("%+d", mod)
end

--- Ataque calculado de un arma del compendio (F-08). Atributo: Finesse → el mayor de FUE y DES;
-- a distancia → DES; si no, FUE. bonus = mod + (competencia si `proficient`).
-- @treturn string bonus con signo ("+3")
-- @treturn string daño ("1d6+1 bludgeoning (1d8+1 two-handed)")
-- @treturn string clave del atributo usado ("fue" | "des")
function Rules.weapon_attack(data, weapon, proficient)
    local fue, des = ability_mod(data, "fue"), ability_mod(data, "des")
    local ab, mod
    if has_property(weapon, "Finesse") then
        ab, mod = (des > fue) and "des" or "fue", math.max(fue, des)
    elseif weapon.kind == "ranged" then
        ab, mod = "des", des
    else
        ab, mod = "fue", fue
    end
    local bonus = mod + (proficient and Rules.prof(data) or 0)
    -- los campos null del JSON llegan como un valor que no es texto (rapidjson.null): se ignoran
    local function str(v) return type(v) == "string" and v ~= "" and v or nil end
    local dano = dmg_expr(str(weapon.damage) or "", mod)
    if str(weapon.damage_type) then dano = dano .. " " .. weapon.damage_type end
    if str(weapon.versatile) then dano = dano .. " (" .. dmg_expr(weapon.versatile, mod) .. " two-handed)" end
    return Rules.fmt_signed(bonus), dano, ab
end

--- "+3", "-1", "+0"; nil → "—".
function Rules.fmt_signed(n)
    if type(n) ~= "number" then return "—" end
    return string.format("%+d", n)
end

return Rules
