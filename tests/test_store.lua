-- SPDX-License-Identifier: AGPL-3.0-or-later
local Store = require("dndsheet/store")
local Schema = require("dndsheet/schema")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local function exists(p)
    local f = io.open(p, "rb")
    if f then f:close() end
    return f ~= nil
end

local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local TMP = os.tmpname()
os.remove(TMP)
local DIR = TMP .. "_dnd"
os.execute("mkdir -p '" .. DIR .. "'")

local function ruta(name) return DIR .. "/" .. name end

local T = {}

function T.save_y_load_dan_lo_mismo()
    local d = Schema.normalize({ nombre = "Ñandú ✓ 🐉", notas = "línea 1\nlínea 2\n\n\"comillas\" \\ barra" })
    d.hp.actual = 7
    local ok, err = Store.save(ruta("a.dnd"), d)
    eq(ok, true, tostring(err))
    local back = assert(Store.load(ruta("a.dnd")))
    eq(back.nombre, "Ñandú ✓ 🐉")
    eq(back.notas, "línea 1\nlínea 2\n\n\"comillas\" \\ barra")
    eq(back.hp.actual, 7)
    eq(type(back.meta.guardado), "number")
    assert(back.meta.guardado > 0)
end

function T.sin_tmp_despues_de_guardar()
    Store.save(ruta("b.dnd"), Schema.normalize({}))
    eq(exists(ruta("b.dnd")), true)
    eq(exists(ruta("b.dnd.tmp")), false)
end

function T.lista_vacia_se_guarda_como_array()
    local d = Schema.normalize({})
    d.ataques = {} -- tabla Lua común: sin Store.save sería {}
    Store.save(ruta("c.dnd"), d)
    assert(read(ruta("c.dnd")):find('"ataques": []', 1, true), "ataques debe ser []")
end

function T.guardar_en_carpeta_inexistente_falla()
    local ok, err = Store.save(DIR .. "/no_existe/x.dnd", Schema.normalize({}))
    eq(ok, nil)
    eq(type(err), "string")
end

function T.original_intacto_si_falla()
    local p = ruta("d.dnd")
    Store.save(p, Schema.normalize({ nombre = "Original" }))
    local antes = read(p)
    local d = Schema.normalize({ nombre = "Nuevo" })
    d.roto = function() end -- no serializable
    local ok = Store.save(p, d)
    eq(ok, nil)
    eq(read(p), antes)
    eq(exists(p .. ".tmp"), false)
end

function T.no_guarda_solo_lectura()
    local ok, err = Store.save(ruta("e.dnd"), { meta = { schema = 99 } })
    eq(ok, nil)
    assert(err:find("solo lectura"))
    eq(exists(ruta("e.dnd")), false)
end

function T.load_errores()
    local d, err = Store.load(DIR .. "/no_hay.dnd")
    eq(d, nil)
    assert(err:find("No se pudo leer"), err)
    local f = assert(io.open(ruta("roto.dnd"), "wb"))
    f:write('{"nombre": "x",')
    f:close()
    d, err = Store.load(ruta("roto.dnd"))
    eq(d, nil)
    assert(err:find("JSON"), err)
    f = assert(io.open(ruta("lista.dnd"), "wb"))
    f:write("[1,2]")
    f:close()
    d, err = Store.load(ruta("lista.dnd"))
    eq(d, nil)
    assert(err)
end

function T.load_con_bom()
    local f = assert(io.open(ruta("bom.dnd"), "wb"))
    f:write("\239\187\191" .. '{"nombre": "Bom"}')
    f:close()
    eq(Store.load(ruta("bom.dnd")).nombre, "Bom")
end

function T.backup()
    local p = ruta("f.dnd")
    Store.save(p, Schema.normalize({ nombre = "Uno" }))
    eq(Store.backup(p), true)
    eq(read(p .. ".bak"), read(p))
    eq(Store.backup(ruta("nada.dnd")), true)
    eq(exists(ruta("nada.dnd.bak")), false)
end

return T
