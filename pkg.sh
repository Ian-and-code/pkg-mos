#!/usr/bin/env bash
set -e

CMD="$1"
SUBCMD="$2"
PATH_IN="$3"

error() {
  echo "[✗] $1"
  exit 1
}

need_path() {
  [ -z "$PATH_IN" ] && error "Falta <path>"
  [ ! -d "$PATH_IN" ] && error "No existe: $PATH_IN"
}

pkg_name() {
  basename "$(realpath "$PATH_IN")"
}

# -------------------------------------------------
# pkg dirs <path>
# -------------------------------------------------
cmd_dirs() {
  need_path
  NAME=$(pkg_name)

  DEB="${NAME}-deb"
  WIN="${NAME}-win"

  echo "[*] Generando estructuras desde $PATH_IN"

  rm -rf "$DEB" "$WIN"

  # -------- DEB --------
  mkdir -p "$DEB/DEBIAN"
  mkdir -p "$DEB/usr/bin"
  mkdir -p "$DEB/usr/include/$NAME"

  cp "$PATH_IN/debian/control" "$DEB/DEBIAN/control"

  cp -r "$PATH_IN/bin/linux/"* "$DEB/usr/bin/" 2>/dev/null || true
  cp -r "$PATH_IN/include/"* "$DEB/usr/include/$NAME/" 2>/dev/null || true

  chmod 755 "$DEB/usr/bin/"* 2>/dev/null || true
  chmod 644 "$DEB/DEBIAN/control"

  # -------- WIN --------
  mkdir -p "$WIN/bin"
  mkdir -p "$WIN/include"

  cp -r "$PATH_IN/bin/win/"* "$WIN/bin/" 2>/dev/null || true
  cp -r "$PATH_IN/include/"* "$WIN/include/" 2>/dev/null || true
  cp "$PATH_IN/win.wxs" "$WIN/"

  echo "[✓] Generado:"
  echo "  - $DEB"
  echo "  - $WIN"
}

# -------------------------------------------------
# pkg compile deb <path>
# -------------------------------------------------
cmd_compile_deb() {
  need_path
  NAME=$(pkg_name)
  DEB="${NAME}-deb"

  [ ! -d "$DEB/DEBIAN" ] && error "No existe $DEB (ejecuta pkg dirs primero)"

  echo "[*] Compilando $DEB.deb"
  dpkg-deb -b "$DEB"
  echo "[✓] $DEB.deb generado"
}

# -------------------------------------------------
# pkg compile win <path>
# -------------------------------------------------
cmd_compile_win() {
  need_path
  NAME=$(pkg_name)
  WIN="${NAME}-win"
  WXS="$WIN/win.wxs"

  [ ! -f "$WXS" ] && error "No existe $WXS (ejecuta pkg dirs primero)"

  echo "[*] Compilando $NAME.msi con wixl"
  (cd "$WIN" && wixl win.wxs -o "../$NAME.msi")
  echo "[✓] $NAME.msi generado"
}

# -------------------------------------------------
# Dispatch
# -------------------------------------------------
case "$CMD" in
  dirs)
    cmd_dirs
    ;;
  compile)
    case "$SUBCMD" in
      deb) cmd_compile_deb ;;
      win) cmd_compile_win ;;
      *) error "Uso: pkg compile {deb|win} <path>" ;;
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
