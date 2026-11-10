-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Uso (desde la carpeta dndsheet.koplugin):  luajit tests/run.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
require("stubs")

-- Las aserciones de test_store buscan textos en español: se fija el idioma (el predeterminado sería el inglés).
require("dndsheet/i18n").set_language("es")

local files = { "test_rules", "test_schema", "test_store", "test_i18n", "test_dice", "test_compendium", "test_release", "test_vectors" }
local pass, fail = 0, 0
for _, f in ipairs(files) do
    local suite = require(f)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(suite[name])
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            print("FALLA " .. f .. " · " .. name .. "\n  " .. tostring(err))
        end
    end
end
print(string.format("%d ok, %d fallas", pass, fail))
os.exit(fail == 0 and 0 or 1)
