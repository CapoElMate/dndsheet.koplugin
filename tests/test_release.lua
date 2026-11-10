-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Publicación: versión SemVer y cabecera SPDX en cada .lua (se corre desde la carpeta del plugin).
local T = {}

function T.version_es_semver()
    local v = require("dndsheet/version")
    if type(v) ~= "string" or not v:match("^%d+%.%d+%.%d+[%w%.%-]*$") then error("versión inválida: " .. tostring(v)) end
end

function T.todos_los_lua_tienen_spdx()
    local p = io.popen("find . -name '*.lua' -not -path './tests/spec/*' -o -name '*_spec.lua' 2>/dev/null")
    local sin, n = {}, 0
    for path in p:lines() do
        n = n + 1
        local f = io.open(path, "r")
        local first = f:read("*l") or ""
        f:close()
        if not first:find("SPDX-License-Identifier: AGPL-3.0-or-later", 1, true) then sin[#sin + 1] = path end
    end
    p:close()
    if n < 30 then error("pocos archivos revisados: " .. n) end
    if #sin > 0 then error("sin SPDX: " .. table.concat(sin, ", ")) end
end

return T
