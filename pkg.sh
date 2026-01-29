#!/usr/bin/env bash
set -euo pipefail

# =================================================
# YAML → WXS
# =================================================
ywxs() {
  local yaml="$1"
  local out="$2"

  command -v yq >/dev/null || error "yq no instalado"
  command -v uuidgen >/dev/null || error "uuidgen no disponible"

  local NAME VERSION
  NAME=$(yq e '.name' "$yaml")
  VERSION=$(yq e '.version' "$yaml")

  [ "$NAME" != "null" ] || error "name faltante en $yaml"
  [ "$VERSION" != "null" ] || error "version faltante en $yaml"

  cat > "$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="$NAME"
    Language="1033"
    Version="$VERSION"
    Manufacturer="$NAME"
    UpgradeCode="$(uuidgen)">

    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine"/>

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="$NAME">
          <Directory Id="BIN" Name="bin">
EOF

  yq e '.files.bin[]' "$yaml" | while read -r entry; do
    local SRC ID GUID
    SRC=$(yq e '.name' <<< "$entry")
    ID=$(yq e '.id' <<< "$entry")
    GUID=$(uuidgen)

    cat >> "$out" <<EOF
            <Component Id="CMP_$ID" Guid="$GUID">
              <File Id="$ID" Source="$SRC" KeyPath="yes"/>
            </Component>
EOF
  done

  cat >> "$out" <<EOF
          </Directory>
        </Directory>
      </Directory>
    </Directory>

    <Feature Id="MainFeature" Title="$NAME" Level="1">
EOF

  yq e '.files.bin[].id' "$yaml" | while read -r id; do
    echo "      <ComponentRef Id=\"CMP_$id\"/>" >> "$out"
  done

  cat >> "$out" <<EOF
    </Feature>
  </Product>
</Wix>
EOF
}

# =================================================
# Utilidades
# =================================================
log()   { echo "[*] $1"; }
warn()  { echo "[!] $1"; }
error() { echo "[✗] $1"; exit 1; }

need_path() {
  [ -d "$1" ] || error "No existe: $1"
}

pkg_name() {
  basename "$(realpath "$1")"
}

copy_if_exists() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    cp -a "$src" "$dst"
  else
    warn "No existe $src (omitido)"
  fi
}

# =================================================
# pkg dirs <path>
# =================================================
cmd_dirs() {
  local SRC="$1"
  need_path "$SRC"

  local NAME
  NAME=$(pkg_name "$SRC")
  local WIN="${NAME}-win"

  log "Reorganizando paquete: $NAME"

  # -------- WINDOWS --------
  rm -rf "$WIN"
  mkdir -p "$WIN/bin" "$WIN/include"

  copy_if_exists "$SRC/bin/win/." "$WIN/bin/"
  copy_if_exists "$SRC/include/." "$WIN/include/"

  if [ -f "$SRC/${NAME}.yaml" ]; then
    log "Generando WXS desde ${NAME}.yaml"
    ywxs "$SRC/${NAME}.yaml" "$WIN/${NAME}.wxs"
  else
    error "No se encontró ${NAME}.yaml"
  fi

  # -------- DEBIAN --------
  mkdir -p "$SRC/usr/bin" "$SRC/usr/include"

  copy_if_exists "$SRC/bin/linux/." "$SRC/usr/bin/"
  copy_if_exists "$SRC/include/." "$SRC/usr/include/"

  chmod 755 "$SRC/usr/bin/"* 2>/dev/null || true
  chmod 644 "$SRC/DEBIAN/control" 2>/dev/null || true

  log "Listo"
  echo "  - Windows: $WIN/"
  echo "  - Debian:  $SRC/usr/"
}

# =================================================
# pkg compile deb <path>
# =================================================
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

# =================================================
# pkg compile rpm <path>
# =================================================
cmd_compile_rpm() {
  local SRC="$1"
  local NAME
  NAME=$(pkg_name "$SRC")

  [ -f "${NAME}.deb" ] || error "Falta ${NAME}.deb"

  rm -f ./*.rpm
  log "Convirtiendo ${NAME}.deb → RPM"
  sudo alien -r "${NAME}.deb"

  local RPM
  RPM=$(ls -t *.rpm | head -n1)
  [ -n "$RPM" ] || error "Alien no generó RPM"

  mv "$RPM" "${NAME}.rpm"
  log "${NAME}.rpm generado"
}

# =================================================
# pkg compile win <path>
# =================================================
cmd_compile_win() {
  local SRC="$1"
  need_path "$SRC"

  local NAME
  NAME=$(pkg_name "$SRC")
  local WIN="${NAME}-win"

  [ -f "$WIN/${NAME}.wxs" ] || error "No existe ${NAME}.wxs"

  log "Compilando ${NAME}.msi"
  (cd "$WIN" && wixl "${NAME}.wxs" -o "../${NAME}.msi")
  log "${NAME}.msi generado"
}

# =================================================
# Dispatch
# =================================================
case "${1:-}" in
  dirs)
    cmd_dirs "${2:-}"
    ;;
  compile)
    case "${2:-}" in
      deb) cmd_compile_deb "${3:-}" ;;
      rpm) cmd_compile_rpm "${3:-}" ;;
      win) cmd_compile_win "${3:-}" ;;
      *) error "Uso: pkg compile {deb|rpm|win} <path>" ;;
    esac
    ;;
  all)
    cmd_dirs "${2:-}"
    cmd_compile_deb "${2:-}"
    cmd_compile_rpm "${2:-}"
    cmd_compile_win "${2:-}"
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
