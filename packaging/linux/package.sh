#!/bin/sh
# Empaqueta Didacta para Linux como AppImage.
#
# AppImage y no `.deb` como formato principal, por lo que exige el
# actualizador: **un AppImage es un solo fichero**, así que actualizarlo es
# sustituir ese fichero con un `mv` --que en el mismo sistema de ficheros es
# atómico-- y volver a lanzarlo. Un `.deb` lo gobierna el gestor de paquetes,
# y escribirle los ficheros por debajo le rompe la base de datos: allí la
# actualización tendría que ser `apt`, que necesita administrador y un
# repositorio firmado que no existe.
#
# Y además no hay que instalar nada: se descarga, se marca ejecutable y se
# abre, en cualquier distribución razonablemente reciente.
#
# Uso:
#   packaging/linux/package.sh <carpeta del bundle> <versión> <salida>
set -eu

bundle=${1:?falta la carpeta del bundle}
version=${2:?falta la versión}
out=${3:?falta la carpeta de salida}

here=$(cd "$(dirname "$0")" && pwd)

[ -x "$bundle/didacta" ] || {
  echo "no encuentro el ejecutable en $bundle/didacta" >&2
  exit 1
}

mkdir -p "$out"
out=$(cd "$out" && pwd)

appdir=$(mktemp -d)/Didacta.AppDir
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/256x256/apps"

cp -a "$bundle"/. "$appdir/usr/bin/"

# El `.desktop` y el icono van dos veces: en la raíz del AppDir, que es donde
# los busca el runtime de AppImage, y en `usr/share`, que es donde los busca
# el escritorio si alguien integra la aplicación. Que falte cualquiera de las
# dos copias da un AppImage que arranca pero sale sin nombre y sin icono.
cp "$here/didacta.desktop" "$appdir/usr/share/applications/didacta.desktop"
cp "$here/didacta.desktop" "$appdir/didacta.desktop"

icon="$here/didacta-256.png"
[ -f "$icon" ] || { echo "no encuentro el icono en $icon" >&2; exit 1; }
cp "$icon" "$appdir/usr/share/icons/hicolor/256x256/apps/didacta.png"
cp "$icon" "$appdir/didacta.png"

# AppRun: lo primero que se ejecuta al abrir el AppImage.
#
# `LD_LIBRARY_PATH` apuntando a `lib/` es lo que hace que el binario encuentre
# `libflutter_linux_gtk.so` y las de los plugins, que van al lado y no en el
# sistema. Sin esto el AppImage arranca y muere sin decir nada.
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$here/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$here/usr/bin/didacta" "$@"
APPRUN
chmod +x "$appdir/AppRun"

# La herramienta oficial. Se descarga si no está: el runner del CI no la trae,
# y pedir que se instale a mano sería una dependencia más que documentar.
tool=${APPIMAGETOOL:-}
if [ -z "$tool" ]; then
  tool=$(mktemp -d)/appimagetool
  echo "descargando appimagetool…"
  curl -fsSL -o "$tool" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$tool"
fi

target="$out/Didacta-$version-linux-x64.AppImage"
rm -f "$target"

# `ARCH` explícito: appimagetool no lo deduce y falla con un mensaje que no
# dice que le falta. `--appimage-extract-and-run` porque en un contenedor de
# CI no hay FUSE, que es lo que un AppImage usa para montarse.
ARCH=x86_64 "$tool" --appimage-extract-and-run \
  --no-appstream "$appdir" "$target"

chmod +x "$target"
echo "AppImage  $(du -h "$target" | cut -f1)  $target"
