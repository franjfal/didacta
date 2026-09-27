/// Los borradores, en la carpeta de datos de la aplicación.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostics.dart';
import 'draft_store.dart';

DraftStore diskDrafts() => DiskDraftStore();

/// Un fichero por borrador, con el nombre sacado de su clave: la clave lleva
/// la ruta del fichero y el repositorio, que como nombre de fichero no valen.
class DiskDraftStore implements DraftStore {
  DiskDraftStore({this.root});

  /// Dónde. Null es la carpeta de datos de la aplicación, que se pregunta la
  /// primera vez; las pruebas ponen una temporal.
  final Directory? root;

  Directory? _resolved;

  Future<Directory> _dir() async {
    final known = _resolved ?? root;
    if (known != null) return _resolved = known;
    final support = await getApplicationSupportDirectory();
    return _resolved = Directory('${support.path}/drafts');
  }

  Future<File> _fileFor(String key) async {
    final name = sha1.convert(utf8.encode(key)).toString();
    return File('${(await _dir()).path}/$name.json');
  }

  @override
  Future<Draft?> read(String key) async {
    try {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString()) as Map;
      if (data['key'] != key) return null;
      return Draft(
        text: data['text'] as String? ?? '',
        base: data['base'] as String? ?? '',
        when: DateTime.tryParse(data['when'] as String? ?? '') ?? DateTime(0),
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('draft_store_io.read', caught, trace);
      // Un borrador ilegible no es motivo para no abrir el fichero.
      return null;
    }
  }

  @override
  Future<void> write(String key, Draft draft) async {
    try {
      final file = await _fileFor(key);
      await file.parent.create(recursive: true);
      // A un temporal y renombrado: un corte a mitad de escribir deja el
      // borrador anterior entero, no uno a medias.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'key': key,
          'text': draft.text,
          'base': draft.base,
          'when': draft.when.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (caught, trace) {
      Diagnostics.instance.note('draft_store_io.write', caught, trace);
      // No poder copiar un borrador no puede interrumpir lo que se escribe.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } catch (caught, trace) {
      Diagnostics.instance.note('draft_store_io.delete', caught, trace);
    }
  }
}
