#!/bin/sh
# Notariza un DMG o un ZIP y le grapa el ticket.
#
# Notarizar es mandarle el paquete a Apple para que lo revise y devuelva un
# ticket. **Grapar** ese ticket al fichero es lo que permite que la aplicación
# se abra en una máquina sin conexión: sin grapar, Gatekeeper tiene que
# preguntarle a Apple cada vez, y la primera apertura en una red mala tarda o
# falla.
#
# Sin credenciales, no falla: lo dice y sigue. Un DMG sin notarizar se abre
# con el aviso que le corresponde, y eso es preferible a no poder publicar.
#
# Uso:
#   packaging/macos/notarize.sh <fichero.dmg|fichero.zip>
set -eu

target=${1:?falta el fichero}

if [ -z "${MACOS_NOTARY_APPLE_ID:-}" ] ||
   [ -z "${MACOS_NOTARY_TEAM_ID:-}" ] ||
   [ -z "${MACOS_NOTARY_PASSWORD:-}" ]; then
  echo "· Sin credenciales de notarización: $target se publica sin notarizar."
  exit 0
fi

echo "· Notarizando $(basename "$target")…"

# `--wait` para que el paso del workflow falle si Apple lo rechaza, en lugar
# de publicar algo que nadie va a poder abrir. Tarda entre uno y quince
# minutos; el `--timeout` evita que un cuelgue se lleve la hora entera.
xcrun notarytool submit "$target" \
  --apple-id "$MACOS_NOTARY_APPLE_ID" \
  --team-id "$MACOS_NOTARY_TEAM_ID" \
  --password "$MACOS_NOTARY_PASSWORD" \
  --wait \
  --timeout 30m

# Grapar. Solo funciona sobre un DMG o un `.app`, no sobre un ZIP: un ZIP no
# tiene dónde guardar el ticket. El ZIP del actualizador no lo necesita,
# porque lo que se comprueba allí es la firma del `.app` que lleva dentro.
case "$target" in
  *.dmg)
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
    echo "· Notarizado y grapado."
    ;;
  *)
    echo "· Notarizado. Un ZIP no admite grapado; el .app de dentro ya va"
    echo "  firmado y su ticket se resuelve en línea la primera vez."
    ;;
esac
