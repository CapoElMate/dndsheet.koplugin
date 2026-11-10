-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Dados (F-06): reglas PURAS (sin interfaz) de la bandeja de dados. Todo recibe el generador `rng(a, b)`
(entero uniforme en [a, b]; por defecto `math.random`) para poder probarlo con valores forzados.

@module dndsheet.dice
--]]
local Dice = {}

--- Los 7 dados de D&D, en el orden de la bandeja.
Dice.FACES = { 4, 6, 8, 10, 12, 20, 100 }

--- Tirada final: entero en [1, faces].
function Dice.roll(faces, rng)
    return (rng or math.random)(1, faces)
end

--- Valor de un cuadro de la animación: en [1, faces] y distinto de `prev` (si `faces` > 1).
function Dice.next_frame_value(faces, prev, rng)
    rng = rng or math.random
    if faces <= 1 or not prev or prev < 1 or prev > faces then
        return rng(1, faces)
    end
    local v = rng(1, faces - 1) -- uniforme entre los demás valores
    if v >= prev then v = v + 1 end
    return v
end

--- ¿Es un 20 o un 1 natural? (solo en d20: la bandeja los dibuja invertidos).
function Dice.is_natural(faces, value)
    return faces == 20 and (value == 20 or value == 1)
end

--- Agrega `entry` al historial (los más recientes primero), de largo máximo `max` (3 por defecto).
function Dice.push_history(history, entry, max)
    table.insert(history, 1, entry)
    while #history > (max or 3) do table.remove(history) end
    return history
end

return Dice
