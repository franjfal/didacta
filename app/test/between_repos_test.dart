/// Lo que solo puede ir mal con más de un repositorio abierto.
///
/// Vivía en Ajustes, que es donde se pone lo que no tiene sitio. Tiene sitio:
/// es trabajo pendiente sobre el material, como las traducciones, y en Ajustes
/// no se entra a mirar si algo va mal. Ahora es un apartado del carril, y
/// **solo aparece con varios repositorios**: con uno no hay nada que cruzar, y
/// un apartado que siempre dice «todo cuadra» es un apartado que se deja de
/// abrir.
///
/// Las dos comprobaciones que lleva no las puede hacer el motor: `didacta
/// check` mira un repositorio, y desde allí el de al lado no existe.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/between_repos_page.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> courseWith({
  String title = 'Análisis Matemático I',
  String document = 'tema-1',
  List<String> references = const [],
}) => {
  'id': 'am-i',
  'title': {'es': title},
  'language': 'es',
  'years': {
    '2026-2027': {
      'year': '2026-2027',
      'language': 'es',
      'documents': [
        {
          'id': document,
          'kind': 'theory',
          'language': 'es',
          'title': const {'es': 'Tema 1'},
          'profiles': const <String>[],
          'unitRefs': references,
        },
      ],
    },
  },
};

Map<String, dynamic> unitJson(String path) => {
  'id': path.replaceAll('/', '.'),
  'path': path,
  'area': 'content',
  'block': 'theory',
  'kind': 'theory',
  'title': const {'es': 'Una lección'},
  'reference': 'es',
  'languages': const <String, dynamic>{},
};

/// Dos repositorios, con lo que cada uno declara.
Catalogue twoRepos({
  String firstTitle = 'Análisis Matemático I',
  String secondTitle = 'Análisis Matemático I',
  List<String> references = const [],
  List<Map<String, dynamic>> unitsInFirst = const [],
}) => Catalogue.merge([
  catalogueWith(
    unitsInFirst,
    courses: [courseWith(title: firstTitle)],
    repo: 'x/teoria',
  ),
  catalogueWith(
    const [],
    courses: [
      courseWith(
        title: secondTitle,
        // Otro id: los dos repositorios declaran la misma asignatura y el
        // mismo año, y la fusión junta sus documentos por id. Con el mismo,
        // el del segundo --el que lleva las referencias-- se pierde, que es
        // lo que hacía que este test no viera ningún cruce.
        document: 'hoja-1',
        references: references,
      ),
    ],
    repo: 'x/problemas',
  ),
]);

Future<FakeSession> sessionWith(Catalogue catalogue, {int repos = 2}) async {
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  await session.useClonesForTest([
    for (var i = 0; i < repos; i += 1) '/tmp/didacta-$i',
  ]);
  return session;
}

Future<void> pump(WidgetTester tester, Session session, Widget page) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  group('cuándo aparece en el carril', () {
    Future<void> rail(WidgetTester tester, {required int repos}) async {
      final catalogue = catalogueWith(const []);
      final session = await sessionWith(catalogue, repos: repos);
      await pump(
        tester,
        session,
        const DidactaShell(location: '/courses', child: SizedBox.shrink()),
      );
    }

    testWidgets('con un repositorio, no', (tester) async {
      // No hay nada que cruzar, así que el apartado no puede decir nada.
      await rail(tester, repos: 1);
      expect(find.text('Entre repos'), findsNothing);
    });

    testWidgets('con dos, sí', (tester) async {
      await rail(tester, repos: 2);
      expect(find.text('Entre repos'), findsOneWidget);
    });

    testWidgets('y Ajustes se queda el último', (tester) async {
      // El carril se lee por posición: lo que aparece y desaparece no puede
      // mover a Ajustes de sitio.
      await rail(tester, repos: 2);
      expect(
        tester.getTopLeft(find.text('Entre repos')).dy,
        lessThan(tester.getTopLeft(find.text('Ajustes')).dy),
      );
    });
  });

  group('los metadatos que discrepan', () {
    testWidgets('se enseñan con lo que dice cada repositorio', (tester) async {
      // Sin esto no hay forma de darse cuenta: la fusión elige un valor y el
      // otro desaparece para siempre.
      final session = await sessionWith(
        twoRepos(
          firstTitle: 'Análisis Matemático I',
          secondTitle: 'Analisis Matematico I',
        ),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(find.textContaining('título (es)'), findsOneWidget);
      expect(find.text('«Análisis Matemático I»'), findsOneWidget);
      expect(find.text('«Analisis Matematico I»'), findsOneWidget);
    });

    testWidgets('con un botón por valor, y el que se pulsa manda', (
      tester,
    ) async {
      // Nada de «el más nuevo gana»: son ficheros que pueden ser de otra
      // persona, y propagar solo deshace el cambio de quien no lo ha enviado.
      final session = await sessionWith(
        twoRepos(firstTitle: 'Uno', secondTitle: 'Otro'),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(
        find.byKey(const Key('use-am-i-título (es)-x/teoria')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('use-am-i-título (es)-x/problemas')),
        findsOneWidget,
      );
    });

    testWidgets('si todo coincide, lo dice', (tester) async {
      final session = await sessionWith(twoRepos());
      await pump(tester, session, const BetweenReposPage());
      expect(find.text('Todo coincide.'), findsOneWidget);
    });
  });

  group('los documentos que llaman fuera', () {
    testWidgets('se enseñan diciendo dónde está cada mitad', (tester) async {
      // El caso que rompe la clase de otra persona: compila en la máquina que
      // tiene los dos repositorios abiertos y no en la de quien tiene uno.
      final session = await sessionWith(
        twoRepos(
          references: const ['analysis/normed/definition'],
          unitsInFirst: [unitJson('content/analysis/normed/definition')],
        ),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(find.textContaining('hoja-1'), findsWidgets);
      expect(find.text('analysis/normed/definition'), findsOneWidget);
      expect(find.textContaining('está en'), findsOneWidget);
    });

    testWidgets('una referencia rota no cuenta como cruce', (tester) async {
      // Son dos problemas distintos y se arreglan distinto: una apunta a algo
      // que no existe en ninguna parte, y la otra a algo que existe en el
      // sitio equivocado.
      final session = await sessionWith(
        twoRepos(references: const ['analysis/normed/no-existe']),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(
        find.text('Ningún documento llama fuera de su repositorio.'),
        findsOneWidget,
      );
    });

    testWidgets('no se ofrece arreglarlo desde aquí', (tester) async {
      // Arreglarlo es mover material que puede estar usando otra persona. Lo
      // que hace falta primero es saber que pasa y dónde.
      final session = await sessionWith(
        twoRepos(
          references: const ['analysis/normed/definition'],
          unitsInFirst: [unitJson('content/analysis/normed/definition')],
        ),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(find.textContaining('no se hacen desde aquí'), findsOneWidget);
    });
  });

  group('la cabecera', () {
    testWidgets('cuenta lo que hay por mirar', (tester) async {
      final session = await sessionWith(
        twoRepos(
          firstTitle: 'Uno',
          secondTitle: 'Otro',
          references: const ['analysis/normed/definition'],
          unitsInFirst: [unitJson('content/analysis/normed/definition')],
        ),
      );
      await pump(tester, session, const BetweenReposPage());

      expect(find.textContaining('2 cosa(s) por mirar'), findsOneWidget);
    });

    testWidgets('y cuando no hay nada, lo dice sin números', (tester) async {
      final session = await sessionWith(twoRepos());
      await pump(tester, session, const BetweenReposPage());
      expect(find.text('Todo cuadra'), findsOneWidget);
    });
  });
}
