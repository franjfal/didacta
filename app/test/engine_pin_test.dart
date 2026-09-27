/// El motor en la versión de la aplicación, con git de verdad.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/engine_pin.dart';
import 'package:didacta_app/model/app_version.dart';

void git(String where, List<String> arguments) {
  final done = Process.runSync('git', arguments, workingDirectory: where);
  if (done.exitCode != 0) throw StateError('git $arguments: ${done.stderr}');
}

/// Un «GitHub» con dos versiones publicadas, y un clon de `main`.
({String origin, String engine}) published() {
  final root = Directory.systemTemp.createTempSync('didacta-pin-');
  addTearDown(() => root.deleteSync(recursive: true));
  final work = '${root.path}/work';
  Directory(work).createSync();
  git(work, ['init', '-q', '-b', 'main']);
  git(work, ['config', 'user.email', 'a@b.c']);
  git(work, ['config', 'user.name', 'A']);
  for (final version in ['0.2.0', '0.2.1']) {
    File('$work/VERSION').writeAsStringSync(version);
    git(work, ['add', '.']);
    git(work, ['commit', '-q', '-m', version]);
    git(work, ['tag', 'v$version']);
  }
  File('$work/VERSION').writeAsStringSync('después');
  git(work, ['commit', '-q', '-am', 'main sigue']);
  final origin = '${root.path}/origin.git';
  git(root.path, ['clone', '-q', '--bare', work, origin]);
  final engine = '${root.path}/didacta';
  // Sin etiquetas, como un clon de `main` antiguo que no las trajo.
  git(root.path, ['clone', '-q', '--no-tags', origin, engine]);
  return (origin: origin, engine: engine);
}

void main() {
  const app = AppVersion(0, 2, 1);

  test('un clon de main no está en ninguna versión', () async {
    final found = await inspectEngine(published().engine, app);
    expect(found.engine, isNull);
    expect(found.commit, isNotEmpty);
    expect(found.matches, isFalse);
    expect(found.managed, isFalse);
    expect(found.blocked, isNull);
    expect(found.canPin, isTrue);
  });

  test('ponerlo en la de la aplicación trae la etiqueta y la saca', () async {
    final engine = published().engine;
    await pinEngine(engine, app);
    final found = await inspectEngine(engine, app);
    expect(found.engine, app);
    expect(found.matches, isTrue);
    expect(File('$engine/VERSION').readAsStringSync(), '0.2.1');
    // Y otra vez no cambia nada.
    await pinEngine(engine, app);
    expect((await inspectEngine(engine, app)).matches, isTrue);
  });

  test('al actualizar la aplicación, a la nueva', () async {
    final engine = published().engine;
    await pinEngine(engine, const AppVersion(0, 2, 0));
    expect(File('$engine/VERSION').readAsStringSync(), '0.2.0');
    final before = await inspectEngine(engine, app);
    expect(before.engine, const AppVersion(0, 2, 0));
    expect(before.canPin, isTrue);
    await pinEngine(engine, app);
    expect(File('$engine/VERSION').readAsStringSync(), '0.2.1');
  });

  test('una versión que GitHub no tiene lo dice', () async {
    final engine = published().engine;
    await expectLater(
      pinEngine(engine, const AppVersion(9, 9, 9)),
      throwsA(
        isA<EnginePinException>().having(
          (e) => e.message,
          'message',
          contains('v9.9.9'),
        ),
      ),
    );
    // Y se queda donde estaba.
    expect(File('$engine/VERSION').readAsStringSync(), 'después');
  });

  test('con cambios sin guardar no se mueve', () async {
    final engine = published().engine;
    File('$engine/VERSION').writeAsStringSync('mío');
    final found = await inspectEngine(engine, app);
    expect(found.blocked, contains('cambios sin guardar'));
    expect(found.canPin, isFalse);
  });

  test('la marca de instalado por Didacta', () async {
    final engine = published().engine;
    expect((await inspectEngine(engine, app)).managed, isFalse);
    await markManaged(engine);
    final found = await inspectEngine(engine, app);
    expect(found.managed, isTrue);
    // Dentro de .git: no es un cambio del clon.
    expect(found.blocked, isNull);
  });

  test('una carpeta que no es un clon no se toca', () async {
    final dir = Directory.systemTemp.createTempSync('didacta-pin-plain-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final found = await inspectEngine(dir.path, app);
    expect(found.blocked, contains('no es un clon'));
    expect(found.canPin, isFalse);
  });

  test('sin versión de aplicación, nada que pedir', () async {
    final found = await inspectEngine(
      published().engine,
      const AppVersion(0, 0, 0),
    );
    expect(found.appKnown, isFalse);
    expect(found.canPin, isFalse);
  });
}
