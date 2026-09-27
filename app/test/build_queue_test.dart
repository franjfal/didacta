/// Una compilación detrás de otra, «Detener» y el resumen al acabar.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/build_button.dart';
import 'package:didacta_app/ui/build_strip.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

typedef Job = ({
  String repo,
  String course,
  String year,
  String id,
  String title,
});

Job job(String id) =>
    (repo: '', course: 'am-i', year: '2026-2027', id: id, title: 'El $id');

/// Un compilador que no acaba hasta que se le dice, y que al pararlo falla
/// como falla el motor al recibir SIGTERM.
class HeldCompiler extends FakeCompiler {
  final List<String> compiled = [];
  final Set<String> failing = {};
  Completer<void>? hold;

  @override
  Future<List<BuildableProfile>> documentProfiles(String document) async =>
      const [
        BuildableProfile(
          id: 'notes',
          label: 'Apuntes',
          family: 'notes',
          byDefault: true,
        ),
      ];

  @override
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    compiled.add(document);
    if (hold case final waiting?) await waiting.future;
    final ok = !failing.contains(document);
    return [
      CompileOutput(
        profile: 'notes',
        language: 'es',
        ok: ok,
        diagnostics: [
          if (!ok)
            const CompileDiagnostic(
              severity: 'error',
              message: 'Undefined control sequence.',
              line: 9,
              unit: unitPath,
              language: 'es',
            ),
        ],
      ),
    ];
  }

  @override
  Future<void> stopCompiling() async {
    await super.stopCompiling();
    hold?.completeError(const CompileException('El motor falló (código 143).'));
    hold = null;
  }
}

Future<FakeSession> sessionWith(HeldCompiler compiler) async {
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return session;
}

void main() {
  group('la cola', () {
    test('una detrás de otra, nunca dos a la vez', () async {
      final session = await sessionWith(HeldCompiler());
      final order = <String>[];
      final first = Completer<void>();
      final a = session.runBuild('A', (console) async {
        order.add('A empieza');
        await first.future;
        order.add('A acaba');
        return 1;
      });
      final b = session.runBuild('B', (console) async {
        order.add('B empieza');
        return 2;
      });
      await Future<void>.delayed(Duration.zero);
      expect(session.queuedBuilds, 1);
      expect(session.buildConsole.title, 'A');
      first.complete();
      expect(await a, 1);
      expect(await b, 2);
      expect(order, ['A empieza', 'A acaba', 'B empieza']);
      expect(session.queuedBuilds, 0);
    });

    test('un error sin «Detener» es un error', () async {
      final session = await sessionWith(HeldCompiler());
      await expectLater(
        session.runBuild('A', (console) async => throw StateError('mal')),
        throwsStateError,
      );
      expect(session.buildConsole.ok, isFalse);
      expect(session.buildConsole.stopped, isFalse);
    });
  });

  group('Detener', () {
    test('para lo que compila y vacía la cola', () async {
      final compiler = HeldCompiler()..hold = Completer<void>();
      final session = await sessionWith(compiler);
      final batch = session.buildDocuments([
        job('tema-1'),
        job('tema-2'),
        job('tema-3'),
      ], title: 'El curso');
      final queued = session.runBuild('Otra', (console) async => 'hecha');
      await Future<void>.delayed(Duration.zero);
      expect(session.buildConsole.running, isTrue);

      await session.stopBuilds();
      expect(compiler.stops, 1);
      expect(await batch, 0);
      expect(await queued, isNull, reason: 'lo encolado ya no se compila');
      expect(compiler.compiled, ['am-i@2026-2027/tema-1']);
      expect(session.buildConsole.stopped, isTrue);
      expect(session.buildConsole.summary, 'Detenida: 0 de 3 hechos');
      expect(session.buildConsole.lines.last, '--- Detenida.');
    });

    test('sin nada compilando, no hace nada', () async {
      final compiler = HeldCompiler();
      final session = await sessionWith(compiler);
      await session.stopBuilds();
      expect(compiler.stops, 0);
    });
  });

  test('al acabar un lote, el resumen dice cómo fue', () async {
    final compiler = HeldCompiler()..failing.add('am-i@2026-2027/tema-2');
    final session = await sessionWith(compiler);
    final ok = await session.buildDocuments([
      job('tema-1'),
      job('tema-2'),
      job('tema-3'),
    ], title: 'El curso');
    expect(ok, 2);
    expect(session.buildConsole.summary, '2 bien, 1 con errores');
    expect(session.buildConsole.ok, isFalse);
    // Y el error, guardado con su documento en lugar de tirarlo.
    final problem = session.buildConsole.problems.single;
    expect(problem.what, 'El tema-2 · notes · es');
    expect(problem.diagnostic.unit, unitPath);
    expect(problem.diagnostic.line, 9);
  });

  group('en pantalla', () {
    Future<FakeSession> pumpStrip(
      WidgetTester tester,
      HeldCompiler compiler,
    ) async {
      final session = await sessionWith(compiler);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(body: BuildStrip(session: session)),
          ),
        ),
      );
      return session;
    }

    testWidgets('mientras compila, dice por cuál va y se puede detener', (
      tester,
    ) async {
      final compiler = HeldCompiler()..hold = Completer<void>();
      final session = await pumpStrip(tester, compiler);
      expect(find.byKey(const Key('build-strip')), findsNothing);

      final batch = session.buildDocuments([
        job('tema-1'),
        job('tema-2'),
      ], title: 'El curso');
      await tester.pump();
      expect(find.byKey(const Key('build-strip')), findsOneWidget);
      expect(find.text('Compilando El curso · 0/2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('build-stop')));
      await tester.pump();
      await batch;
      await tester.pump();
      expect(compiler.stops, 1);
      expect(find.byKey(const Key('build-strip')), findsNothing);
      expect(find.text('El curso: Detenida: 0 de 2 hechos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('build-summary-close')));
      await tester.pump();
      expect(find.byKey(const Key('build-summary')), findsNothing);
    });
  });

  testWidgets('un curso entero pregunta antes; un tema, no', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () async => answers.add(
                    await confirmBigBuild(
                      context,
                      documents: 2,
                      what: 'El tema',
                    ),
                  ),
                  child: const Text('poco'),
                ),
                TextButton(
                  onPressed: () async => answers.add(
                    await confirmBigBuild(
                      context,
                      documents: 38,
                      what: 'El curso',
                    ),
                  ),
                  child: const Text('mucho'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('poco'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-big-build')), findsNothing);
    expect(answers, [true]);

    await tester.tap(find.text('mucho'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-big-build')), findsOneWidget);
    expect(find.textContaining('Son 38 documentos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-big-build-go')));
    await tester.pumpAndSettle();
    expect(answers, [true, true]);
  });
}
