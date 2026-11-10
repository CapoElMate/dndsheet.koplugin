-- SPDX-License-Identifier: AGPL-3.0-or-later
--[[--
Instrumentación de tiempos. Solo actúa con el log de depuración activo
(Configuración → Dispositivo → Desarrollador → "Activar registro de depuración"); si no, cuesta una comparación.
Las líneas quedan en crash.log con el prefijo "dndsheet: PERF".

@module dndsheet.perf
--]]
local dbg = require("dbg")
local logger = require("logger")
local time = require("ui/time")

local Perf = {
    record = false, -- las pruebas lo activan para leer `samples` sin depender del log
    samples = {},
}

--- Marca de inicio (nil si no se está midiendo).
function Perf.start()
    if dbg.is_on or Perf.record then
        return time.now()
    end
end

--- Cierra la medición `name` iniciada con `Perf.start()`; devuelve los ms (o nil).
function Perf.stop(name, t0, extra)
    if not t0 then return nil end
    local ms = time.to_ms(time.since(t0))
    if Perf.record then
        local list = Perf.samples[name]
        if not list then
            list = {}
            Perf.samples[name] = list
        end
        list[#list + 1] = ms
    end
    if dbg.is_on then
        logger.dbg("dndsheet: PERF", name, string.format("%.1f ms", ms), extra or "")
    end
    return ms
end

--- Mediana de una lista de muestras (ms).
function Perf.median(list)
    if not list or #list == 0 then return nil end
    local copy = { table.unpack(list) }
    table.sort(copy)
    return copy[math.ceil(#copy / 2)]
end

return Perf
