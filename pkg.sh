#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "Falta $1"; exit 1; }; }

need tomlq
need dpkg-deb
need wixl

PKG_TOML="$1"
[ -f "$PKG_TOML" ] || { echo "Uso: pkg.sh <pkg.toml>"; exit 1; }

name=$(tomlq -r .package.name "$PKG_TOML")

# ---------------- LINUX ----------------
echo "[*] Generando Debian"

rm -rf "$name"
mkdir -p "$name/DEBIAN" "$name/usr/bin" "$name/usr/include/$name" "$name/usr/lib/$name"

cat > "$name/DEBIAN/control" <<EOF
Package: $name
Section: $(tomlq -r .linux.section "$PKG_TOML")
Priority: $(tomlq -r .linux.priority "$PKG_TOML")
Architecture: $(tomlq -r .package.arch "$PKG_TOML")
Depends: $(tomlq -r '.linux.depends | join(", ")' "$PKG_TOML")
Maintainer: $(tomlq -r .linux.maintainer "$PKG_TOML")
Description: $(tomlq -r .linux.description "$PKG_TOML")
EOF

cp -a bin/linux/. "$name/usr/bin/" 2>/dev/null || true
cp -a include/. "$name/usr/include/$name/" 2>/dev/null || true
cp -a lib/linux/. "$name/usr/lib/$name/" 2>/dev/null || true

chmod 755 "$name/usr/bin/"* 2>/dev/null || true

dpkg-deb -b "$name" "$name.deb"
echo "[✓] $name.deb"

# ---------------- WINDOWS ----------------
echo "[*] Generando MSI"

WIN="$name-win"
rm -rf "$WIN"
mkdir -p "$WIN/bin"

cp -a bin/win/. "$WIN/bin/"

GUID_PRODUCT=$(uuidgen)

cat > "$WIN/$name.wxs" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="$name"
           Manufacturer="$(tomlq -r .win.manufacturer "$PKG_TOML")"
           UpgradeCode="$GUID_PRODUCT">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine"/>

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="$name">
          <Directory Id="BIN" Name="bin">
EOF

while read -r exe; do
  id=$(basename "$exe" .exe)
  guid=$(uuidgen)
  cat >> "$WIN/$name.wxs" <<EOF
            <Component Id="$id" Guid="$guid">
              <File Source="bin/$exe" KeyPath="yes"/>
            </Component>
EOF
done < <(tomlq -r '.win.bins[]' "$PKG_TOML")

cat >> "$WIN/$name.wxs" <<EOF
          </Directory>
        </Directory>
      </Directory>
    </Directory>

    <Feature Id="Main" Level="1">
EOF

while read -r exe; do
  id=$(basename "$exe" .exe)
  echo "      <ComponentRef Id=\"$id\"/>" >> "$WIN/$name.wxs"
done < <(tomlq -r '.win.bins[]' "$PKG_TOML")

cat >> "$WIN/$name.wxs" <<EOF
    </Feature>
  </Product>
</Wix>
EOF

(cd "$WIN" && wixl "$name.wxs" -o "../$name.msi")
echo "[✓] $name.msi"

# ---------------- RPM ----------------
if command -v alien >/dev/null; then
  echo "[*] Generando RPM"
  sudo alien -r "$name.deb"
  mv ./*.rpm "$name.rpm"
  echo "[✓] $name.rpm"
fi
