/// Encontrar el clon del repositorio de contenido en el disco.
///
/// Este test existe por un fallo que ya ocurrió: la ruta del clon iba dentro
/// del binario por `--dart-define=DIDACTA_CLONE`, una compilación de
/// escritorio se hizo sin acordarse, y la aplicación abrió diciendo «no se
/// pudo cargar el catálogo» **con el catálogo generado y en su sitio**. Una
/// configuración invisible que se pierde en silencio no es una
/// configuración; encontrarla es parte de arrancar.
///
/// Contra directorios de verdad, porque lo que se prueba es el
/// reconocimiento: qué cuenta como clon y qué no.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';

/// Un directorio que parece el repositorio de contenido.
void seedClone(String path, {bool marker = true, bool git = true}) {
  Directory(path).createSync(recursive: true);
  if (marker) {
    File('$path/didacta.yaml').writeAsStringSync('name: Prueba\n');
  }
  if (git) Directory('$path/.git').createSync();
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('didacta-find-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('lo configurado manda, exista o no', () async {
    // La misma regla que con el motor: decir que la ruta elegida no está es
    // mejor que sustituirla por otra a la callada, que es como alguien
    // termina editando el repositorio equivocado.
    seedClone('${root.path}/didacta_db');
    expect(await LocalClone.discover(configured: '/no/existe'), '/no/existe');
  });

  test('al lado del motor, que es la disposición del README', () async {
    seedClone('${root.path}/didacta_db');
    Directory('${root.path}/didacta/cli').createSync(recursive: true);

    expect(
      await LocalClone.discover(enginePath: '${root.path}/didacta'),
      '${root.path}/didacta_db',
    );
  });

  test('con el nombre del repositorio que se le diga', () async {
    // El nombre es configurable (`DIDACTA_REPO`), así que buscar solo
    // `didacta_db` dejaría fuera a quien lo tenga con otro nombre.
    seedClone('${root.path}/apuntes');
    expect(
      await LocalClone.discover(
        repo: 'apuntes',
        enginePath: '${root.path}/didacta',
      ),
      '${root.path}/apuntes',
    );
  });

  // Los tres casos de «esta no». Se comprueba que no la elija, y no que
  // devuelva null: en la máquina donde esto se ejecuta puede haber un clon
  // de verdad en el sitio de siempre, y encontrarlo es lo que se quiere.

  test('una carpeta con el nombre pero sin git no vale', () async {
    // Se podría leer el catálogo de ahí, pero no se podría hacer un commit,
    // y elegirla en silencio dejaría la aplicación en un estado en el que
    // guardar falla sin explicación.
    seedClone('${root.path}/didacta_db', git: false);
    expect(
      await LocalClone.discover(enginePath: '${root.path}/didacta'),
      isNot(contains(root.path)),
    );
  });

  test('un clon de otra cosa tampoco: falta didacta.yaml', () async {
    seedClone('${root.path}/didacta_db', marker: false);
    expect(
      await LocalClone.discover(enginePath: '${root.path}/didacta'),
      isNot(contains(root.path)),
    );
  });

  test('una ruta inventada, nunca', () async {
    // Nada sembrado: lo que no puede pasar es que devuelva
    // `<algo>/didacta_db` porque el nombre encaje.
    final found = await LocalClone.discover(enginePath: '${root.path}/didacta');
    expect(found, isNot(contains(root.path)));
    if (found != null) {
      expect(File('$found/didacta.yaml').existsSync(), isTrue);
      expect(Directory('$found/.git').existsSync(), isTrue);
    }
  });

  test('hacia arriba desde donde se ejecuta', () async {
    // Es el caso de `flutter run` desde `app/`: el clon está dos niveles por
    // encima del directorio actual.
    seedClone('${root.path}/didacta_db');
    final work = Directory('${root.path}/didacta/app')
      ..createSync(recursive: true);
    final before = Directory.current;
    Directory.current = work;
    addTearDown(() => Directory.current = before);

    // Resuelto: en macOS `/var` es un enlace a `/private/var`, y el
    // directorio actual sale resuelto mientras `root.path` no.
    expect(
      await LocalClone.discover(),
      Directory('${root.path}/didacta_db').resolveSymbolicLinksSync(),
    );
  });
}
