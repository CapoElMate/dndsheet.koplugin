-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Módulos falsos de KOReader para probar la lógica pura con luajit.
local cjson = require("cjson")

local NULL = cjson.null

-- ── rapidjson ───────────────────────────────────────────────────────────────
local ARRAY_MT = { __jsontype = "array" }

local function is_seq(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t and n > 0
end

local function encode_value(v, pretty, indent)
    local tv = type(v)
    if v == NULL then return "null" end
    if tv == "nil" then return "null" end
    if tv == "boolean" then return tostring(v) end
    if tv == "number" then return string.format("%.14g", v) end
    if tv == "string" then return cjson.encode(v) end
    if tv ~= "table" then error("tipo no serializable: " .. tv) end
    local nl = pretty and "\n" or ""
    local ind = pretty and string.rep("  ", indent + 1) or ""
    local ind0 = pretty and string.rep("  ", indent) or ""
    local parts = {}
    local mt = getmetatable(v)
    if mt == ARRAY_MT or is_seq(v) then
        for i = 1, #v do parts[#parts + 1] = ind .. encode_value(v[i], pretty, indent + 1) end
        if #parts == 0 then return "[]" end
        return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. ind0 .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        parts[#parts + 1] = ind .. cjson.encode(k) .. ":" .. (pretty and " " or "") .. encode_value(val, pretty, indent + 1)
    end
    if #parts == 0 then return "{}" end
    return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. ind0 .. "}"
end

package.loaded["rapidjson"] = {
    null = NULL,
    decode = function(s)
        local ok, res = pcall(cjson.decode, s)
        if not ok then return nil, tostring(res) end
        return res
    end,
    encode = function(t, opts)
        return encode_value(t, opts and opts.pretty, 0)
    end,
    array = function(t) return setmetatable(t or {}, ARRAY_MT) end,
}

-- ── util ────────────────────────────────────────────────────────────────────
package.loaded["util"] = {
    readFromFile = function(path, mode)
        local f, err = io.open(path, mode or "rb")
        if not f then return nil, err end
        local s = f:read("*a")
        f:close()
        return s
    end,
    writeToFile = function(data, path)
        local f, err = io.open(path, "wb")
        if not f then return nil, err end
        f:write(data)
        f:close()
        return true
    end,
}

package.loaded["ffi/util"] = {
    template = function(str, ...)
        local args = { ... }
        return (str:gsub("%%(%d+)", function(n) return tostring(args[tonumber(n)]) end))
    end,
}

local silent = function() end
package.loaded["logger"] = os.getenv("DEBUG") and {
    dbg = print, info = print, warn = print, err = print,
} or { dbg = silent, info = silent, warn = silent, err = silent }

package.loaded["gettext"] = function(s) return s end
