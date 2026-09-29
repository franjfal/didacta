/// Una traducción desactualizada dice qué ha cambiado en el original.
///
/// «Desactualizada» decía que el original había cambiado y nada más: una
/// coma o un teorema nuevo se veían igual, y para saberlo había que ir al
/// historial y buscar a ojo. La huella que se guarda al revisar dice cuál era
/// el original entonces; aquí se comprueba que se encuentra esa versión en el
/// historial y que se enseña la diferencia con la de ahora.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/model/source_hash.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String before = 'La norma es una longitud.\n';
const String after = 'La norma es una longitud.\n\nY cumple la desigualdad.\n';

FileCommit commit(String sha, int day) => FileCommit(
  sha: sha,
  author: 'Javier',
  email: 'j@uv.es',
  when: DateTime(2026, 9, day),
  subject: 'Cambio $sha',
);

Future<FakeSession> sessionWith({String? hash}) async {
  final catalogue = catalogueWith([
    {
      ...unitJson(),
      'languages': {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': 'outdated', 'exists': true},
      },
    },
  ]);
  final clone = FakeClone();
  clone.log['$unitPath/es.tex'] = [commit('nuevo', 20), commit('viejo', 2)];
  clone.contents['nuevo'] = after;
  clone.contents['viejo'] = before;
  final session = FakeSession(
    gatewayOverride: FakeGateway(
      files: {
        '$unitPath/es.tex': after,
        '$unitPath/va.tex': 'La norma és una longitud.\n',
        '$unitPath/unit.yaml': [
          'title:',
          '  es: Espacios normados',
          'languages:',
          '  es: {status: source}',
          hash == null
              ? '  va: {status: reviewed}'
              : '  va: {status: reviewed, source_hash: $hash}',
          '',
        ].join('\n'),
      },
    ),
    catalogue: catalogue,
    cloneOverride: clone,
  );
  await session.primeForTest(catalogue);
  return session;
}

void main() {
  test('la huella se lee en línea y en bloque', () {
    expect(
      declaredSourceHash(
        'languages:\n  va: {status: reviewed, source_hash: sha256:ab}\n',
        'va',
      ),
      'sha256:ab',
    );
    expect(
      declaredSourceHash(
        'languages:\n  va:\n    status: reviewed\n    source_hash: sha256:cd\n',
        'va',
      ),
      'sha256:cd',
    );
    expect(
      declaredSourceHash('languages:\n  va: {status: draft}\n', 'va'),
      isNull,
    );
  });

  test('y no la confunde con el título en ese idioma', () {
    // El título va antes y tiene su línea por idioma: tomarla por la del
    // estado dejaba sin huella a casi todas las lecciones.
    expect(
      declaredSourceHash(
        'title:\n  es: Límite\n  va: Límit\n\n'
            'reference: es\n'
            'languages:\n  es: {status: source}\n'
            '  va: {status: reviewed, source_hash: sha256:ef}\n',
        'va',
      ),
      'sha256:ef',
    );
  });

  test('encuentra en el historial la versión que se revisó', () async {
    final session = await sessionWith(hash: contentHash(before));
    final unit = session.catalogue.units.single;
    final found = await session.originalAtReview(unit, 'va');
    expect(found?.commit.sha, 'viejo');
    expect(found?.text, before);
  });

  test('sin huella, no se sabe', () async {
    final session = await sessionWith();
    final unit = session.catalogue.units.single;
    expect(await session.originalAtReview(unit, 'va'), isNull);
  });

  testWidgets('la pestaña lo dice y enseña la diferencia', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = await sessionWith(hash: contentHash(before));
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: UnitPage(unitPath: unitPath, language: 'va'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const Key('outdated-strip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('show-original-changes')));
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const Key('diff-box')), findsOneWidget);
    expect(find.textContaining('Y cumple la desigualdad.'), findsOneWidget);
    expect(find.textContaining('2/9/2026'), findsOneWidget);
  });
}
