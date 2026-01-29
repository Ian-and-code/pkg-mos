#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0

# -------------------------------------------------
# Utils
# -------------------------------------------------
log()   { echo "[*] $1"; }
warn()  { echo "[!] $1"; }
error() { echo "[✗] $1"; exit 1; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry] $*"
  else
    "$@"
  fi
}

need() {
  command -v "$1" >/dev/null || error "$1 no instalado"
}

pkg_name() {
  yq e '.name' "$1"
}

pkg_version() {
  yq e '.version' "$1"
}

# -------------------------------------------------
# YAML → DEBIAN/control
# -------------------------------------------------
ycontrol() {
  local yaml="$1"
  local out="$2"

  cat > "$out" <<EOF
Package: $(yq e '.name' "$yaml")
Version: $(yq e '.version' "$yaml")
Section: devel
Priority: optional
Architecture: $(yq e '.arch' "$yaml")
Maintainer: $(yq e '.maintainer' "$yaml")
Description: $(yq e '.description' "$yaml")
EOF
}

# -------------------------------------------------
# YAML → WXS
# -------------------------------------------------
ywxs() {
  local yaml="$1"
  local out="$2"

  local NAME VERSION
  NAME=$(yq e '.name' "$yaml")
  VERSION=$(yq e '.version' "$yaml")

  cat > "$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
<Product Id="*" Name="$NAME" Version="$VERSION"
 Manufacturer="$NAME" Language="1033"
 UpgradeCode="$(uuidgen)">
<Package InstallerVersion="500" Compressed="yes"/>
<Directory Id="TARGETDIR" Name="SourceDir">
 <Directory Id="ProgramFilesFolder">
  <Directory Id="INSTALLFOLDER" Name="$NAME">
   <Directory Id="BIN" Name="bin">
EOF

  yq e '.files.bin[]' "$yaml" | while read -r entry; do
    ID=$(yq e '.id' <<<"$entry")
    SRC=$(yq e '.name' <<<"$entry")
    GUID=$(uuidgen)

    cat >> "$out" <<EOF
    <Component Id="CMP_$ID" Guid="$GUID">
      <File Id="$ID" Source="bin/$SRC" KeyPath="yes"/>
    </Component>
EOF
  done

  cat >> "$out" <<EOF
   </Directory>
  </Directory>
 </Directory>
</Directory>
<Feature Id="Main" Level="1">
EOF

  yq e '.files.bin[].id' "$yaml" | while read -r id; do
    echo "<ComponentRef Id=\"CMP_$id\"/>" >> "$out"
  done

  cat >> "$out" <<EOF
</Feature>
</Product>
</Wix>
EOF
}

# -------------------------------------------------
# dirs
# -------------------------------------------------
cmd_dirs() {
  local SRC="$1"
  local YAML="$SRC/package.yaml"

  [ -f "$YAML" ] || error "package.yaml faltante"

  local NAME
  NAME=$(pkg_name "$YAML")

  log "Preparando estructuras para $NAME"

  # Debian
  run mkdir -p "$SRC/DEBIAN" "$SRC/usr/bin"
  run ycontrol "$YAML" "$SRC/DEBIAN/control"
  run cp -a "$SRC/bin/linux/." "$SRC/usr/bin/" 2>/dev/null || true

  # Windows
  local WIN="${NAME}-win"
  run rm -rf "$WIN"
  run mkdir -p "$WIN/bin"
  run cp -a "$SRC/bin/win/." "$WIN/bin/" 2>/dev/null || true
  run ywxs "$YAML" "$WIN/$NAME.wxs"

  log "OK"
}

# -------------------------------------------------
# compile deb
# -------------------------------------------------
cmd_deb() {
  local SRC="$1"
  local YAML="$SRC/package.yaml"
  local NAME
  NAME=$(pkg_name "$YAML")

  run dpkg-deb -b "$SRC" "$NAME.deb"
}

# -------------------------------------------------
# compile rpm
# -------------------------------------------------
cmd_rpm() {
  local YAML="$1/package.yaml"
  local NAME
  NAME=$(pkg_name "$YAML")

  run rm -f *.rpm
  run sudo alien -r "$NAME.deb"
  run mv *.rpm "$NAME.rpm"
}

# -------------------------------------------------
# compile win
# -------------------------------------------------
cmd_win() {
  local YAML="$1/package.yaml"
  local NAME
  NAME=$(pkg_name "$YAML")

  run wixl "$NAME-win/$NAME.wxs" -o "$NAME.msi"
}

# -------------------------------------------------
# clean
# -------------------------------------------------
cmd_clean() {
  run rm -rf *.deb *.rpm *.msi *-win usr DEBIAN
}

# -------------------------------------------------
# main
# -------------------------------------------------
need yq
need uuidgen

while [[ "${1:-}" == "--dry-run" ]]; do
  DRY_RUN=1
  shift
done

case "${1:-}" in
  dirs)   cmd_dirs "$2" ;;
  deb)    cmd_deb "$2" ;;
  rpm)    cmd_rpm "$2" ;;
  win)    cmd_win "$2" ;;
  all)
    cmd_dirs "$2"
    cmd_deb "$2"
    cmd_rpm "$2"
    cmd_win "$2"
    ;;
  clean)  cmd_clean ;;
  *)
    echo "Uso:"
    echo "  pkg [--dry-run] dirs <path>"
    echo "  pkg deb|rpm|win <path>"
    echo "  pkg all <path>"
    echo "  pkg clean"
    ;;
esac
