#!/bin/sh
# Empaqueta Didacta para macOS: un DMG para instalar y un ZIP para actualizar.
#
# **Dos artefactos y no uno**, que es la decisión que hay detrás de este
# script. Son el mismo `.app`, empaquetado dos veces, porque las dos cosas que
# hay que hacer con él son distintas:
#
# * el **DMG** es para una persona que todavía no tiene Didacta. Se abre, se
#   arrastra a Aplicaciones y se acabó. Es lo que espera cualquiera en macOS;
# * el **ZIP** es para el actualizador. Descomprimir un ZIP y mover una
#   carpeta son dos órdenes; montar un DMG, copiar y desmontarlo desde el
#   propio programa que se está sustituyendo son tres formas más de fallar sin
#   ganar nada. Es lo que hace Sparkle, y por lo mismo.
#
# El ZIP se hace con `ditto` y no con `zip`: conserva los atributos extendidos
# y la firma del paquete. Un `.app` firmado que se comprime con `zip` y se
# descomprime con `unzip` deja de validar contra Gatekeeper.
#
# Uso:
#   packaging/macos/package.sh <Didacta.app> <versión> <carpeta de salida>
set -eu

app=${1:?falta la ruta del .app}
version=${2:?falta la versión}
out=${3:?falta la carpeta de salida}

[ -d "$app" ] || { echo "no existe $app" >&2; exit 1; }
[ -x "$app/Contents/MacOS/Didacta" ] || {
  echo "$app no tiene el ejecutable dentro" >&2
  exit 1
}

mkdir -p "$out"
out=$(cd "$out" && pwd)
app=$(cd "$(dirname "$app")" && pwd)/$(basename "$app")

dmg="$out/Didacta-$version-macos-universal.dmg"
zip="$out/Didacta-$version-macos-universal.zip"

# ---------------------------------------------------------------- el ZIP ---

# `--keepParent` para que dentro haya `Didacta.app` y no su contenido suelto:
# el actualizador busca un `.app` en la raíz de lo que extrae.
rm -f "$zip"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$app" "$zip"
echo "ZIP  $(du -h "$zip" | cut -f1)  $zip"

# ---------------------------------------------------------------- el DMG ---

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

/usr/bin/ditto "$app" "$stage/Didacta.app"
# El enlace a Aplicaciones: es lo que convierte la ventana del DMG en «arrastra
# esto ahí» sin necesidad de explicarlo.
ln -s /Applications "$stage/Aplicaciones"

rm -f "$dmg"
# UDZO: comprimido y de solo lectura, que es lo que se reparte. `-ov` para que
# una segunda ejecución no falle por encontrarse el de antes.
hdiutil create \
  -volname "Didacta $version" \
  -srcfolder "$stage" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  -quiet \
  "$dmg"

echo "DMG  $(du -h "$dmg" | cut -f1)  $dmg"
