/// La vista rápida: un documento en una sola pasada, para ver cómo queda.
///
/// Tarda la mitad en un tema de verdad --30 s en lugar de 54 tras añadir una
/// diapositiva--, y a cambio el índice y las referencias pueden no estar al
/// día. Por eso es de la pantalla del documento y no de los lotes, y lo que
/// sale así cuenta como desactualizado hasta que se compila entero.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/pdf_inputs.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// Apunta si se le pidió una sola pasada, y lo dice en lo que devuelve, como
/// el motor.
class _Recording extends FakeCompiler {
  final List<bool> fast = [];

  @override
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    this.fast.add(fast);
    return [
      for (final profile in profiles)
        for (final language in languages)
          CompileOutput(
            profile: profile,
            language: language,
            ok: true,
            pdf: '/salida/$profile-$language.pdf',
            pages: 3,
            quick: fast,
          ),
    ];
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<_Recording> _pumpDocument(
  WidgetTester tester, {
  required bool quick,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final compiler = _Recording();
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
    preferencesOverride: MemoryPreferences()..quick = quick,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: DocumentPage(
            courseId: 'am-iii',
            year: '2025-2026',
            documentId: 'tema-1',
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Compilar'));
  await settle(tester);
  return compiler;
}

Future<void> finish(WidgetTester tester) async {
  await settle(tester);
  // El terminal se cierra solo cuando va bien.
  await tester.pump(const Duration(seconds: 2));
  await settle(tester);
}

void main() {
  testWidgets('apagada, se compila entero como siempre', (tester) async {
    final compiler = await _pumpDocument(tester, quick: false);
    expect(find.byKey(const Key('compile-full')), findsNothing);
    expect(find.textContaining('Vista rápida'), findsNothing);

    await tester.tap(find.byKey(const Key('compile')));
    await finish(tester);
    expect(compiler.fast, [false]);
    expect(find.byKey(const Key('quick-note')), findsNothing);
  });

  testWidgets('encendida, el botón es de una pasada y lo dice el PDF', (
    tester,
  ) async {
    final compiler = await _pumpDocument(tester, quick: true);
    expect(find.textContaining('Vista rápida'), findsOneWidget);

    await tester.tap(find.byKey(const Key('compile')));
    await finish(tester);
    expect(compiler.fast, [true]);
    // Se abre el PDF, y su panel dice de dónde salió.
    expect(find.byKey(const Key('pane-quick-es')), findsOneWidget);
    expect(find.textContaining('vista rápida ·'), findsOneWidget);
  });

  testWidgets('y al lado, «Compilar entero» para lo que se reparte', (
    tester,
  ) async {
    final compiler = await _pumpDocument(tester, quick: true);
    await tester.tap(find.byKey(const Key('compile-full')));
    await finish(tester);
    expect(compiler.fast, [false]);
    expect(find.byKey(const Key('pane-quick-es')), findsNothing);
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
    expect(session.quickBuild, isFalse);
    await session.setQuickBuild(true);
    expect(preferences.quick, isTrue);
    expect(session.quickBuild, isTrue);
  });

  group('lo que dice el motor', () {
    Directory fakeEngine(String reply) {
      final root = Directory.systemTemp.createTempSync('didacta-quick-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/reply.json').writeAsStringSync(reply);
      final script = File('${root.path}/cli/didacta')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo "\$@" >> "\$(dirname "\$0")/../args.txt"\n'
          'cat "\$(dirname "\$0")/../reply.json"\n',
        );
      Process.runSync('chmod', ['+x', script.path]);
      return root;
    }

    test('una salida de una pasada llega marcada', () async {
      final root = fakeEngine(
        '[{"profile": "slides", "language": "es", "ok": true, '
        '"pdf": "/x.pdf", "pages": 3, "seconds": 1.0, "quick": true, '
        '"diagnostics": []}]',
      );
      final compiler = Compiler(
        enginePath: root.path,
        repositoryPath: root.path,
      );
      final [result] = await compiler.compileDocument(
        document: 'am-iii@2025-2026/tema-1',
        profiles: const ['slides'],
        languages: const ['es'],
        fast: true,
      );
      expect(result.quick, isTrue);
      expect(
        File('${root.path}/args.txt').readAsStringSync(),
        contains('--fast'),
      );
    });

    test('y lo compilado de una pasada, también', () async {
      final root = fakeEngine(
        '{"documents": [{"document": "tema-1", "title": "Tema 1", '
        '"outputs": [{"profile": "slides", "label": "Diapositivas", '
        '"family": "slides", "language": "es", "pdf": "/x.pdf", '
        '"exists": true, "stale": true, "quick": true, "mtime": 1}]}]}',
      );
      final compiler = Compiler(
        enginePath: root.path,
        repositoryPath: root.path,
      );
      final found = await compiler.documentOutputs('am-iii@2025-2026');
      final [output] = found['tema-1']!;
      expect(output.quick, isTrue);
      expect(output.stale, isTrue);
    });

    test('un PDF de una pasada está viejo aunque no cambie nada', () async {
      final root = Directory.systemTemp.createTempSync('didacta-quick-pdf-');
      addTearDown(() => root.deleteSync(recursive: true));
      final pdf = '${root.path}/x.pdf';
      File(pdf).writeAsStringSync('%PDF');
      final record = File('$pdf$inputsSuffix');
      record.writeAsStringSync('{"version": 1, "files": {}, "lessons": {}}');
      expect(await staleByInputs(pdf), isFalse);
      record.writeAsStringSync(
        '{"version": 1, "files": {}, "lessons": {}, "quick": true}',
      );
      expect(await staleByInputs(pdf), isTrue);
    });
  });
}
