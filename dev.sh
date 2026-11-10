#!/usr/bin/env bash
# dev.sh · lint + pruebas + lanzador del emulador para dndsheet.koplugin
#
# Uso (desde WSL, en la raíz del proyecto):
#   ./dev.sh          luacheck + pruebas (luajit tests/run.lua, si existe)
#   ./dev.sh run      lo anterior y, si todo pasa, abre el emulador (1264x1680, 300 ppp)
#   ./dev.sh emu      abre el emulador sin pasar por lint ni pruebas
#
# Variables opcionales:
#   KOREADER_DIR   carpeta del clon compilado de KOReader (por defecto ~/koreader)
#   EMU_ESCALA     porcentaje del tamaño real del Paperwhite (por defecto 100).
#                  Ej.: EMU_ESCALA=50 ./dev.sh run  -> ventana 632x840 a 150 ppp.
#                  Ancho, alto y ppp se reducen juntos: la interfaz se ve igual, más chica.

set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Dos disposiciones: repo de desarrollo (plugin en dndsheet.koplugin/) o repo público (el plugin es la raíz)
if [ -d "$RAIZ/dndsheet.koplugin" ]; then PLUGIN="$RAIZ/dndsheet.koplugin"; else PLUGIN="$RAIZ"; fi
if [ -f "$RAIZ/.luacheckrc" ]; then
    LUACHECKRC="$RAIZ/.luacheckrc"
elif [ -f "$RAIZ/tools/publicar/luacheckrc" ]; then
    LUACHECKRC="$RAIZ/tools/publicar/luacheckrc"
else
    LUACHECKRC="$RAIZ/koreader-v2026.07.1/.luacheckrc"
fi
KOREADER_DIR="${KOREADER_DIR:-$HOME/koreader}"

# Medidas del Kindle Paperwhite 12a gen, ajustadas por EMU_ESCALA (porcentaje)
EMU_ESCALA="${EMU_ESCALA:-100}"
EMU_W=$((1264 * EMU_ESCALA / 100))
EMU_H=$((1680 * EMU_ESCALA / 100))
EMU_DPI=$((300 * EMU_ESCALA / 100))

fallos=0

mensaje() { printf '\n== %s ==\n' "$1"; }
error()   { printf 'ERROR: %s\n' "$1" >&2; }

# ── Herramientas ────────────────────────────────────────────────────────────
verificar_herramientas() {
    mensaje "Herramientas"
    local faltan=0
    for h in luajit luacheck; do
        if command -v "$h" >/dev/null 2>&1; then
            printf '  %-9s OK  (%s)\n' "$h" "$(command -v "$h")"
        else
            error "falta '$h' (sudo apt install luajit lua-check)"
            faltan=1
        fi
    done
    if command -v luajit >/dev/null 2>&1; then
        if luajit -e 'require("cjson")' >/dev/null 2>&1; then
            printf '  %-9s OK\n' "lua-cjson"
        else
            error "falta lua-cjson (sudo apt install lua-cjson), lo necesitan las pruebas"
            faltan=1
        fi
    fi
    if [ ! -f "$LUACHECKRC" ]; then
        error "no encuentro $LUACHECKRC"
        faltan=1
    fi
    return $faltan
}

# ── Lint ────────────────────────────────────────────────────────────────────
correr_lint() {
    mensaje "luacheck"
    if [ ! -d "$PLUGIN" ]; then
        error "no existe $PLUGIN"
        return 1
    fi
    luacheck --config "$LUACHECKRC" "$PLUGIN"
}

# ── Pruebas ─────────────────────────────────────────────────────────────────
correr_pruebas() {
    mensaje "Pruebas"
    if [ ! -f "$PLUGIN/tests/run.lua" ]; then
        echo "  (todavía no hay tests/run.lua: se omiten)"
        return 0
    fi
    ( cd "$PLUGIN" && luajit tests/run.lua )
}

# ── Emulador ────────────────────────────────────────────────────────────────
lanzar_emulador() {
    mensaje "Emulador"
    if [ ! -x "$KOREADER_DIR/kodev" ]; then
        error "no encuentro $KOREADER_DIR/kodev (definí KOREADER_DIR)"
        return 1
    fi
    # Aviso si el plugin no está registrado en extra_plugin_paths
    local ajustes
    ajustes="$(ls "$KOREADER_DIR"/koreader-emulator-*/koreader/settings.reader.lua 2>/dev/null | head -n 1)"
    if [ -n "$ajustes" ] && ! grep -q "extra_plugin_paths" "$ajustes"; then
        echo "  AVISO: $ajustes no tiene extra_plugin_paths; el plugin no se va a cargar."
    fi
    echo "  Abriendo ${EMU_W}x${EMU_H} a ${EMU_DPI} ppp (cerralo con el menú de KOReader o Ctrl+C aquí)"
    cd "$KOREADER_DIR" && ./kodev run -W "$EMU_W" -H "$EMU_H" -D "$EMU_DPI"
}

# ── Principal ───────────────────────────────────────────────────────────────
comando="${1:-check}"

case "$comando" in
    emu)
        lanzar_emulador
        exit $?
        ;;
    check|run)
        verificar_herramientas || exit 2
        correr_lint    || fallos=1
        correr_pruebas || fallos=1
        mensaje "Resultado"
        if [ "$fallos" -ne 0 ]; then
            error "hay fallas (ver arriba)"
            exit 1
        fi
        echo "  Todo OK"
        if [ "$comando" = "run" ]; then
            lanzar_emulador
            exit $?
        fi
        ;;
    -h|--help|help)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        error "comando desconocido: $comando (usá: check | run | emu)"
        exit 2
        ;;
esac
