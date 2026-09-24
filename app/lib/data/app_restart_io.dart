/// Volver a abrir Didacta, en cada sistema.
library;

import 'dart:io';

Future<void> restartApp() async {
  final executable = Platform.resolvedExecutable;
  try {
    if (Platform.isMacOS) {
      // El paquete .app, no el binario de dentro: `open` es lo que hace que
      // arranque como una aplicación, con su Dock y su menú. Con un segundo
      // de espera para que esta haya terminado, y la ruta como argumento y
      // no dentro de la orden, para que ningún nombre se interprete.
      final cut = executable.indexOf('.app/');
      final bundle = cut < 0 ? executable : executable.substring(0, cut + 4);
      await Process.start('/bin/sh', [
        '-c',
        r'sleep 1; open -n "$0"',
        bundle,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start(executable, [], mode: ProcessStartMode.detached);
    } else {
      // Un AppImage se ejecuta montado, y lo montado desaparece al cerrar:
      // lo que hay que volver a abrir es el fichero .AppImage.
      final image = Platform.environment['APPIMAGE'] ?? executable;
      await Process.start('/bin/sh', [
        '-c',
        r'sleep 1; exec "$0"',
        image,
      ], mode: ProcessStartMode.detached);
    }
  } on ProcessException {
    // Sin poder volver a abrirla, al menos se cierra: lo borrado ya está
    // borrado, y abrirla a mano la encuentra de cero.
  }
  exit(0);
}
