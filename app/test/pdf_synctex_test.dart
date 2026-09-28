/// ⌘+clic en el PDF: a la lección y a la línea de donde sale.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/pdf_synctex.dart';
import 'package:didacta_app/ui/pdf_tab.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';
import 'pdf_search_test.dart' show minimalPdf, pdfiumLoads, sinPdfium, wait;

/// Una fila de letras de 10 × 10 puntos, de izquierda a derecha, en la
/// altura [top]; los saltos de línea bajan una fila.
List<PdfRect> rectsFor(String text) {
  final rects = <PdfRect>[];
  var x = 0.0;
  var top = 100.0;
  for (final char in text.split('')) {
    if (char == '\n') {
      rects.add(PdfRect(x, top, x, top - 10));
      x = 0;
      top -= 20;
      continue;
    }
    rects.add(PdfRect(x, top, x + 10, top - 10));
    x += 10;
  }
  return rects;
}

Future<FakeSession> prime(FakeCompiler compiler) async {
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);
  return session;
}

void main() {
  group('lo que hay bajo el cursor', () {
    const text = 'Definición del límite\nde una sucesión.';
    final rects = rectsFor(text);

    test('la palabra pulsada y su línea', () {
      // «límite» empieza en la letra 15: x de 150 a 210, y de 90 a 100.
      final found = wordAndLineAt(text, rects, const PdfPoint(165, 95));
      expect(found.word, 'límite');
      expect(found.line, 'Definición del límite');
    });

    test('entre dos palabras, la de al lado', () {
      final found = wordAndLineAt(text, rects, const PdfPoint(102, 95));
      expect(found.word, 'Definición');
    });

    test('lejos de todo, nada', () {
      final found = wordAndLineAt(text, rects, const PdfPoint(500, 500));
      expect(found.word, isNull);
      expect(found.line, isNull);
    });
  });

  group('lo que contesta el motor', () {
    Future<(SourceSpot?, String)> ask(String reply) async {
      final root = Directory.systemTemp.createTempSync('didacta-synctex-cli-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/reply.json').writeAsStringSync(reply);
      final script = File('${root.path}/cli/didacta')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo "\$@" > "\$(dirname "\$0")/../args.txt"\n'
          'cat "\$(dirname "\$0")/../reply.json"\n',
        );
      Process.runSync('chmod', ['+x', script.path]);
      final compiler = Compiler(
        enginePath: root.path,
        repositoryPath: root.path,
      );
      final spot = await compiler.sourceAt(
        pdf: '/x.pdf',
        page: 3,
        x: 12.5,
        y: 40,
        word: 'límite',
        text: 'El límite es único.',
      );
      return (spot, File('${root.path}/args.txt').readAsStringSync());
    }

    test('la lección, su idioma y su línea', () async {
      final (spot, args) = await ask(
        '{"found": {"file": "/r/$unitPath/va.tex", "line": 7, '
        '"path": "$unitPath/va.tex", "unit": "$unitPath", "language": "va"}}',
      );
      expect(spot!.unit, unitPath);
      expect(spot.language, 'va');
      expect(spot.line, 7);
      expect(args, contains('synctex /x.pdf --page 3 --x 12.50 --y 40.00'));
      expect(args, contains('--word límite'));
    });

    test('nada en ese punto es null, y un problema se dice', () async {
      expect((await ask('{"found": null}')).$1, isNull);
      expect(
        () => ask('{"error": "este PDF no tiene su .synctex.gz"}'),
        throwsA(
          isA<CompileException>().having(
            (e) => e.message,
            'message',
            contains('synctex.gz'),
          ),
        ),
      );
    });
  });

  group('a dónde lleva', () {
    Future<String?> open(WidgetTester tester, FakeCompiler compiler) async {
      final session = await prime(compiler);
      String? went;
      late BuildContext host;
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp.router(
            theme: didactaTheme(),
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, _) {
                    host = context;
                    return const Scaffold(body: SizedBox());
                  },
                ),
              ],
              errorBuilder: (_, state) {
                went = '${state.uri}';
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );
      await openSourceAt(
        host,
        session,
        const SourceRequest(pdf: '/x.pdf', page: 2, x: 10, y: 20, word: 'w'),
      );
      await tester.pumpAndSettle();
      return went;
    }

    testWidgets('a la lección, en su idioma y en su línea', (tester) async {
      final compiler = FakeCompiler()
        ..sourceSpot = const SourceSpot(
          file: '/repo/$unitPath/va.tex',
          line: 12,
          path: '$unitPath/va.tex',
          unit: unitPath,
          language: 'va',
        );
      final went = await open(tester, compiler);
      expect(went, contains(Uri.encodeFull(unitPath).split('/').last));
      expect(went, contains('linea=12'));
      expect(went, contains('va'));
      expect(compiler.askedSource.single.page, 2);
      expect(compiler.askedSource.single.word, 'w');
    });

    testWidgets('lo del documento lo dice, sin irse', (tester) async {
      final compiler = FakeCompiler()
        ..sourceSpot = const SourceSpot(
          file: '/repo/courses/am-iii/2025-2026/tema-1.tex',
          line: 17,
          path: 'courses/am-iii/2025-2026/tema-1.tex',
        );
      final went = await open(tester, compiler);
      expect(went, isNull);
      expect(
        find.textContaining('courses/am-iii/2025-2026/tema-1.tex'),
        findsOneWidget,
      );
      expect(find.textContaining('línea 17'), findsOneWidget);
    });

    testWidgets('donde no hay nada, lo dice', (tester) async {
      final went = await open(tester, FakeCompiler());
      expect(went, isNull);
      expect(
        find.textContaining('no hay nada que venga de un fichero'),
        findsOneWidget,
      );
    });
  });

  testWidgets('⌘+clic en el visor pregunta por ese punto y esa palabra', (
    tester,
  ) async {
    if (!(await tester.runAsync(pdfiumLoads) ?? false)) {
      return markTestSkipped(sinPdfium);
    }
    final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
    final dir = Directory.systemTemp.createTempSync('didacta-synctex-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pdf = '${dir.path}/tema.pdf';
    File(pdf).writeAsBytesSync(
      minimalPdf([
        ['Definición del límite'],
      ]),
    );
    final compiler = FakeCompiler();
    final session = await prime(compiler);

    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: PdfTabView(
              group: PdfGroup(
                id: 'notes',
                panes: [
                  OpenPdf(
                    path: pdf,
                    profile: 'notes',
                    language: 'es',
                    pages: 1,
                  ),
                ],
              ),
              onOpenExternally: (_) {},
              onReveal: (_) {},
              onRecompile: () {},
              onRecompilePane: (_) {},
              onDetach: (_) {},
            ),
          ),
        ),
      ),
    );
    await wait(tester, rounds: 10);

    // El punto de la página donde está «límite»: la línea empieza en x = 60
    // y su base en y = 700 (desde abajo), en Helvetica de 20 puntos.
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer.controller!;
    final page = controller.layout.pageLayouts.first;
    final scale = page.width / 612;
    final inPage = Offset(60 + 170, 792 - 706);
    final global = controller.documentToGlobal(page.topLeft + inPage * scale)!;

    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = mac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    // Sin ⌘, el clic es del visor.
    await tester.tapAt(global);
    await wait(tester, rounds: 3);
    expect(compiler.askedSource, isEmpty);

    await tester.sendKeyDownEvent(modifier);
    await tester.tapAt(global);
    await tester.sendKeyUpEvent(modifier);
    await wait(tester, rounds: 6);
    final [asked] = compiler.askedSource;
    expect(asked.pdf, pdf);
    expect(asked.page, 1);
    expect(asked.word, 'límite');
    // Desde arriba, como SyncTeX: la línea está a ~90 puntos del borde.
    expect(asked.y, closeTo(86, 3));
    expect(asked.x, closeTo(230, 3));
    // Donde no hay nada que venga de un fichero, lo dice.
    expect(
      find.textContaining('no hay nada que venga de un fichero'),
      findsOneWidget,
    );
  });
}
