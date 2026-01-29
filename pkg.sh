#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[*] $1"
}

warn() {
  echo "[!] $1"
}

error() {
  echo "[✗] $1"
  exit 1
}

need_path() {
  [ -d "$1" ] || error "No existe: $1"
}

pkg_name() {
  basename "$(realpath "$1")"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"

  if [ -e "$src" ]; then
    cp -r "$src" "$dst"
  else
    warn "No existe $src (omitido)"
  fi
}

# -------------------------------------------------
# pkg dirs <path>
# -------------------------------------------------
cmd_dirs() {
  local SRC="$1"
  need_path "$SRC"

  local NAME
  NAME=$(pkg_name "$SRC")
  local WIN="${NAME}-win"

  log "Reorganizando $NAME"

  # -------- WINDOWS --------
  log "Preparando $WIN"
  rm -rf "$WIN"
  mkdir -p "$WIN/bin" "$WIN/include"

  copy_if_exists "$SRC/bin/win/." "$WIN/bin/"
  copy_if_exists "$SRC/include/." "$WIN/include/"

  if [ -f "$SRC/${NAME}.wxs" ]; then
    cp "$SRC/${NAME}.wxs" "$WIN/"
  else
    error "No se encontró ${NAME}.wxs"
  fi

  # -------- DEBIAN --------
  log "Preparando estructura Debian"
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
  [ -d "$SRC/usr" ] || error "Falta usr/ (ejecuta pkg dirs)"

  log "Compilando ${NAME}.deb"
  dpkg-deb -b "$SRC" "${NAME}.deb"
  log "${NAME}.deb generado"
}

cmd_compile_rpm() {
  local SRC="$1"
  local NAME
  NAME=$(pkg_name "$SRC")

  [ -f "${NAME}.deb" ] || error "Falta ${NAME}.deb (ejecuta pkg compile deb $SRC)"

  log "Convirtiendo ${NAME}.deb → RPM con alien"
  sudo alien -r "${NAME}.deb"

  # Encontrar el rpm generado
  local RPM_FILE
  RPM_FILE=$(ls "${NAME}-"*.rpm 2>/dev/null | head -n 1) \
    || error "Alien no generó ningún .rpm"

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

  local NAME
  NAME=$(pkg_name "$SRC")
  local WIN="${NAME}-win"
  local WXS="$WIN/${NAME}.wxs"

  [ -f "$WXS" ] || error "No existe $WXS (ejecuta pkg dirs)"

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
    case "${2:-}" in
      deb) cmd_compile_deb "${3:-}" ;;
      rpm) cmd_compile_rpm "${3:-}" ;;
      win) cmd_compile_win "${3:-}" ;;
      *) error "Uso: pkg compile {deb|win|rpm} <path>" ;;
    esac
    ;;
  *)
    echo "Uso:"
    echo "  pkg dirs <path>"
    echo "  pkg compile deb <path>"
    echo "  pkg compile win <path>"
    exit 1
    ;;
esac
