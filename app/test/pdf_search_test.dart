/// Buscar texto en el PDF: sin mirar tildes ni mayúsculas, con ⌘F, y de un
/// resultado al siguiente.
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:typed_data' show BytesBuilder, Uint8List;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/pdf_query.dart';
import 'package:didacta_app/ui/pdf_dialog.dart';
import 'package:didacta_app/ui/pdf_tab.dart';
import 'package:didacta_app/ui/theme.dart';

/// Un PDF de verdad, escrito a mano: una página por texto, en Helvetica.
///
/// Sin LaTeX, para que la prueba no dependa de tenerlo, y con tildes, que
/// es lo que hay que encontrar sin escribirlas.
List<int> minimalPdf(List<List<String>> pages) {
  final objects = <String>[];
  final kids = [for (var i = 0; i < pages.length; i += 1) '${4 + 2 * i} 0 R'];
  objects
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add('<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>')
    ..add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
  for (var i = 0; i < pages.length; i += 1) {
    final lines = [
      for (var j = 0; j < pages[i].length; j += 1)
        'BT /F1 20 Tf 60 ${700 - 30 * j} Td (${pages[i][j].replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)')}) Tj ET',
    ].join('\n');
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + 2 * i} 0 R >>',
      )
      ..add(
        '<< /Length ${latin1.encode(lines).length} >>\nstream\n$lines\nendstream',
      );
  }
  final out = BytesBuilder();
  void write(String text) => out.add(latin1.encode(text));
  write('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i += 1) {
    offsets.add(out.length);
    write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return out.toBytes();
}

/// Si en esta máquina se puede abrir un PDF de verdad.
///
/// Hace falta PDFium, y en un `flutter test` a secas no siempre está: en el
/// Mac lo deja en `.dart_tool/` la primera compilación, pero en el Linux de
/// GitHub no hay nada que lo traiga. Sin él, las pruebas que abren un PDF se
/// saltan diciéndolo --como las que piden LaTeX-- en lugar de fallar por
/// algo que no es de Didacta.
Future<bool> pdfiumLoads() async {
  try {
    final doc = await PdfDocument.openData(
      Uint8List.fromList(
        minimalPdf([
          ['x'],
        ]),
      ),
    );
    await doc.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

/// Lo que se dice al saltar una prueba que necesita PDFium.
const String sinPdfium =
    'hace falta PDFium, y este flutter test no lo tiene '
    '(se genera al compilar la aplicación en esta máquina)';

/// Deja pasar el tiempo de verdad: pdfium lee fuera del reloj falso.
Future<void> wait(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i += 1) {
    await wait(tester, rounds: 1);
  }
}

String countText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('pdf-search-count'))).data ?? '';

void main() {
  group('el patrón', () {
    bool finds(String query, String text) =>
        pdfQueryPattern(query)!.hasMatch(text);

    test('sin tildes ni mayúsculas, en los dos sentidos', () {
      expect(finds('limite', 'El límite de una sucesión'), isTrue);
      expect(finds('LÍMITE', 'el limite'), isTrue);
      expect(finds('sucesion', 'SUCESIÓN'), isTrue);
      expect(finds('año', 'el ano'), isTrue);
      expect(finds('limite', 'limitado'), isFalse);
    });

    test('un espacio vale por un salto de línea', () {
      expect(
        finds('teorema de Bolzano', 'el teorema de\nBolzano dice'),
        isTrue,
      );
      expect(finds('teorema  de', 'teorema de'), isTrue);
    });

    test('lo demás, tal cual', () {
      expect(finds('f(x)', 'si f(x) > 0'), isTrue);
      expect(finds('a.b', 'axb'), isFalse);
      expect(finds(r'\lambda', r'con \lambda'), isTrue);
    });

    test('nada que buscar es null', () {
      expect(pdfQueryPattern(''), isNull);
      expect(pdfQueryPattern('   '), isNull);
    });
  });

  group('en el visor', () {
    late String pdf;
    var conPdfium = false;

    setUpAll(() async {
      final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => cache.path,
          );
      final dir = Directory.systemTemp.createTempSync('didacta-pdf-search-');
      pdf = '${dir.path}/tema.pdf';
      File(pdf).writeAsBytesSync(
        minimalPdf([
          ['Tema 1. Sucesiones'],
          ['Definición del límite', 'de una sucesión.'],
          ['Otra página'],
          ['El límite es único.'],
        ]),
      );
      conPdfium = await pdfiumLoads();
    });

    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
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
                    pages: 4,
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
      );
      await wait(tester, rounds: 10);
    }

    testWidgets('encuentra sin tildes y va de uno al siguiente', (
      tester,
    ) async {
      if (!conPdfium) return markTestSkipped(sinPdfium);
      await mount(tester);
      await tester.tap(find.byKey(const Key('pdf-search')));
      await wait(tester, rounds: 2);
      expect(find.byKey(const Key('pdf-search-bar')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('pdf-search-field')),
        'limite',
      );
      // Espera a terminar de escribir, y busca página a página.
      await tester.pump(const Duration(milliseconds: 600));
      await until(tester, () => countText(tester) == '1 de 2');
      expect(countText(tester), '1 de 2');

      await tester.tap(find.byKey(const Key('pdf-search-next')));
      await wait(tester, rounds: 3);
      expect(countText(tester), '2 de 2');
      // Da la vuelta.
      await tester.tap(find.byKey(const Key('pdf-search-next')));
      await wait(tester, rounds: 3);
      expect(countText(tester), '1 de 2');
      await tester.tap(find.byKey(const Key('pdf-search-prev')));
      await wait(tester, rounds: 3);
      expect(countText(tester), '2 de 2');
    });

    testWidgets('lo que no está lo dice, y Esc cierra', (tester) async {
      if (!conPdfium) return markTestSkipped(sinPdfium);
      await mount(tester);
      await tester.tap(find.byKey(const Key('pdf-search')));
      await wait(tester, rounds: 2);
      await tester.enterText(
        find.byKey(const Key('pdf-search-field')),
        'Weierstrass',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await until(tester, () => countText(tester) == 'No está');
      expect(countText(tester), 'No está');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('pdf-search-next')))
            .onPressed,
        isNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await wait(tester, rounds: 2);
      expect(find.byKey(const Key('pdf-search-bar')), findsNothing);
    });

    testWidgets('también en el diálogo de lo compilado', (tester) async {
      if (!conPdfium) return markTestSkipped(sinPdfium);
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: BuiltPdfsDialog(
              title: 'Tema 1',
              outputs: [
                ExistingOutput(
                  profile: 'notes',
                  label: 'Apuntes',
                  family: 'notes',
                  language: 'es',
                  pdf: pdf,
                  exists: true,
                  stale: true,
                  quick: true,
                ),
              ],
            ),
          ),
        ),
      );
      await wait(tester, rounds: 10);
      expect(find.textContaining('vista rápida'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-search')));
      await wait(tester, rounds: 2);
      await tester.enterText(
        find.byKey(const Key('pdf-search-field')),
        'UNICO',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await until(tester, () => countText(tester) == '1 de 1');
      expect(countText(tester), '1 de 1');
    });

    testWidgets('⌘F la abre desde el visor', (tester) async {
      if (!conPdfium) return markTestSkipped(sinPdfium);
      await mount(tester);
      // El visor toma el foco al pulsarlo, como al leer.
      await tester.tap(find.byType(PdfTabView), warnIfMissed: false);
      await wait(tester, rounds: 2);
      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      final modifier = mac
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await wait(tester, rounds: 2);
      expect(find.byKey(const Key('pdf-search-bar')), findsOneWidget);
    });
  });
}
