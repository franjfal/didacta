/// El vigilante de verdad, sobre el sistema de ficheros.
library;

import 'dart:async';
import 'dart:io';

/// El fichero que se mira: si cambia, el índice cambió.
///
/// Uno y no los cuatro de `generated/`: el motor los escribe juntos, y cuatro
/// vigilantes darían cuatro avisos por una sola regeneración.
const String _manifest = 'generated/manifest.json';

Stream<void> watchIndex(String directory) {
  final generated = Directory('$directory/generated');
  if (!generated.existsSync()) return const Stream.empty();
  try {
    return generated
        .watch(events: FileSystemEvent.all)
        .where((event) => event.path.endsWith('.json'))
        .map((_) {});
  } on FileSystemException {
    // No poder vigilar no es un error: queda la comprobación al volver a la
    // ventana, que coge lo mismo un momento más tarde.
    return const Stream.empty();
  }
}

Future<DateTime?> indexModified(String directory) async {
  final file = File('$directory/$_manifest');
  try {
    return await file.exists() ? await file.lastModified() : null;
  } on FileSystemException {
    return null;
  }
}
