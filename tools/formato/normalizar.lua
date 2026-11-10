-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Migra y normaliza un .dnd con las MISMAS funciones del plugin y lo imprime como JSON (para validarlo contra el schema).
-- Uso (desde la carpeta del plugin):  luajit <ruta>/normalizar.lua archivo.dnd
package.path = "./?.lua;./tests/?.lua;" .. package.path
require("stubs")
local Schema = require("dndsheet/schema")
local rapidjson = require("rapidjson")
local f = assert(io.open(arg[1], "rb"))
local data, err = rapidjson.decode(f:read("*a"))
f:close()
if type(data) ~= "table" then io.stderr:write("JSON inválido: " .. tostring(err) .. "\n") os.exit(3) end
if Schema.is_readonly(data) then io.stderr:write("versión futura\n") os.exit(4) end
Schema.migrate(data)
Schema.normalize(data)
Schema.fix_arrays(data)
io.write(rapidjson.encode(data, { pretty = true }), "\n")
