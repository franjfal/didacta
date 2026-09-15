#!/bin/sh
# La prueba de extremo a extremo de la actualización, en macOS.
#
# Hace de verdad el recorrido entero contra el release publicado:
#
#   1. prepara una **copia** de la Didacta instalada, en una carpeta temporal;
#   2. comprueba el acceso al repositorio privado, y que un token inválido no
#      pasa;
#   3. lee el manifiesto del último release;
#   4. descarga el artefacto por su `assetId`, con el token;
#   5. comprueba el SHA-256 --si no cuadra, aquí se acaba--;
#   6. extrae, valida el paquete y escribe el script de sustitución;
#   7. deja que el script sustituya la copia y la relance;
#   8. comprueba que la copia **es** la versión nueva y que arranca.
#
# **No toca la Didacta que estés usando.** Todo pasa sobre la copia.
#
# Lo único que no cubre es pulsar el botón en la ventana, que necesita a una
# persona delante; ese camino está cubierto por `app/test/update_ui_test.dart`
# contra el mismo servicio.
#
# Uso:
#   DIDACTA_E2E_TOKEN=$(gh auth token) \
#     packaging/e2e-macos.sh <Didacta.app que hace de versión instalada>
set -eu

[ "$(uname)" = "Darwin" ] || { echo "esto es la prueba de macOS" >&2; exit 1; }

origen=${1:?falta el .app que hace de versión instalada}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

: "${DIDACTA_E2E_TOKEN:?falta DIDACTA_E2E_TOKEN (prueba: gh auth token)}"

trabajo=$(mktemp -d)
copia="$trabajo/Didacta.app"
marca="$trabajo/script"

limpiar() {
  # Cerrar la copia si se quedó abierta, y borrar lo temporal.
  pkill -f "$copia/Contents/MacOS/Didacta" 2>/dev/null || true
  rm -rf "$trabajo"
}
trap limpiar EXIT

echo "== 1. preparando la copia"
/usr/bin/ditto "$origen" "$copia"
antes=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$copia/Contents/Info.plist")
echo "   la copia dice ser $antes"
echo "   en $copia"

echo
echo "== 2-6. acceso, manifiesto, descarga, checksum y preparación"
cd "$root/app"
DIDACTA_E2E_APP="$copia" \
DIDACTA_E2E_SCRIPT="$marca" \
  flutter test tool/e2e_update.dart --reporter expanded
cd "$root"

script=$(cat "$marca")
[ -x "$script" ] || { echo "el script no quedó ejecutable: $script" >&2; exit 1; }

echo
echo "== 7. sustituyendo"
# El script espera a que termine **su** proceso padre, que era el de
# `flutter test` y ya no existe: por eso este paso va aquí fuera y no dentro
# del test. Es exactamente lo que pasa de verdad, donde quien termina es
# Didacta.
sh "$script" >/dev/null 2>&1 &

# Esperar a que la copia cambie de versión, con tope.
i=0
while [ "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
           "$copia/Contents/Info.plist" 2>/dev/null || echo "$antes")" = "$antes" ]; do
  i=$((i + 1))
  if [ $i -gt 120 ]; then
    echo "   la copia sigue siendo $antes después de 60 s" >&2
    exit 1
  fi
  sleep 0.5
done

despues=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$copia/Contents/Info.plist")
echo "   $antes → $despues"

# Y que no quede la copia de seguridad tirada: solo se borra cuando la
# sustitución sale bien, así que encontrarla aquí significaría que falló.
if [ -e "$copia.didacta-anterior" ]; then
  echo "   queda la copia de seguridad: la sustitución no terminó" >&2
  exit 1
fi
echo "   la copia de seguridad se limpió, así que terminó bien"

echo
echo "== 8. y arranca"
# `-n` para forzar una instancia nueva: hay otra Didacta con el mismo
# identificador instalada, y sin esto macOS activaría aquella en lugar de
# abrir la copia.
open -n "$copia"
i=0
until pgrep -f "$copia/Contents/MacOS/Didacta" >/dev/null 2>&1; do
  i=$((i + 1))
  [ $i -gt 40 ] && { echo "   no arrancó" >&2; exit 1; }
  sleep 0.5
done
pid=$(pgrep -f "$copia/Contents/MacOS/Didacta" | head -1)
echo "   corriendo, pid $pid, desde $copia"

# Que el proceso que corre sea el de la versión nueva y no otro.
#
# Las dos rutas se resuelven antes de compararlas: en macOS `/var` es un
# enlace a `/private/var`, así que la ruta del proceso y la de `mktemp -d` son
# la misma carpeta escrita de dos formas. Comparándolas tal cual, esto fallaba
# con la actualización ya hecha.
ruta=$(ps -o comm= -p "$pid")
real_proc=$(cd "$(dirname "$ruta")" && pwd -P)
real_copia=$(cd "$copia/Contents/MacOS" && pwd -P)
if [ "$real_proc" = "$real_copia" ]; then
  echo "   y es la copia, no otra Didacta"
else
  echo "   el proceso no es el de la copia:" >&2
  echo "     corriendo: $real_proc" >&2
  echo "     esperado:  $real_copia" >&2
  exit 1
fi

# Y que lo que corre diga ser la versión nueva.
corriendo=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$copia/Contents/Info.plist")
[ "$corriendo" = "$despues" ] || {
  echo "   lo que corre dice ser $corriendo y no $despues" >&2
  exit 1
}
echo "   y dice ser la $corriendo"

echo
echo "== bien: $antes → $despues, descargada, verificada, instalada y en marcha"
