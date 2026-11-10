-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Los textos salen de dndsheet/i18n (se resuelve el idioma al cargar). PluginLoader agrega la carpeta
-- del plugin a package.path antes de leer este archivo (frontend/pluginloader.lua:242,253); el pcall es solo un resguardo.
local ok, I18n = pcall(require, "dndsheet/i18n")
local okv, version = pcall(require, "dndsheet/version")
return {
    fullname = ok and I18n.T("app.name") or "dndsheet (character sheet)",
    description = (ok and I18n.T("app.description") or "Opens .dnd files (JSON) as 5e-compatible character sheets.")
        .. (okv and ("\nv" .. version) or ""),
}
