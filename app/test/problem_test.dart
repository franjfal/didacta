/// Los fallos, dichos de forma que se entiendan y con qué hacer.
///
/// Había unos cuarenta sitios que enseñaban el error tal cual, a menudo en
/// el inglés de git, en un aviso que se iba a los cuatro segundos.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/problem.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const behind = CloneException(
  'git falló al enviar (código 1).',
  stderr: ' ! [rejected] main -> main (fetch first)',
);

class _PullSession extends FakeSession {
  _PullSession({required super.catalogue})
    : super(gatewayOverride: FakeGateway());

  int pulls = 0;

  @override
  Future<Map<String, Object>> pullAll() async {
    pulls += 1;
    return {'x/uno': 1};
  }
}

/// Una pantalla con un botón que lanza [error], bajo un router de verdad.
Future<_PullSession> _pumpWith(WidgetTester tester, Object error) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith(defaultUnits());
  final session = _PullSession(catalogue: catalogue);
  await session.primeForTest(catalogue);
  final router = GoRouter(
    initialLocation: '/here',
    routes: [
      GoRoute(
        path: '/here',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProblem(context, error),
              child: const Text('fallar'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Scaffold(body: Text('los ajustes')),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: Provider<GoRouter>.value(
        value: router,
        child: MaterialApp.router(theme: didactaTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.tap(find.text('fallar'));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('qué se dice', () {
    test('cambios nuevos en GitHub: traer primero', () {
      final problem = problemOf(behind);
      expect(problem.title, 'Hay cambios nuevos en GitHub');
      expect(problem.fix, ProblemFix.pull);
      // Lo que dijo git, entero, para «Detalles».
      expect(problem.detail, contains('fetch first'));
    });

    test('la sesión, volver a entrar', () {
      final problem = problemOf(
        const CloneException(
          'git falló al enviar.',
          stderr: 'fatal: Authentication failed',
        ),
      );
      expect(problem.fix, ProblemFix.signIn);
    });

    test('dentro de un fallo de guardar, se mira el de git', () {
      final problem = problemOf(
        const ContentException('No se pudo guardar.', cause: behind),
      );
      expect(problem.title, 'Hay cambios nuevos en GitHub');
    });

    test('sin red, sin botón', () {
      final problem = problemOf(
        const CloneException(
          'git falló.',
          stderr: 'Could not resolve host: github.com',
        ),
      );
      expect(problem.title, 'No se llega a GitHub');
      expect(problem.fix, isNull);
    });

    test('lo demás, con su primera línea', () {
      final problem = problemOf(
        const CloneException(
          'La carpeta no está vacía.',
          stderr: 'algo más largo',
        ),
      );
      expect(problem.title, 'La carpeta no está vacía.');
    });
  });

  group('cómo se enseña', () {
    testWidgets('con el título, el consejo y el arreglo a un botón', (
      tester,
    ) async {
      final session = await _pumpWith(tester, behind);
      expect(find.text('Hay cambios nuevos en GitHub'), findsOneWidget);
      expect(find.textContaining('Trae primero'), findsOneWidget);

      await tester.tap(find.byKey(const Key('problem-fix')));
      await tester.pumpAndSettle();
      expect(session.pulls, 1);
    });

    testWidgets('«Volver a entrar» lleva a Ajustes', (tester) async {
      await _pumpWith(
        tester,
        const CloneException('x', stderr: 'returned error: 401'),
      );
      await tester.tap(find.byKey(const Key('problem-fix')));
      await tester.pumpAndSettle();
      expect(find.text('los ajustes'), findsOneWidget);
    });

    testWidgets('«Detalles» enseña lo que dijo el programa y deja copiarlo', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpWith(tester, behind);
      await tester.tap(find.byKey(const Key('problem-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('problem-dialog')), findsOneWidget);
      expect(find.byKey(const Key('problem-report')), findsOneWidget);

      // Plegado de salida.
      expect(find.textContaining('fetch first'), findsNothing);
      await tester.tap(find.byKey(const Key('problem-said')));
      await tester.pumpAndSettle();
      expect(find.textContaining('fetch first'), findsOneWidget);

      await tester.tap(find.byKey(const Key('problem-copy')));
      await tester.pumpAndSettle();
      expect(copied, contains('fetch first'));
    });
  });
}
