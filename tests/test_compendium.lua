-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Pruebas puras de los datos del compendio SRD 5.2.1 (F-07): integridad, referencias y formato.
local Compendium = require("dndsheet/compendium")
local Rules = require("dndsheet/rules")
local View = require("dndsheet/compendium_view")
local rapidjson = require("rapidjson")

local BASE = "compendium/srd521/en/"

local function load(name)
    local f = assert(io.open(BASE .. name .. ".json", "rb"), "no existe " .. name .. ".json")
    local s = f:read("*a")
    f:close()
    local t, err = rapidjson.decode(s)
    if not t then error("JSON inválido en " .. name .. ": " .. tostring(err)) end
    return t
end

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " esperado " .. tostring(b) .. ", obtuvo " .. tostring(a), 2) end
end

local T = {}

function T.cantidades_y_meta()
    local meta = load("meta")
    eq(meta.counts.classes, #load("classes"))
    eq(meta.counts.subclasses, #load("subclasses"))
    eq(meta.counts.species, #load("species"))
    eq(meta.counts.feats, #load("feats"))
    eq(meta.counts.spells, #load("spells"))
    eq(meta.counts.weapons, #load("weapons"))
    eq(#load("classes"), 12, "clases")
    eq(meta.license, "CC-BY-4.0")
    if not meta.attribution:find("This work includes material from the System Reference Document 5.2.1", 1, true) then
        error("falta la atribución")
    end
    if not meta.sha256:match("^%x+$") or #meta.sha256 ~= 64 then error("sha256 inválido") end
end

function T.ids_unicos_y_referencias()
    local ids = {}
    local function add(id)
        if ids[id] then error("id repetido: " .. id) end
        ids[id] = true
    end
    local classes, subclasses = load("classes"), load("subclasses")
    local names = {}
    for _, c in ipairs(classes) do
        add(c.id)
        names[c.name] = true
        for _, f in ipairs(c.features) do add(f.id) end
    end
    local sub_ids = {}
    for _, s in ipairs(subclasses) do
        add(s.id)
        sub_ids[s.id] = s
        for _, f in ipairs(s.features) do add(f.id) end
    end
    for _, sp in ipairs(load("species")) do
        add(sp.id)
        for _, t in ipairs(sp.traits) do add(t.id) end
    end
    for _, f in ipairs(load("feats")) do add(f.id) end
    for _, w in ipairs(load("weapons")) do add(w.id) end
    for _, c in ipairs(classes) do
        for _, sid in ipairs(c.subclass_ids) do
            if not sub_ids[sid] then error("subclase inexistente " .. sid) end
            eq(sub_ids[sid].class_id, c.id)
        end
    end
    for _, sp in ipairs(load("spells")) do
        add(sp.id)
        if #sp.classes == 0 then error("conjuro sin clases: " .. sp.id) end
        for _, cn in ipairs(sp.classes) do
            if not names[cn] then error("clase inexistente " .. cn .. " en " .. sp.id) end
        end
    end
end

function T.clases_con_rasgos_y_nivel_1()
    for _, c in ipairs(load("classes")) do
        local lv1 = false
        for _, f in ipairs(c.features) do
            if f.level == 1 then lv1 = true end
            if f.text == "" then error("rasgo sin texto: " .. f.id) end
        end
        if not lv1 then error("sin rasgos de nivel 1: " .. c.id) end
        if not c.hit_die or #c.saving_throws ~= 2 then error("clase incompleta: " .. c.id) end
    end
end

function T.conjuros_campos_y_niveles()
    for _, s in ipairs(load("spells")) do
        for _, k in ipairs({ "name", "school", "casting_time", "range", "components", "duration", "text" }) do
            if type(s[k]) ~= "string" or s[k] == "" then error("conjuro " .. s.id .. " sin " .. k) end
        end
        if s.level < 0 or s.level > 9 then error("nivel fuera de rango: " .. s.id) end
    end
end

function T.armas_formato()
    local n = 0
    for _, w in ipairs(load("weapons")) do
        n = n + 1
        if w.id ~= "weapon.blowgun" and not w.damage:match("^%d+d%d+$") then error("daño inválido: " .. w.id) end
        if w.id == "weapon.blowgun" then eq(w.damage, "1") end
        if not w.mastery or w.mastery == "" then error("sin mastery: " .. w.id) end
        if type(w.properties) ~= "table" then error("sin properties: " .. w.id) end
        if w.category ~= "simple" and w.category ~= "martial" then error("categoría: " .. w.id) end
        if w.kind ~= "melee" and w.kind ~= "ranged" then error("tipo: " .. w.id) end
    end
    eq(n, 38)
end

function T.valores_conocidos()
    local spells = {}
    for _, s in ipairs(load("spells")) do spells[s.id] = s end
    eq(spells["spell.fireball"].level, 3)
    eq(spells["spell.fire-bolt"].level, 0)
    eq(spells["spell.fireball"].school, "Evocation")
    local monk
    for _, c in ipairs(load("classes")) do if c.id == "monk" then monk = c end end
    eq(monk.hit_die, 8)
    local weapons = {}
    for _, w in ipairs(load("weapons")) do weapons[w.id] = w end
    eq(weapons["weapon.quarterstaff"].versatile, "1d8")
    eq(weapons["weapon.dagger"].range, "20/60")
    eq(weapons["weapon.shortbow"].range, "80/320")
end

-- ── F-08: carga perezosa, entradas propias, búsqueda, visor y alta en la hoja ──

local CUSTOM = "tests/fixtures/compendio"

local function ls(dir)
    local names = {}
    local p = io.popen("ls '" .. dir .. "' 2>/dev/null")
    for name in p:lines() do names[#names + 1] = name end
    p:close()
    return names
end

-- Compendio con lectura contada (para comprobar que carga solo lo que se pide)
local function counted(opts)
    local reads = {}
    opts = opts or {}
    opts.root = "compendium"
    opts.list_dir = ls
    opts.read_file = function(path)
        reads[#reads + 1] = path
        local f = io.open(path, "rb")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end
    return Compendium.new(opts), reads
end

local function count(reads, pattern)
    local n = 0
    for _i, p in ipairs(reads) do
        if p:find(pattern) then n = n + 1 end
    end
    return n
end

function T.carga_perezosa_por_archivo()
    local c, reads = counted()
    eq(#reads, 0, "al crear no se lee nada")
    c:entries("spells")
    eq(count(reads, "spells%.json"), 1)
    eq(count(reads, "classes%.json"), 0, "no se carga lo que no se pidió")
    eq(count(reads, "weapons%.json"), 0)
    c:entries("spells")
    eq(count(reads, "spells%.json"), 1, "segunda vez: caché")
    eq(Compendium.is_loaded(), false, "la instancia suelta no es la compartida")
end

function T.resolve_carga_solo_el_archivo_probable()
    local c, reads = counted()
    local hit = c:resolve("monk.slow-fall")
    eq(hit.kind, "classes")
    eq(hit.item.name, "Slow Fall")
    eq(hit.item.level, 4)
    eq(count(reads, "spells%.json"), 0)
    eq(c:resolve("spell.fire-bolt").entry.name, "Fire Bolt")
    eq(c:resolve("weapon.quarterstaff").entry.name, "Quarterstaff")
    eq(c:resolve("feat.alert").entry.category, "origin")
    eq(c:resolve("species.elf.trance").item.name, "Trance")
    eq(c:resolve("subclass.champion.improved-critical").item.level, 3)
    eq(c:resolve("no.existe"), nil)
    eq(c:peek("no.existe"), false, "todo cargado y no está")
end

function T.peek_no_lee_nada()
    local c, reads = counted()
    eq(c:peek("monk.slow-fall"), nil)
    eq(#reads, 0)
    eq(Compendium.peekShared("monk.slow-fall"), nil)
end

function T.entradas_propias_validas_rotas_y_repetidas()
    local c = counted({ custom_dir = CUSTOM })
    local spells = c:entries("spells")
    local by_id = {}
    for _i, e in ipairs(spells) do by_id[e.id] = e end
    eq(by_id["custom.ember-lash"].source, "custom")
    eq(by_id["spell.fire-bolt"].name, "Fire Bolt (regla de la casa)", "gana la propia")
    eq(by_id["spell.fire-bolt"].override, true)
    eq(by_id["spell.sin-texto"], nil, "inválida: se saltea")
    local feats = c:entries("feats")
    eq(feats[#feats].id, "custom.example-feat")
    eq(#c:entries("weapons"), 38, "arma inválida no suma")
    local a = c:about()
    eq(a.custom_files, 3)
    eq(a.custom_entries, 3)
    eq(a.custom_errors, 3, "JSON roto + conjuro sin texto + arma incompleta")
    -- una entrada propia con prefijo desconocido se resuelve igual
    eq(c:resolve("custom.ember-lash").entry.name, "Ember Lash")
    eq(c:resolve("custom.example-feat").kind, "feats")
end

function T.sin_carpeta_propia_no_hay_entradas_propias()
    local c = counted({ custom_dir = "tests/fixtures/no-existe" })
    eq(#c:entries("spells"), 339)
    eq(c:about().custom_entries, 0)
    eq(c:about().custom_errors, 0)
end

function T.idioma_sin_datos_cae_en_ingles()
    eq(Compendium.new({ root = "compendium", lang = "es" }).lang, "en")
    eq(Compendium.new({ root = "compendium", lang = "en" }).lang, "en")
    -- si existiera srd521/es/ se usaría (simulado con una lectura que lo "encuentra")
    local c = Compendium.new({ root = "compendium", lang = "es", read_file = function(p) return p:find("/es/meta.json") and "{}" or nil end })
    eq(c.lang, "es")
end

function T.validar_entradas_propias()
    local V = Compendium.validate
    eq((V("spells", { id = "a", name = "A", level = 2, text = "x" })), true)
    eq((V("spells", { id = "a", name = "A", level = 12, text = "x" })), false)
    eq((V("spells", { id = "a", name = "A", level = 2 })), false)
    eq((V("feats", { id = "a", name = "A", text = "x" })), true)
    eq((V("weapons", { id = "a", name = "A" })), false)
    eq((V("weapons", { id = "a", name = "A", damage = "1d6", category = "simple", kind = "melee" })), true)
    eq((V("subclasses", { id = "a", name = "A", class_id = "fighter", features = { { id = "f", name = "F", level = 3, text = "t" } } })), true)
    eq((V("subclasses", { id = "a", name = "A", features = {} })), false, "sin class_id")
    eq((V("classes", { id = "a", name = "A", features = { { id = "f", name = "F", text = "t" } } })), false, "rasgo sin level")
    eq((V("species", { id = "a", name = "A", traits = { { id = "t", name = "T", text = "t" } } })), true)
    eq((V("spells", "no es tabla")), false)
    eq((V("desconocido", { id = "a", name = "A" })), false)
end

function T.busqueda_ignora_mayusculas_y_tildes()
    eq(Compendium.fold("Cuación Mágica ÑANDÚ"), "cuacion magica nandu")
    eq(Compendium.matches("Fire Bolt", "FIRE"), true)
    eq(Compendium.matches("Fire Bolt", " bolt "), true)
    eq(Compendium.matches("Fire Bolt", "ice"), false)
    eq(Compendium.matches("Tasha’s Hideous Laughter", "tasha's"), true)
    eq(Compendium.matches("Maldición", "maldicion"), true)
    eq(Compendium.matches("Cualquiera", ""), true)
    local c = counted()
    local found = c:search("spells", "fire")
    local names = {}
    for _i, e in ipairs(found) do names[e.name] = true end
    eq(names["Fire Bolt"], true)
    eq(names["Fireball"], true)
    eq(names["Faerie Fire"], true)
    eq(names["Aid"], nil)
end

function T.visor_describe_conjuro_arma_dote_rasgo()
    local c = counted()
    local function d(ref)
        local hit = c:resolve(ref)
        return View.describe(c, hit)
    end
    local title, info, body = d("spell.fireball")
    eq(title, "Fireball")
    if not info:find("3", 1, true) or not info:find("Evocation", 1, true) or not info:find("150 feet", 1, true) or not info:find("SRD 5.2.1", 1, true) then
        error("línea de datos del conjuro: " .. info)
    end
    if not body:find("A bright streak flashes", 1, true) or not body:find("Using a Higher-Level Spell Slot", 1, true) then error("cuerpo del conjuro") end
    local _, info2 = d("monk.slow-fall")
    if not info2:find("Monk 4", 1, true) then error("rasgo de clase: " .. info2) end
    local _, info3, body3 = d("weapon.quarterstaff")
    if not info3:find("1d6 bludgeoning", 1, true) or not body3:find("1d8", 1, true) then error("arma: " .. info3 .. body3) end
    local _, info4 = d("feat.grappler")
    if not info4:find("Level 4+", 1, true) then error("dote: " .. info4) end
    local c2 = counted({ custom_dir = CUSTOM })
    local _, info5 = View.describe(c2, c2:resolve("custom.example-feat"))
    if not info5:find(("(propia)"), 1, true) then error("origen propio: " .. info5) end
    local _, info6 = View.describe(c2, c2:resolve("spell.fire-bolt"))
    if not info6:find("reemplaza", 1, true) then error("origen que reemplaza: " .. info6) end
end

local function pj()
    local Schema = require("dndsheet/schema")
    local d = Schema.normalize({})
    d.atributos.fue, d.atributos.des = 12, 16
    return d
end

function T.alta_en_la_hoja_rasgo_conjuro_arma()
    local c = counted()
    local d = pj()
    eq(View.add_feature(d, "monk.slow-fall", "Slow Fall"), "added")
    eq(View.add_feature(d, "monk.slow-fall", "Slow Fall"), "exists")
    eq(#d.rasgos_ref, 1)
    eq(d.rasgos_ref[1].nota, "")
    -- conjuro: queda en su nivel, con ref; los trucos no llevan "preparado"
    eq(View.add_spell(d, c:resolve("spell.fire-bolt").entry), "added")
    eq(d.conjuros.niveles["0"].lista[1].ref, "spell.fire-bolt")
    eq(d.conjuros.niveles["0"].lista[1].preparado, nil)
    local r, lvl = View.add_spell(d, c:resolve("spell.fireball").entry)
    eq(r, "added")
    eq(lvl, 3)
    eq(d.conjuros.niveles["3"].lista[1].preparado, false)
    eq(View.add_spell(d, c:resolve("spell.fireball").entry), "exists")
    -- arma: valores calculados en el momento
    local qs = c:resolve("weapon.quarterstaff").entry
    local bonus, dano = View.add_attack(d, qs, true)
    eq(bonus, "+3")
    eq(dano, "1d6+1 bludgeoning (1d8+1 two-handed)")
    local a = d.ataques[#d.ataques]
    eq(a.nombre, "Quarterstaff")
    eq(a.ref, "weapon.quarterstaff")
    eq(a.bonus, Rules.weapon_attack(d, qs, true))
    local b2 = View.add_attack(d, c:resolve("weapon.dagger").entry, false)
    eq(b2, "+3", "sin competencia")
end

function T.plantilla_propia_es_valida_y_se_carga()
    local f = assert(io.open("compendium/plantilla-propia.json", "rb"))
    local t = assert(rapidjson.decode(f:read("*a")))
    f:close()
    eq(type(t._comentario), "string")
    for _i, e in ipairs(t.subclasses) do
        eq((Compendium.validate("subclasses", e)), true)
        eq(e.source, "custom")
    end
    -- copiada a la carpeta propia, el compendio la lee y no cuenta errores
    os.execute("rm -rf /tmp/dnd_plantilla_prueba && mkdir -p /tmp/dnd_plantilla_prueba && cp compendium/plantilla-propia.json /tmp/dnd_plantilla_prueba/")
    local c = Compendium.new({ root = "compendium", custom_dir = "/tmp/dnd_plantilla_prueba", list_dir = ls })
    local subs = c:entries("subclasses")
    eq(subs[#subs].id, "custom.subclase-ejemplo")
    eq(c:about().custom_errors, 0)
    eq(c:resolve("custom.subclase-ejemplo.rasgo-ejemplo").item.level, 3)
    os.execute("rm -rf /tmp/dnd_plantilla_prueba")
end

-- F-10 todavía no calcula `efectos`: una entrada que los trae (incluso mal formados) se acepta y se ignoran
function T.efectos_se_ignoran_sin_error()
    local e = {
        id = "custom.subclass.x", class_id = "fighter", name = "X",
        features = { { id = "custom.subclass.x.a", name = "A", level = 3, text = "t",
                       efectos = { { tipo = "bono", a = "ca", valor = 1 }, { tipo = "magia" } } } },
        efectos = { { tipo = "recurso", nombre = "R", usos = 2, descanso = "corto" } },
    }
    local ok, why = Compendium.validate("subclasses", e)
    assert(ok, tostring(why))
end

return T
