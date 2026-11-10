-- SPDX-License-Identifier: AGPL-3.0-or-later
local Dice = require("dndsheet/dice")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local T = {}

function T.roll_en_rango_y_extremos()
    math.randomseed(12345)
    for _, faces in ipairs(Dice.FACES) do
        local seen_min, seen_max = false, false
        for _ = 1, 10000 do
            local v = Dice.roll(faces)
            if v < 1 or v > faces or v ~= math.floor(v) then error("fuera de rango d" .. faces .. ": " .. v) end
            if v == 1 then seen_min = true end
            if v == faces then seen_max = true end
        end
        if not (seen_min and seen_max) then error("d" .. faces .. " no mostró 1 y el máximo en 10 000 tiradas") end
    end
end

function T.roll_usa_el_generador_inyectado()
    eq(Dice.roll(20, function(a, b) eq(a, 1) eq(b, 20) return 20 end), 20)
end

function T.next_frame_nunca_repite_y_queda_en_rango()
    math.randomseed(777)
    for _, faces in ipairs(Dice.FACES) do
        local prev = 1
        for _ = 1, 10000 do
            local v = Dice.next_frame_value(faces, prev)
            if v < 1 or v > faces then error("fuera de rango d" .. faces) end
            if v == prev then error("repitió " .. v .. " en d" .. faces) end
            prev = v
        end
    end
end

function T.next_frame_cubre_todos_los_valores()
    math.randomseed(99)
    local seen, prev = {}, 3
    for _ = 1, 2000 do
        prev = Dice.next_frame_value(6, prev)
        seen[prev] = true
    end
    for v = 1, 6 do if not seen[v] then error("nunca salió " .. v) end end
end

function T.next_frame_sin_anterior()
    local v = Dice.next_frame_value(8, nil, function() return 5 end)
    eq(v, 5)
end

function T.natural()
    eq(Dice.is_natural(20, 20), true)
    eq(Dice.is_natural(20, 1), true)
    eq(Dice.is_natural(20, 13), false)
    eq(Dice.is_natural(6, 1), false)
    eq(Dice.is_natural(100, 100), false)
end

function T.historial_de_3()
    local h = {}
    for i = 1, 5 do Dice.push_history(h, i) end
    eq(#h, 3)
    eq(h[1], 5)
    eq(h[3], 3)
end

return T
