/// Diapositivas que se salen por abajo y líneas que se salen por la derecha.
///
/// Compilan, y por eso no se veían: el motor las descartaba, y una
/// diapositiva cortada no la nota nadie hasta que se proyecta.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/build_console.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/build_console.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_preview.dart';

import 'fixture.dart';

const Map<String, dynamic> slideJson = {
  'severity': 'warning',
  'message': 'La diapositiva se sale por abajo 60 pt (en 3 páginas)',
  'file': '../../../$unitPath/es.tex',
  'line': 12,
  'path': '$unitPath/es.tex',
  'unit': unitPath,
  'language': 'es',
  'code': 'overfull-slide',
  'points': 59.9,
  'times': 3,
};

final CompileDiagnostic slide = CompileDiagnostic.fromJson(slideJson);

/// Un motor de mentira que apunta con qué se le llamó y contesta [reply]
/// a `preview` y una lista con lo mismo a `build`.
Directory fakeEngine(String reply) {
  final root = Directory.systemTemp.createTempSync('didacta-overflow-');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${root.path}/preview.json').writeAsStringSync(reply);
  File('${root.path}/build.json').writeAsStringSync('[${resultJson()}]');
  final script = File('${root.path}/cli/didacta')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'echo "\$@" >> "\$(dirname "\$0")/../args.txt"\n'
      'cat "\$(dirname "\$0")/../\$1.json"\n',
    );
  Process.runSync('chmod', ['+x', script.path]);
  return root;
}

String argsIn(Directory root) =>
    File('${root.path}/args.txt').readAsStringSync();

String resultJson() =>
    '{"profile": "slides", "language": "es", "ok": true, '
    '"pdf": "/x.pdf", "pages": 3, "seconds": 1.0, "diagnostics": ['
    '{"severity": "warning", "message": "Reference `a\' undefined"}, '
    '${_encode(slideJson)}]}';

String _encode(Map<String, dynamic> json) => [
  '{',
  [
    for (final entry in json.entries)
      '"${entry.key}": '
          '${entry.value is String ? '"${entry.value}"' : entry.value}',
  ].join(', '),
  '}',
].join();

class _Compiler extends FakeCompiler {
  @override
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async => [
    CompileOutput(
      profile: 'slides',
      language: 'es',
      ok: true,
      pdf: '/salida/slides-es.pdf',
      pages: 3,
      diagnostics: [slide],
    ),
  ];
}

class _Host extends StatefulWidget {
  const _Host({required this.unit, required this.session});

  final Unit unit;
  final Session session;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  PreviewState? _state;

  @override
  Widget build(BuildContext context) => UnitPreview(
    onOpen: (_) {},
    state: _state ??= PreviewState(
      target: UnitTarget(widget.unit),
      session: widget.session,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onCompiled: (_) {},
    ),
    onExternal: (path, {required bool reveal}) {},
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('el modelo', () {
    test('lee qué es, cuánto se sale y en cuántas páginas', () {
      expect(slide.code, 'overfull-slide');
      expect(slide.points, 59.9);
      expect(slide.times, 3);
      expect(slide.isOverflow, isTrue);
      expect(slide.isError, isFalse);
      expect(
        CompileDiagnostic.fromJson(const {'message': 'x'}).isOverflow,
        isFalse,
      );
    });

    test('una salida separa lo que se sale de lo demás', () {
      final output = CompileOutput(
        profile: 'slides',
        language: 'es',
        ok: true,
        diagnostics: [
          slide,
          const CompileDiagnostic(severity: 'warning', message: 'otro'),
        ],
      );
      expect(output.overflowDiagnostics, [slide]);
      expect(output.errorDiagnostics, isEmpty);
    });
  });

  group('el motor', () {
    test('lo que se sale no entra en los avisos de texto', () async {
      final root = fakeEngine('{"ok": true, "results": [${resultJson()}]}');
      final compiler = Compiler(
        enginePath: root.path,
        repositoryPath: root.path,
      );
      final [result] = await compiler.compile(
        unitPath: unitPath,
        profiles: const ['slides'],
        languages: const ['es'],
      );
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('Reference'));
      final [overflow] = result.overflowDiagnostics;
      expect(overflow.unit, unitPath);
      expect(overflow.line, 12);
    });

    test('las líneas de los apuntes, solo si se piden', () async {
      final root = fakeEngine('{"ok": true, "results": []}');
      await Compiler(enginePath: root.path, repositoryPath: root.path).compile(
        unitPath: unitPath,
        profiles: const ['notes'],
        languages: const ['es'],
      );
      expect(argsIn(root), isNot(contains('--overfull-lines')));

      final asked = fakeEngine('{"ok": true, "results": []}');
      final compiler = Compiler(
        enginePath: asked.path,
        repositoryPath: asked.path,
        overfullLines: true,
      );
      await compiler.compile(
        unitPath: unitPath,
        profiles: const ['notes'],
        languages: const ['es'],
      );
      await compiler.compileDocument(
        document: 'am-i@2026-2027/tema-1',
        profiles: const ['notes'],
        languages: const ['es'],
      );
      final calls = argsIn(asked).trim().split('\n');
      expect(calls, hasLength(2));
      expect(calls[0], startsWith('preview'));
      expect(calls[1], startsWith('build'));
      for (final call in calls) {
        expect(call, contains('--overfull-lines'));
      }
    });

    test('la preferencia se guarda y la tiene la sesión', () async {
      final preferences = MemoryPreferences();
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: preferences,
      );
      await session.primeForTest(catalogue);
      expect(session.overfullLines, isFalse);
      await session.setOverfullLines(true);
      expect(preferences.overfull, isTrue);
      expect(session.overfullLines, isTrue);
    });
  });

  testWidgets('la vista previa dice qué diapositiva se sale y lleva allí', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: _Compiler(),
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: _Host(
              unit: catalogue.unitByPath(unitPath)!,
              session: session,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('compile')));
    await settle(tester);
    // El terminal se cierra solo al ir bien; lo que queda es la tarjeta.
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(find.byKey(const Key('overflow-diagnostics')), findsOneWidget);
    expect(
      find.textContaining('La diapositiva se sale por abajo 60 pt'),
      findsOneWidget,
    );
    expect(find.textContaining('línea 12'), findsOneWidget);
    expect(
      find.byKey(const Key('diagnostic-open-$unitPath-12')),
      findsOneWidget,
    );
  });

  testWidgets('en un lote, el terminal lo dice aparte de los errores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    final console = BuildConsole();
    addTearDown(console.dispose);
    console.start('Compilando el curso');
    console.addProblems('Tema 1 · slides · es', [slide]);
    console.finish();

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(body: BuildConsoleDialog(console: console)),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Se salen de la página: 1 salida'), findsOneWidget);

    console.start('Otra vez');
    console.addProblems('Tema 2 · notes · es', const [
      CompileDiagnostic(
        severity: 'error',
        message: 'Undefined control sequence.',
      ),
    ]);
    console.addProblems('Tema 1 · slides · es', [slide]);
    console.finish(ok: false);
    await settle(tester);
    expect(
      find.text('Con errores: 1 salida · 1 que se sale de la página'),
      findsOneWidget,
    );
  });
}
