-- SPDX-License-Identifier: AGPL-3.0-or-later
local Rules = require("dndsheet/rules")
local Schema = require("dndsheet/schema")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local function thalia()
    local d = Schema.normalize({
        nivel = 5,
        atributos = { fue = 8, des = 18, con = 14, int = 12, sab = 13, car = 14 },
        salvaciones = { des = true, int = true },
        habilidades = { acrobacias = 1, engano = 2, percepcion = 1, sigilo = 2 },
        hp = { maximo = 38, actual = 27, temporal = 5 },
        dados_golpe = { total = "5d8", restantes = 3 },
    })
    return d
end

local T = {}

function T.mod()
    for score, m in pairs({ [1] = -5, [8] = -1, [10] = 0, [11] = 0, [18] = 4, [30] = 10 }) do
        eq(Rules.mod(score), m, "mod(" .. score .. ")")
    end
end

function T.prof_por_nivel()
    local esperado = { [1] = 2, [4] = 2, [5] = 3, [8] = 3, [9] = 4, [12] = 4, [13] = 5, [16] = 5, [17] = 6, [20] = 6 }
    for lvl, p in pairs(esperado) do
        eq(Rules.prof({ nivel = lvl }), p, "prof nivel " .. lvl)
    end
end

function T.prof_manual()
    eq(Rules.prof({ nivel = 5, ajustes = { competencia = 4 } }), 4)
end

function T.skill_0_1_2()
    local d = thalia()
    eq(Rules.skill(d, "atletismo"), -1)
    eq(Rules.skill(d, "acrobacias"), 7)
    eq(Rules.skill(d, "sigilo"), 10)
    eq(Rules.skill(d, "engano"), 8)
    eq(Rules.skill(d, "inexistente"), nil)
end

function T.save()
    local d = thalia()
    eq(Rules.save(d, "des"), 7)
    eq(Rules.save(d, "fue"), -1)
    eq(Rules.save(d, "int"), 4)
end

function T.iniciativa_y_pasiva()
    local d = thalia()
    eq(Rules.initiative(d), 4)
    eq(Rules.passive(d), 14)
    d.ajustes.percepcion_pasiva = 20
    d.ajustes.iniciativa = 9
    eq(Rules.passive(d), 20)
    eq(Rules.initiative(d), 9)
end

function T.conjuros_con_y_sin_aptitud()
    local d = thalia()
    eq(Rules.spell_dc(d), nil)
    eq(Rules.spell_atk(d), nil)
    d.conjuros.aptitud = "int"
    eq(Rules.spell_dc(d), 12)
    eq(Rules.spell_atk(d), 4)
    d.conjuros.aptitud = "car"
    eq(Rules.spell_dc(d), 13)
    d.ajustes.cd_conjuros = 15
    eq(Rules.spell_dc(d), 15)
end

function T.dano_con_temporal()
    local d = thalia()
    Rules.apply_damage(d, 8)
    eq(d.hp.temporal, 0)
    eq(d.hp.actual, 24)
end

function T.dano_no_negativo()
    local d = thalia()
    Rules.apply_damage(d, 100)
    eq(d.hp.actual, 0)
    eq(d.hp.temporal, 0)
end

function T.curacion_con_tope()
    local d = thalia()
    d.hp.actual = 10
    Rules.apply_heal(d, 50)
    eq(d.hp.actual, 38)
    d.hp.actual = 40 -- por encima del máximo: no se baja
    Rules.apply_heal(d, 5)
    eq(d.hp.actual, 40)
end

function T.descanso_largo()
    local d = thalia()
    d.conjuros.niveles["1"].total = 3
    d.conjuros.niveles["1"].usados = 3
    d.muerte.fallos = 2
    Rules.long_rest(d)
    eq(d.hp.actual, 38)
    eq(d.hp.temporal, 0)
    eq(d.conjuros.niveles["1"].usados, 0)
    eq(d.muerte.fallos, 0)
    eq(d.dados_golpe.restantes, 5)
    d.dados_golpe.restantes = 0
    Rules.long_rest(d)
    eq(d.dados_golpe.restantes, 2)
end

function T.hit_dice_count()
    eq(Rules.hit_dice_count("5d8"), 5)
    eq(Rules.hit_dice_count("3d10+2d8"), 5)
    eq(Rules.hit_dice_count("x"), nil)
    eq(Rules.hit_dice_count(nil), nil)
end

function T.fmt_signed()
    eq(Rules.fmt_signed(3), "+3")
    eq(Rules.fmt_signed(0), "+0")
    eq(Rules.fmt_signed(-2), "-2")
    eq(Rules.fmt_signed(nil), "—")
end

-- F-08: ataque calculado de un arma del compendio
local function weapon(id)
    local f = assert(io.open("compendium/srd521/en/weapons.json", "rb"))
    local list = require("rapidjson").decode(f:read("*a"))
    f:close()
    for _i, w in ipairs(list) do
        if w.id == id then return w end
    end
    error("arma inexistente " .. id)
end

local function pj(fue, des, nivel)
    return { atributos = { fue = fue, des = des }, nivel = nivel or 1, ajustes = {} }
end

function T.weapon_attack_quarterstaff()
    local bonus, dano, ab = Rules.weapon_attack(pj(12, 16), weapon("weapon.quarterstaff"), true)
    eq(bonus, "+3")
    eq(dano, "1d6+1 bludgeoning (1d8+1 two-handed)")
    eq(ab, "fue")
end

function T.weapon_attack_dagger_finesse_usa_el_mayor()
    local bonus, dano, ab = Rules.weapon_attack(pj(12, 16), weapon("weapon.dagger"), true)
    eq(bonus, "+5")
    eq(dano, "1d4+3 piercing")
    eq(ab, "des")
    -- con más FUE que DES usa FUE
    local b2, _, ab2 = Rules.weapon_attack(pj(18, 12), weapon("weapon.dagger"), true)
    eq(b2, "+6")
    eq(ab2, "fue")
end

function T.weapon_attack_a_distancia_usa_destreza()
    local bonus, dano = Rules.weapon_attack(pj(12, 16), weapon("weapon.shortbow"), true)
    eq(bonus, "+5")
    eq(dano, "1d6+3 piercing")
end

function T.weapon_attack_sin_competencia_y_modificador_cero_o_negativo()
    local bonus = Rules.weapon_attack(pj(12, 16), weapon("weapon.quarterstaff"), false)
    eq(bonus, "+1")
    local dano = select(2, Rules.weapon_attack(pj(10, 10), weapon("weapon.quarterstaff"), true))
    eq(dano, "1d6 bludgeoning (1d8 two-handed)")
    local b3, d3 = Rules.weapon_attack(pj(8, 10), weapon("weapon.club"), true)
    eq(b3, "+1")
    eq(d3, "1d4-1 bludgeoning")
end

function T.weapon_attack_usa_la_competencia_del_nivel()
    local bonus = Rules.weapon_attack(pj(10, 10, 9), weapon("weapon.club"), true)
    eq(bonus, "+4")
end

return T
