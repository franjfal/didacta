/// El vigilante de verdad, sobre el sistema de ficheros.
library;

import 'dart:async';
import 'dart:io';

/// El fichero que se mira: si cambia, el índice cambió.
///
/// Uno y no los cuatro de `generated/`: el motor los escribe juntos, y cuatro
/// vigilantes darían cuatro avisos por una sola regeneración.
const String _manifest = 'generated/manifest.json';

/// Las carpetas donde vive el material.
const List<String> _content = ['content', 'problems', 'courses'];

/// Avisa cuando cambia cualquier fichero del material.
///
/// Recursivo y sobre las tres carpetas: lo que hay que coger es «alguien ha
/// tocado algo», y eso puede ser un `.tex` editado en otro programa, una
/// figura nueva, un `unit.yaml` a mano o un `git pull` que trae cien
/// ficheros. Qué cambió no lo contesta el aviso: lo contesta volver a mirar
/// el disco, que es barato.
Stream<void> watchContent(String directory) {
  final streams = <Stream<FileSystemEvent>>[];
  for (final name in _content) {
    final folder = Directory('$directory/$name');
    if (!folder.existsSync()) continue;
    try {
      streams.add(folder.watch(events: FileSystemEvent.all, recursive: true));
    } on FileSystemException {
      continue;
    }
  }
  if (streams.isEmpty) return const Stream.empty();
  final controller = StreamController<void>.broadcast();
  final subscriptions = [
    for (final stream in streams)
      stream.listen((event) {
        // Los temporales de un editor no son un cambio de material.
        final path = event.path;
        if (path.endsWith('~') || path.contains('/.')) return;
        if (!controller.isClosed) controller.add(null);
      }),
  ];
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
  return controller.stream;
}

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
