/// Lo escrito y sin guardar, copiado fuera del repositorio mientras se escribe.
///
/// Si Didacta se cierra de golpe --se cuelga, se va la luz, se cierra el
/// portátil sin batería-- lo que había en un editor sin guardar se perdía
/// entero. Esto lo va copiando a la carpeta de datos de la aplicación, fuera
/// del repositorio para no ensuciarlo ni colarse en un commit, y el editor lo
/// ofrece al volver a abrir ese fichero.
///
/// Se borra al guardar y al descartar: un borrador que sobrevive a su
/// guardado es un aviso falso la próxima vez.
library;

import 'draft_store_stub.dart'
    if (dart.library.io) 'draft_store_io.dart'
    as platform;

/// Un borrador: el texto, y sobre qué versión del fichero se escribió.
class Draft {
  const Draft({required this.text, required this.base, required this.when});

  final String text;

  /// El sha del fichero cuando se empezó a escribir. Si el fichero ha
  /// cambiado desde entonces, recuperar el borrador es pisar ese cambio, y
  /// el editor lo dice.
  final String base;

  final DateTime when;
}

abstract class DraftStore {
  Future<Draft?> read(String key);
  Future<void> write(String key, Draft draft);
  Future<void> delete(String key);
}

/// El de esta plataforma: en disco donde lo hay, en memoria en la web.
DraftStore diskDrafts() => platform.diskDrafts();

/// En memoria: para la web y para las pruebas.
class MemoryDraftStore implements DraftStore {
  final Map<String, Draft> drafts = {};

  @override
  Future<Draft?> read(String key) async => drafts[key];

  @override
  Future<void> write(String key, Draft draft) async => drafts[key] = draft;

  @override
  Future<void> delete(String key) async => drafts.remove(key);
}
