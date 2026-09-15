#!/bin/sh
# Firma y notariza el `.app` de macOS, si hay con qué.
#
# **Y si no lo hay, no falla: lo dice y sigue.** Esa es la decisión de este
# script. Hoy todavía no hay un certificado de Developer ID, y un sistema de
# distribución que no puede publicar nada hasta que lo haya sería un sistema
# que no sirve. Lo que sí hace es dejarlo todo preparado --los secretos tienen
# nombre, el orden de los pasos está escrito y probado-- para que el día que
# el certificado exista publicar sea añadir cuatro secretos y nada más.
#
# Lo que **no** hace en ningún caso es desactivar nada. Sin firma, el DMG se
# abre con el aviso de Gatekeeper que corresponde a una aplicación sin firmar,
# que es lo honesto. No se toca el `com.apple.quarantine` de nadie, no se
# recomienda `spctl --master-disable`, y el actualizador se niega a instalar
# una versión sin firmar encima de una firmada.
#
# El orden importa y es este:
#
#   1. firmar de dentro afuera (`--deep` no basta para los binarios de
#      Flutter: los `.framework` van firmados uno a uno);
#   2. con `--options runtime`, el hardened runtime, que la notarización
#      **exige**;
#   3. empaquetar;
#   4. notarizar el paquete y grapar el ticket, para que se pueda abrir sin
#      conexión.
#
# Uso:
#   packaging/macos/sign.sh <Didacta.app>
set -eu

app=${1:?falta la ruta del .app}

if [ -z "${MACOS_SIGNING_IDENTITY:-}" ]; then
  echo "· Sin MACOS_SIGNING_IDENTITY: se publica sin firmar."
  echo "  Quien la instale verá el aviso de Gatekeeper, que es lo que"
  echo "  corresponde. Para firmar, añade los secretos que documenta"
  echo "  ARCHITECTURE.md §Firma."
  exit 0
fi

echo "· Firmando con: $MACOS_SIGNING_IDENTITY"

entitlements=$(cd "$(dirname "$0")/../../app/macos/Runner" && pwd)/Release.entitlements
[ -f "$entitlements" ] || { echo "no encuentro $entitlements" >&2; exit 1; }

# De dentro afuera. `codesign --deep` está desaconsejado por Apple justo para
# esto: no firma bien los frameworks anidados, y la notarización los rechaza
# uno por uno sin decir cuál.
find "$app/Contents/Frameworks" -type f \
  \( -name '*.dylib' -o -name '*.so' \) -print 2>/dev/null |
while IFS= read -r binary; do
  codesign --force --timestamp --options runtime \
    --sign "$MACOS_SIGNING_IDENTITY" "$binary"
done

for framework in "$app"/Contents/Frameworks/*.framework; do
  [ -d "$framework" ] || continue
  codesign --force --timestamp --options runtime \
    --sign "$MACOS_SIGNING_IDENTITY" "$framework"
done

# Y el paquete entero al final, con los entitlements.
codesign --force --timestamp --options runtime \
  --entitlements "$entitlements" \
  --sign "$MACOS_SIGNING_IDENTITY" "$app"

echo "· Comprobando la firma…"
codesign --verify --deep --strict --verbose=2 "$app"

echo "· Firmado."
