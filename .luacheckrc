-- Configuración de luacheck de dndsheet (basada en la de KOReader).
unused_args = false
std = "luajit"
-- ignore implicit self
self = false

globals = {
    "G_reader_settings",
    "G_defaults",
    "table.pack",
    "table.unpack",
}

read_globals = {
    "_ENV",
}

-- busted en las specs de interfaz
files["tests/spec/*"].std = "+busted"
files["tests/spec/*"].globals = {
    "package",
    "disable_plugins",
    "load_plugin",
    "fastforward_ui_events",
    "screenshot",
}

ignore = {
    "211/__*", -- Unused local variable
    "231/__",  -- Local variable is set but never accessed
    "631",     -- Line is too long
    "dummy",
}
