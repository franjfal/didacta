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

/// La carpeta del índice.
const List<String> _index = ['generated'];

/// Avisa cuando cambia cualquier fichero del material.
///
/// Recursivo y sobre las tres carpetas: lo que hay que coger es «alguien ha
/// tocado algo», y eso puede ser un `.tex` editado en otro programa, una
/// figura nueva, un `unit.yaml` a mano o un `git pull` que trae cien
/// ficheros. Qué cambió no lo contesta el aviso: lo contesta volver a mirar
/// el disco, que es barato.
Stream<void> watchContent(String directory) => _watch(
  directory,
  _content,
  recursive: true,
  // Los temporales de un editor no son un cambio de material.
  keep: (path) => !path.endsWith('~') && !path.contains('/.'),
);

/// Avisa cuando el motor reescribe el índice.
Stream<void> watchIndex(String directory) =>
    _watch(directory, _index, recursive: false, keep: (p) => p.endsWith('.json'));

/// Vigila [names] dentro de [directory], y la raíz mientras alguna no exista.
///
/// Lo segundo es lo que hace que un repositorio recién añadido se entere de
/// sí mismo. Un clon vacío --o uno al que todavía no le han pasado el motor--
/// no tiene `content/` ni `generated/`, y vigilar una carpeta que no existe
/// no vigila nada: el repositorio se quedaba mudo para siempre, enseñando el
/// error de «no existe manifest.json» mucho después de que el fichero
/// estuviera ahí. La raíz sí existe --es el clon--, así que se mira ella
/// hasta que aparezca lo que falta; el aviso de que ha aparecido es el que
/// hace que alguien vuelva a montar los vigilantes de verdad.
Stream<void> _watch(
  String directory,
  List<String> names, {
  required bool recursive,
  required bool Function(String path) keep,
}) {
  final streams = <Stream<FileSystemEvent>>[];
  var missing = false;

  for (final name in names) {
    final folder = Directory('$directory/$name');
    if (!folder.existsSync()) {
      missing = true;
      continue;
    }
    try {
      streams.add(
        folder
            .watch(events: FileSystemEvent.all, recursive: recursive)
            .where((event) => keep(event.path)),
      );
    } on FileSystemException {
      missing = true;
    }
  }

  if (missing) {
    try {
      streams.add(
        Directory(directory).watch(events: FileSystemEvent.all).where(
          (event) => names.any(
            (name) =>
                event.path == '$directory/$name' ||
                event.path.endsWith('/$name'),
          ),
        ),
      );
    } on FileSystemException {
      // Ni la raíz se deja vigilar: queda la comprobación al volver a la
      // ventana, que coge lo mismo un momento más tarde.
    }
  }

  if (streams.isEmpty) return const Stream.empty();

  final controller = StreamController<void>.broadcast();
  final subscriptions = [
    for (final stream in streams)
      stream.listen((_) {
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

Future<DateTime?> indexModified(String directory) async {
  final file = File('$directory/$_manifest');
  try {
    return await file.exists() ? await file.lastModified() : null;
  } on FileSystemException {
    return null;
  }
}
