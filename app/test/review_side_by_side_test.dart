/// Revisar una traducción: el original al lado, un clic para aprobarla y la
/// siguiente ya abierta.
///
/// Revisar treinta eran, treinta veces, guardar lo corregido, cambiar el
/// estado --otro commit--, volver a la lista y buscar la siguiente. Lo que se
/// fija aquí:
///
/// * «Aprobar y siguiente» guarda lo corregido y el estado en **un** cambio,
///   con la huella del original, y abre la siguiente sin revisar;
/// * lado a lado, mientras se revisa la traducción, el original es de solo
///   lectura y lo dice;
/// * el desplazamiento del original sigue al de la traducción.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/unsaved_dialog.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String banach = 'content/analysis/normed/banach';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

List<Map<String, dynamic>> units() => [
  {
    ...unitJson(),
    'languages': {
      'es': {'status': 'source', 'exists': true},
      'va': {'status': 'draft', 'exists': true},
    },
  },
  {
    ...unitJson(path: banach, title: const {'es': 'Espacios de Banach'}),
    'languages': {
      'es': {'status': 'source', 'exists': true},
      'va': {'status': 'draft', 'exists': true},
    },
  },
];

final String longText = [
  for (var i = 0; i < 200; i += 1) 'Línea $i del texto.',
].join('\n');

Future<(FakeSession, FakeGateway, GoRouter)> open(
  WidgetTester tester, {
  bool split = false,
  bool guard = false,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith(units());
  final gateway = FakeGateway(
    files: {
      '$unitPath/es.tex': '$longText\n',
      '$unitPath/va.tex': '$longText\n',
      '$unitPath/unit.yaml': unitYaml,
      '$banach/es.tex': 'Un espacio completo.\n',
      '$banach/va.tex': 'Un espai complet.\n',
    },
  );
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  if (split) await session.setSplitEditors(true);
  final router = GoRouter(
    initialLocation: '/unit/$unitPath?lang=va',
    routes: [
      GoRoute(
        path: '/unit/:rest(.*)',
        // Como el de la aplicación, con `guard`: preguntar al salir si hay
        // algo sin guardar.
        onExit: guard
            ? (context, state) => confirmLeaving(
                context,
                session.unsaved.whatAt(state.uri.path),
              )
            : null,
        builder: (_, state) => Scaffold(
          body: UnitPage(
            key: ValueKey(state.uri.toString()),
            unitPath: state.pathParameters['rest']!,
            language: state.uri.queryParameters['lang'],
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp.router(theme: didactaTheme(), routerConfig: router),
    ),
  );
  await settle(tester);
  return (session, gateway, router);
}

void main() {
  test('la siguiente sin revisar, en el orden de la lista', () async {
    final catalogue = catalogueWith(units());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    final order = [
      for (final unit in session.needingTranslation('va')) unit.path,
    ];
    final next = session.nextToReview('va', after: order.first);
    expect(next?.path, order.last);
    // Y de la última, vuelta a la primera que quede.
    expect(session.nextToReview('va', after: order.last)?.path, order.first);
  });

  testWidgets('aprobar guarda lo corregido y el estado en un cambio, y abre '
      'la siguiente', (tester) async {
    final (session, gateway, router) = await open(tester);
    final next = session.nextToReview('va', after: unitPath)!;

    await tester.enterText(find.byType(TextField).first, 'Corregida.\n');
    await settle(tester);
    await tester.tap(find.byKey(const Key('approve-next')));
    await settle(tester);

    expect(
      gateway.batches.single,
      unorderedEquals(['$unitPath/va.tex', '$unitPath/unit.yaml']),
    );
    final yaml = gateway.files['$unitPath/unit.yaml']!;
    expect(yaml, contains('va: {status: reviewed, source_hash: sha256:'));
    expect(gateway.files['$unitPath/va.tex'], 'Corregida.\n');
    expect(
      router.routeInformationProvider.value.uri.toString(),
      contains(next.path),
    );
  });

  testWidgets('y al irse a la siguiente no pregunta por lo que ya guardó', (
    tester,
  ) async {
    // La marca de «sin guardar» se apunta al repintar; aprobar navegaba
    // antes, y salir preguntaba por unos cambios que acababa de guardar.
    final (session, _, router) = await open(tester, guard: true);
    final next = session.nextToReview('va', after: unitPath)!;

    await tester.enterText(find.byType(TextField).first, 'Corregida.\n');
    await settle(tester);
    await tester.tap(find.byKey(const Key('approve-next')));
    await settle(tester);

    expect(find.text('Hay cambios sin guardar'), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      contains(next.path),
    );
  });

  testWidgets('sin corregir nada, solo el estado', (tester) async {
    final (_, gateway, _) = await open(tester);
    await tester.tap(find.byKey(const Key('approve-next')));
    await settle(tester);
    expect(gateway.batches.single, ['$unitPath/unit.yaml']);
  });

  testWidgets('lado a lado, el original es de solo lectura', (tester) async {
    await open(tester, split: true);
    expect(find.byKey(const Key('pane-locked-es')), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.where((field) => field.readOnly), hasLength(1));
  });

  testWidgets('y su desplazamiento sigue al de la traducción', (tester) async {
    await open(tester, split: true);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    final editable = fields.firstWhere((field) => !field.readOnly);
    final locked = fields.firstWhere((field) => field.readOnly);
    final leader = editable.scrollController!;
    final follower = locked.scrollController!;
    expect(leader.position.maxScrollExtent, greaterThan(0));

    leader.jumpTo(leader.position.maxScrollExtent / 2);
    await tester.pump();
    expect(
      follower.position.pixels / follower.position.maxScrollExtent,
      closeTo(0.5, 0.02),
    );
  });

  test('el original no se aprueba', () async {
    final catalogue = catalogueWith(units());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    final unit = session.catalogue.units.firstWhere((u) => u.path == unitPath);
    expect(
      () => session.approveTranslation(unit: unit, language: 'es'),
      throwsArgumentError,
    );
  });
}
