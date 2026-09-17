/// Aprobar una traducción: el paso que cerraba mal el ciclo.
///
/// Una máquina deja un borrador, una persona lo lee, y hasta ahora no había
/// forma de decir que ya está. El borrador se quedaba en la lista para
/// siempre, y una lista que no se vacía deja de significar nada.
///
/// El estado se declara **por idioma**, junto al idioma que se está editando.
/// Los otros dos --«no existe» y «desactualizada»-- no se declaran: los
/// calcula el motor, el primero de que el fichero esté y el segundo
/// comparando con el original, y escribirlos garantizaría que se queden
/// obsoletos en cuanto alguien toque el original.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String unitPathHere = 'content/analysis/normed/definition';

Future<(FakeSession, FakeGateway)> ready() async {
  final gateway = FakeGateway(
    files: {
      '$unitPathHere/unit.yaml':
          'kind: theory\n'
          'title:\n'
          '  es: Una definición\n'
          'languages:\n'
          '  es: {status: source}\n'
          '  va: {status: draft}\n',
    },
  );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return (session, gateway);
}

Unit theUnit(FakeSession session) =>
    session.catalogue.units.firstWhere((u) => u.path == unitPathHere);

void main() {
  test('aprobar una traducción la escribe en unit.yaml', () async {
    final (session, gateway) = await ready();

    await session.setUnitStatus(
      unit: theUnit(session),
      language: 'va',
      status: 'reviewed',
    );

    final written = gateway.commits.single;
    expect(written.path, '$unitPathHere/unit.yaml');
    expect(written.text, contains('va: {status: reviewed}'));
  });

  test('y no toca el estado de los otros idiomas', () async {
    // El estado es de **esa** traducción. Aprobar el valenciano no dice nada
    // del inglés.
    final (session, gateway) = await ready();

    await session.setUnitStatus(
      unit: theUnit(session),
      language: 'va',
      status: 'reviewed',
    );

    expect(gateway.commits.single.text, contains('es: {status: source}'));
  });

  test('el mensaje del commit dice qué se aprobó', () async {
    // Un historial lleno de «editar unit.yaml» es un historial que nadie lee.
    final (session, gateway) = await ready();

    await session.setUnitStatus(
      unit: theUnit(session),
      language: 'va',
      status: 'reviewed',
    );

    expect(gateway.commits.single.message, contains('va'));
    expect(gateway.commits.single.message, contains('revisada'));
  });

  test('los estados que calcula el motor se rechazan', () async {
    // Declararlos garantiza que se queden obsoletos: basta con volver a
    // tocar el original.
    final (session, _) = await ready();

    for (final status in ['missing', 'outdated']) {
      await expectLater(
        session.setUnitStatus(
          unit: theUnit(session),
          language: 'va',
          status: status,
        ),
        throwsArgumentError,
        reason: status,
      );
    }
  });

  test('en un repositorio de solo lectura se niega', () async {
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(writable: false),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);

    await expectLater(
      session.setUnitStatus(
        unit: theUnit(session),
        language: 'va',
        status: 'reviewed',
      ),
      throwsArgumentError,
    );
  });

  test('poner el mismo que ya estaba no hace commit', () async {
    // Un commit que no cambia nada es ruido en el historial de otra persona.
    final (session, gateway) = await ready();

    await session.setUnitStatus(
      unit: theUnit(session),
      language: 'va',
      status: 'draft',
    );

    expect(gateway.commits, isEmpty);
  });

  test('una unidad sin metadatos los estrena', () async {
    // Pasa con el material migrado: hay `.tex` y no hay `unit.yaml`.
    final gateway = FakeGateway(files: <String, String>{});
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
    await session.primeForTest(catalogue);

    await session.setUnitStatus(
      unit: theUnit(session),
      language: 'va',
      status: 'reviewed',
    );

    expect(gateway.commits.single.text, contains('va: {status: reviewed}'));
  });

  testWidgets('el estado que se enseña es el de ahora, no el de al abrir', (
    tester,
  ) async {
    // El fallo que se veía: aprobabas una traducción, el punto de la pestaña
    // se actualizaba --lee del catálogo-- y el botón de estado seguía
    // diciendo «borrador». El editor se cachea por idioma para no perder lo
    // escrito al cambiar de pestaña, y se quedaba con la unidad de cuando se
    // creó.
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Map<String, dynamic> withStatus(String status) => {
      ...unitJson(),
      'languages': {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': status, 'exists': true},
      },
    };

    final borrador = catalogueWith([withStatus('draft')]);
    // Con el fichero en valenciano de verdad: el editor lo lee, y sin él
    // la pestaña enseña el error en vez de la barra con el estado.
    final session = FakeSession(
      gatewayOverride: FakeGateway(
        files: {
          '$unitPath/es.tex': 'El original.\n',
          '$unitPath/va.tex': 'La traducció.\n',
        },
      ),
      catalogue: borrador,
    );
    await session.primeForTest(borrador);

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
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('borrador'), findsWidgets);

    // Lo que hace `setUnitStatus` al terminar: recargar el catálogo. La
    // unidad es **otra instancia**, y el editor cacheado tenía la vieja.
    await session.primeForTest(catalogueWith([withStatus('reviewed')]));
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('revisada'), findsWidgets);
    expect(find.text('borrador'), findsNothing);
  });

  group('qué se puede declarar', () {
    test('lo que sale del motor, no', () {
      expect(TranslationStatus.missing.computed, isTrue);
      expect(TranslationStatus.outdated.computed, isTrue);
    });

    test('y lo demás, sí', () {
      for (final status in [
        TranslationStatus.source,
        TranslationStatus.draft,
        TranslationStatus.translated,
        TranslationStatus.reviewed,
      ]) {
        expect(status.computed, isFalse, reason: '$status');
      }
    });
  });
}
