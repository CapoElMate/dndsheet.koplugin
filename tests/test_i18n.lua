-- SPDX-License-Identifier: AGPL-3.0-or-later
-- F-02: idiomas. `resolve` es pura; la cobertura y la limpieza leen los archivos del plugin.
local I18n = require("dndsheet/i18n")

local T = {}

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local EN_ES = { "en", "es" }

function T.resolve_con_en_y_es()
    local function r(pref, sys, av) return I18n.resolve(pref, sys, av or EN_ES) end
    eq(r("auto", nil), "en", "nil")
    eq(r("auto", "C"), "en", "C")
    eq(r("auto", ""), "en", "vacío")
    eq(r("auto", "en_US.UTF-8"), "en", "en_US.UTF-8")
    eq(r("auto", "en_GB"), "en", "en_GB")
    eq(r("auto", "es"), "es", "es")
    eq(r("auto", "es_MX"), "es", "es_MX")
    eq(r("auto", "es_AR.utf8"), "es", "es_AR.utf8")
    eq(r("auto", "es-AR"), "es", "es-AR")
    eq(r("auto", "pt_BR"), "en", "pt_BR")
    eq(r("auto", "zh_CN.utf8"), "en", "zh_CN")
    eq(r("en", "es"), "en", "preferencia en con sistema es")
    eq(r("es", "en_US"), "es", "preferencia es con sistema en")
    eq(r("xx", "es"), "es", "preferencia inexistente → automático (es)")
    eq(r("xx", nil), "en", "preferencia inexistente → automático (en)")
    eq(r(nil, "es"), "es", "sin preferencia")
end

function T.resolve_variantes()
    eq(I18n.resolve("auto", "es", { "en", "es_AR" }), "es_AR")
    eq(I18n.resolve("auto", "es_MX", { "en", "es_AR" }), "es_AR")
    eq(I18n.resolve("auto", "es_MX", { "en", "es_AR", "es_MX" }), "es_MX")
    eq(I18n.resolve("auto", "es", { "en", "es_AR", "es_MX" }), "es_AR", "alfabético")
    eq(I18n.resolve("auto", "es_ES", { "en", "es_MX", "es_AR" }), "es_AR", "alfabético con otro orden de entrada")
    eq(I18n.resolve("auto", "pt_BR", { "en", "es_AR" }), "en")
    eq(I18n.resolve("auto", "es", { "en", "es", "es_AR" }), "es", "el idioma base gana a las variantes")
end

-- Lee las claves de un archivo de idioma
local function load_lang(code)
    local f = assert(loadfile("dndsheet/lang/" .. code .. ".lua"))
    return f()
end

local function lang_codes()
    local out = {}
    local p = assert(io.popen("ls dndsheet/lang"))
    for name in p:lines() do
        local code = name:match("^([%w_]+)%.lua$")
        if code then out[#out + 1] = code end
    end
    p:close()
    table.sort(out)
    return out
end

function T.cobertura_de_claves()
    local codes = lang_codes()
    assert(#codes >= 2, "hay al menos en y es")
    local en = load_lang("en")
    for _i, code in ipairs(codes) do
        local t = load_lang(code)
        assert(type(t._name) == "string" and t._name ~= "", code .. ": falta _name")
        for k in pairs(en) do
            if t[k] == nil then error(code .. " no tiene la clave " .. k) end
        end
        for k, v in pairs(t) do
            if en[k] == nil then error(code .. " tiene la clave " .. k .. " que no está en en.lua") end
            if type(v) ~= "string" or v == "" then error(code .. ": valor inválido en " .. k) end
        end
    end
end

function T.mismos_argumentos_en_todos_los_idiomas()
    -- %1, %2… deben coincidir entre idiomas (cada traducción usa los mismos valores)
    local en = load_lang("en")
    local function args(s)
        local set = {}
        for n in s:gmatch("%%(%d)") do set[n] = true end
        local l = {}
        for n in pairs(set) do l[#l + 1] = n end
        table.sort(l)
        return table.concat(l, ",")
    end
    for _i, code in ipairs(lang_codes()) do
        local t = load_lang(code)
        for k, v in pairs(en) do
            if k ~= "_name" and args(t[k]) ~= args(v) then
                error(code .. ": los argumentos de " .. k .. " no coinciden (" .. args(t[k]) .. " vs " .. args(v) .. ")")
            end
        end
    end
end

function T.limpieza_sin_gettext_propio()
    -- ningún _("…") ni require("gettext") propio fuera de tests/
    local p = assert(io.popen([[grep -rnE '(^|[^%w_.])_\(|require\("gettext"\)' --include=*.lua . | grep -v '^./tests/']]))
    local out = p:read("*a")
    p:close()
    eq(out, "", "quedan usos de gettext:\n" .. out)
end

function T.todas_las_claves_usadas_existen()
    -- T("clave") literales y claves dinámicas (atributos, habilidades, páginas) del código
    local en = load_lang("en")
    local p = assert(io.popen([[grep -rnoE 'T\("[a-z_]+\.[a-z_.]+"' --include=*.lua . main.lua _meta.lua | grep -v '^./tests/']]))
    local missing = {}
    for line in p:lines() do
        local key = line:match('T%("([^"]+)"')
        if key and en[key] == nil then missing[#missing + 1] = line end
    end
    p:close()
    eq(#missing, 0, "claves usadas que no están en en.lua: " .. table.concat(missing, "; "))
    -- también las claves por label_key / title_key
    local p2 = assert(io.popen([[grep -rhoE '(label_key|title_key) = "[a-z_.]+"' --include=*.lua dndsheet]]))
    for line in p2:lines() do
        local key = line:match('"([^"]+)"')
        if en[key] == nil then missing[#missing + 1] = key end
    end
    p2:close()
    eq(#missing, 0, "claves (label_key/title_key) que no están en en.lua: " .. table.concat(missing, "; "))
    local Labels = require("dndsheet/labels")
    for _i, a in ipairs(Labels.ABILITIES) do
        assert(en["ability." .. a.key] and en["ability." .. a.key .. ".short"], "falta ability." .. a.key)
    end
    for _i, s in ipairs(Labels.SKILLS) do assert(en["skill." .. s.key], "falta skill." .. s.key) end
    for _i, pg in ipairs(Labels.PAGES) do assert(en["page." .. pg.id], "falta page." .. pg.id) end
end

function T.t_con_idioma_respaldo_y_claves_faltantes()
    I18n.set_language("es")
    eq(I18n.T("page.combat"), "Combate")
    eq(I18n.T("spell.slots_title", 3), "Ranuras de nivel 3")
    I18n.set_language("en")
    eq(I18n.T("page.combat"), "Combat")
    eq(I18n.T("spell.slots_title", 3), "Level 3 slots")
    eq(I18n.T("no.existe"), "[no.existe]")
    I18n.set_language("zz") -- inexistente → inglés
    eq(I18n.T("page.combat"), "Combat")
    I18n.set_language("es") -- el resto de las pruebas esperan español
end

return T
