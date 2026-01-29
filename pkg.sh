#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Utilidades
# -------------------------------------------------
log()   { echo "[*] $1"; }
warn()  { echo "[!] $1"; }
error() { echo "[✗] $1"; exit 1; }
need_path() { [ -d "$1" ] || error "No existe: $1"; }
pkg_name() { basename "$(realpath "$1")"; }
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then cp -a "$src" "$dst"; else warn "No existe $src (omitido)"; fi
}

# -------------------------------------------------
# pkg dirs <path>
# -------------------------------------------------
cmd_dirs() {
  local SRC="$1"
  need_path "$SRC"
  local NAME=$(pkg_name "$SRC")
  WIN="${NAME}-win"

  log "Reorganizando paquete: $NAME"

  # -------- WINDOWS --------
  WIN="${NAME}-win"
  log "Preparando estructura Windows: $WIN/"
  rm -rf "$WIN"
  mkdir -p "$WIN/bin" "$WIN/include"

  copy_if_exists "$SRC/bin/win/." "$WIN/bin/"
  copy_if_exists "$SRC/include/." "$WIN/include/"

  # Si hay .wxs lo copia, sino nada
  if [ -f "$SRC/${NAME}.wxs" ]; then
    cp "$SRC/${NAME}.wxs" "$WIN/"
  fi

  # -------- DEBIAN --------
  log "Preparando estructura Debian en $SRC/usr/"
  mkdir -p "$SRC/usr/bin" "$SRC/usr/include"

  copy_if_exists "$SRC/bin/linux/." "$SRC/usr/bin/"
  copy_if_exists "$SRC/include/." "$SRC/usr/include/"

  chmod 755 "$SRC/usr/bin/"* 2>/dev/null || true
  chmod 644 "$SRC/DEBIAN/control" 2>/dev/null || true

  log "Listo"
  echo "  - Windows: $WIN/"
  echo "  - Debian:  $SRC/usr/"
}

# -------------------------------------------------
# pkg compile deb <path>
# -------------------------------------------------
cmd_compile_deb() {
  local SRC="$1"
  need_path "$SRC"
  local NAME
  NAME=$(pkg_name "$SRC")
  [ -d "$SRC/DEBIAN" ] || error "Falta DEBIAN/"
  [ -d "$SRC/usr" ] || error "Falta usr/ (ejecuta pkg dirs <path>)"

  log "Compilando ${NAME}.deb"
  dpkg-deb -b "$SRC" "${NAME}.deb"
  log "${NAME}.deb generado"
}

# -------------------------------------------------
# pkg compile rpm <path>
# -------------------------------------------------
cmd_compile_rpm() {
  local SRC="$1"
  local NAME
  NAME=$(pkg_name "$SRC")
  [ -f "${NAME}.deb" ] || error "Falta ${NAME}.deb (ejecuta pkg compile deb $SRC)"

  log "Convirtiendo ${NAME}.deb → RPM con alien"
  rm -f ./*.rpm
  sudo alien -r "${NAME}.deb"

  local RPM_FILE
  RPM_FILE=$(find . -maxdepth 1 -type f -name "*.rpm" -printf "%T@ %p\n" | sort -nr | head -n1 | cut -d' ' -f2)
  [ -n "$RPM_FILE" ] || error "Alien no generó ningún .rpm"

  log "Renombrando $(basename "$RPM_FILE") → ${NAME}.rpm"
  mv "$RPM_FILE" "${NAME}.rpm"
  log "${NAME}.rpm generado"
}

# -------------------------------------------------
# pkg compile win <path>
# -------------------------------------------------
cmd_compile_win() {
  local SRC="$1"
  need_path "$SRC"
  local NAME=$(pkg_name "$SRC")
  WIN="${NAME}-win"
  local WXS="$WIN/${NAME}.wxs"
  [ -f "$WXS" ] || error "No existe $WXS (ejecuta pkg dirs <path>)"

  log "Compilando ${NAME}.msi"
  (cd "$WIN" && wixl "${NAME}.wxs" -o "../${NAME}.msi")
  log "${NAME}.msi generado"
}

# -------------------------------------------------
# Dispatch
# -------------------------------------------------
case "${1:-}" in
  dirs)
    [ -n "${2:-}" ] || error "Uso: pkg dirs <path>"
    cmd_dirs "$2"
    ;;
  compile)
    [ -n "${3:-}" ] || error "Uso: pkg compile {deb|rpm|win} <path>"
    case "$2" in
      deb) cmd_compile_deb "$3" ;;
      rpm) cmd_compile_rpm "$3" ;;
      win) cmd_compile_win "$3" ;;
      *) error "Uso: pkg compile {deb|rpm|win} <path>" ;;
    esac
    ;;
  all)
    [ -n "${2:-}" ] || error "Uso: pkg all <path>"
    cmd_dirs "$2"
    cmd_compile_deb "$2"
    cmd_compile_rpm "$2"
    cmd_compile_win "$2"
    ;;
  *)
    echo "Uso:"
    echo "  pkg dirs <path>"
    echo "  pkg compile deb <path>"
    echo "  pkg compile rpm <path>"
    echo "  pkg compile win <path>"
    echo "  pkg all <path>"
    exit 1
    ;;
esac
