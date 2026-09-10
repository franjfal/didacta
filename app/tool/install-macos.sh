#!/bin/sh
# Compila Didacta para macOS, la instala y la abre.
#
# Un script y no una orden a mano porque la orden a mano se hizo mal una vez y
# costó una tarde: la ruta del clon iba dentro del binario por
# `--dart-define=DIDACTA_CLONE`, una compilación se hizo sin acordarse, y la
# aplicación abrió diciendo «no se pudo cargar el catálogo» con el catálogo
# generado y en su sitio.
#
# Ya no hace falta ninguna define --la aplicación busca el clon-- pero sí hacen
# falta los dos pasos que también se olvidan: cerrar la copia que esté abierta
# (copiar encima de una app en marcha la deja a medias) y dejar **una sola**
# instalada, que es lo que evita abrir por error la de ayer.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
target=${DIDACTA_APPS:-$HOME/Applications}
built=$here/build/macos/Build/Products/Release/Didacta.app

cd "$here"
flutter build macos --release

# Cerrar lo que hubiera abierto, incluidas instalaciones viejas en otro sitio.
pkill -f 'Didacta.app/Contents/MacOS/Didacta' 2>/dev/null || true
sleep 1

mkdir -p "$target"
rm -rf "$target/Didacta.app"
cp -R "$built" "$target/"

# Y avisar si queda otra copia por ahí: dos Didactas en el Dock, una de ellas
# vieja, es peor que una en el sitio menos canónico.
for other in /Applications/Didacta.app "$HOME/Desktop/Didacta.app"; do
  [ "$other" = "$target/Didacta.app" ] && continue
  [ -e "$other" ] && echo "AVISO: queda otra copia en $other"
done

open -a "$target/Didacta.app"
echo "Instalada en $target/Didacta.app"
