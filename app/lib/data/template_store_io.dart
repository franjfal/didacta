/// La carpeta de plantillas del programa, en una plataforma con disco.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'template_store.dart';

bool get supported => true;

Future<TemplateStore?> openStore() async {
  final support = await getApplicationSupportDirectory();
  return _DiskStore(Directory('${support.path}/templates'));
}

class _DiskStore implements TemplateStore {
  _DiskStore(this._root);

  final Directory _root;

  @override
  String get directory => _root.path;

  @override
  Future<bool> get hasAny async =>
      File('${_root.path}/templates.yaml').exists();

  /// La carpeta, creada si no estaba.
  ///
  /// A demanda y no al arrancar: quien no guarde nada aquí no tiene por qué
  /// encontrarse una carpeta vacía en los datos de la aplicación.
  Future<Directory> _ensure() async {
    if (!await _root.exists()) await _root.create(recursive: true);
    return _root;
  }

  @override
  Future<String> read(String relative) async {
    final file = File('${_root.path}/$relative');
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  @override
  Future<void> write(String relative, String text) async {
    await _ensure();
    final file = File('${_root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  @override
  Future<int> exportTo(String directory) async {
    final destination = Directory(directory);
    if (!await destination.exists()) {
      throw TemplateStoreException('no existe la carpeta $directory');
    }
    final source = await _ensure();
    var copied = 0;
    await for (final entry in source.list(recursive: true)) {
      if (entry is! File) continue;
      final relative = entry.path.substring(source.path.length + 1);
      final target = File('${destination.path}/$relative');
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
      copied += 1;
    }
    return copied;
  }

  @override
  Future<({List<String> copied, List<String> kept})> importFrom(
    String directory,
  ) async {
    final source = Directory(directory);
    if (!await source.exists()) {
      throw TemplateStoreException('no existe la carpeta $directory');
    }
    if (!await File('${source.path}/templates.yaml').exists()) {
      throw const TemplateStoreException(
        'ahí no hay plantillas: falta el templates.yaml',
      );
    }
    final destination = await _ensure();
    final copied = <String>[];
    final kept = <String>[];
    await for (final entry in source.list(recursive: true)) {
      if (entry is! File) continue;
      final relative = entry.path.substring(source.path.length + 1);
      final target = File('${destination.path}/$relative');
      if (await target.exists()) {
        kept.add(relative);
        continue;
      }
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
      copied.add(relative);
    }
    return (copied: copied, kept: kept);
  }
}
