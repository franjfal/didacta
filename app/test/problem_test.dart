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

import 'package:didacta_app/data/browser.dart';
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

/// Lo que se ve al fallar un rebase: las dos historias tocan lo mismo.
const diverged = CloneException(
  'Tus cambios sin enviar y los que han llegado de GitHub tocan lo mismo en '
  'content/a/es.tex. Lo he dejado todo como estaba.',
  stderr: 'error: could not apply 1a2b3c4... Mío',
  kind: CloneFailure.diverged,
);

class _PullSession extends FakeSession {
  _PullSession({required super.catalogue, required this.pulled})
    : super(gatewayOverride: FakeGateway());

  final Map<String, Object> pulled;

  int pulls = 0;

  @override
  Future<Map<String, Object>> pullAll() async {
    pulls += 1;
    return pulled;
  }
}

/// Una pantalla con un botón que lanza [error], bajo un router de verdad.
///
/// Traer, desde ahí, devuelve [pulled].
Future<_PullSession> _pumpWith(
  WidgetTester tester,
  Object error, {
  Map<String, Object> pulled = const {'x/uno': 1},
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith(defaultUnits());
  final session = _PullSession(catalogue: catalogue, pulled: pulled);
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

    test('dos historias que no se juntan no son el choque del editor', () {
      // «Dos cambios chocan» manda a recargar el fichero, y aquí eso no
      // arregla nada: lo que hay que juntar son dos historias.
      final problem = problemOf(diverged);
      expect(
        problem.title,
        'Tus cambios y los de GitHub no se pueden juntar solos',
      );
      expect(problem.advice, contains('lo tuyo sigue guardado'));
      expect(problem.fix, ProblemFix.help);
      expect(problem.help, 'ayuda/problemas/#historias-separadas');
      expect(problem.detail, contains('could not apply'));
    });

    test('ni lo es un --ff-only que se niega', () {
      final problem = problemOf(
        const CloneException(
          'git falló al traer los cambios del repositorio (código 128).',
          stderr: 'fatal: Not possible to fast-forward, aborting.',
        ),
      );
      expect(problem.title, isNot('Dos cambios chocan'));
      expect(problem.fix, ProblemFix.help);
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

    testWidgets('si traer tampoco puede, lo dice como un aviso más', (
      tester,
    ) async {
      // Antes salía «Tampoco se pudo traer:» con el texto de la excepción
      // pegado detrás, en inglés de git y sin nada que hacer con él.
      await _pumpWith(tester, behind, pulled: const {'x/uno': diverged});
      await tester.tap(find.byKey(const Key('problem-fix')));
      await tester.pumpAndSettle();

      expect(
        find.text('Tus cambios y los de GitHub no se pueden juntar solos'),
        findsOneWidget,
      );
      expect(find.text('Cómo juntarlos'), findsOneWidget);
      expect(find.textContaining('Tampoco se pudo traer'), findsNothing);
      expect(find.textContaining('could not apply'), findsNothing);
    });

    testWidgets('y si trae, dice que se vuelva a intentar', (tester) async {
      await _pumpWith(tester, behind);
      await tester.tap(find.byKey(const Key('problem-fix')));
      await tester.pumpAndSettle();
      expect(find.text('Traído. Vuelve a intentarlo.'), findsOneWidget);
    });

    testWidgets('«Cómo juntarlos» abre la ayuda, en su sitio', (tester) async {
      final opened = <String>[];
      final before = openLinkWith;
      openLinkWith = (url) async {
        opened.add(url);
        return true;
      };
      addTearDown(() => openLinkWith = before);

      await _pumpWith(tester, diverged);
      await tester.tap(find.byKey(const Key('problem-fix')));
      await tester.pumpAndSettle();
      expect(opened, ['${didactaDocs}ayuda/problemas/#historias-separadas']);
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
