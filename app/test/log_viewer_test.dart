/// «Ver log completo»: qué se marca como error, cuál es el primero de verdad
/// y que el visor busca y salta entre errores.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/ui/log_viewer.dart';
import 'package:didacta_app/ui/theme.dart';

const List<String> _log = [
  'This is pdfTeX, Version 3.141592653-2.6-1.40.27 (TeX Live 2026)',
  '(./tema-1.tex',
  'LaTeX2e <2025-06-01>',
  "./tema-1.tex:3: LaTeX Error: File `tcolorbox.sty' not found.",
  '',
  'Type X to quit or <RETURN> to proceed,',
  'l.3 \\usepackage',
  './tema-1.tex:3: Emergency stop.',
  'LaTeX Warning: Reference `x\' on page 1 undefined on input line 9.',
  '! Undefined control sequence.',
  'l.12 \\foo',
  'Output written on tema-1.pdf (2 pages).',
];

void main() {
  group('leer el registro', () {
    test('marca errores, avisos y cabeceras, y nada más', () {
      expect(
        classifyLogLine('! Undefined control sequence.'),
        LogLineKind.error,
      );
      expect(
        classifyLogLine('../content/a/es.tex:9: Undefined control sequence.'),
        LogLineKind.error,
      );
      expect(
        classifyLogLine('LaTeX Warning: Citation undefined'),
        LogLineKind.warning,
      );
      expect(classifyLogLine('=== doc · slides · es'), LogLineKind.header);
      expect(classifyLogLine('(./tema-1.tex'), LogLineKind.plain);
    });

    test('los errores que son consecuencia de otro no cuentan', () {
      expect(errorStarts(_log), [3, 9]);
    });

    test('el primer error de verdad no es el «Emergency stop»', () {
      const errors = [
        CompileDiagnostic(severity: 'error', message: 'Emergency stop.'),
        CompileDiagnostic(severity: 'warning', message: 'w'),
        CompileDiagnostic(
          severity: 'error',
          message: "LaTeX Error: File `tcolorbox.sty' not found.",
          file: 'tema-1.tex',
          line: 3,
        ),
      ];
      expect(firstRealError(errors)!.line, 3);
      expect(lineOfDiagnostic(_log, firstRealError(errors)!), 3);
    });

    test('sin diagnóstico, el sitio sale del propio log', () {
      expect(whereIsLogError(_log, 3), (file: 'tema-1.tex', line: 3));
      expect(whereIsLogError(_log, 9), (file: null, line: 12));
    });
  });

  group('el visor', () {
    Future<void> pump(WidgetTester tester, List<LogSource> sources) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: LogViewerDialog(
              title: 'Log completo',
              sources: sources,
              errors: const [
                CompileDiagnostic(
                  severity: 'error',
                  message: "LaTeX Error: File `tcolorbox.sty' not found.",
                  path: 'courses/x/tema-1.tex',
                  line: 3,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('enseña el primer error con su fichero y su línea', (
      tester,
    ) async {
      await pump(tester, [const LogSource(label: 'log', lines: _log)]);
      expect(find.byKey(const Key('log-first-error')), findsOneWidget);
      expect(
        find.text('Primer error: courses/x/tema-1.tex · línea 3'),
        findsOneWidget,
      );
      expect(find.text('2 errores'), findsOneWidget);
      // Con números de línea.
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('salta de error en error', (tester) async {
      await pump(tester, [const LogSource(label: 'log', lines: _log)]);
      await tester.tap(find.byKey(const Key('log-error-next')));
      await tester.pump();
      expect(find.text('Error 1 de 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('log-error-next')));
      await tester.pump();
      expect(find.text('Error 2 de 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('log-error-next')));
      await tester.pump();
      expect(find.text('Error 1 de 2'), findsOneWidget);
    });

    testWidgets('busca y cuenta lo encontrado', (tester) async {
      await pump(tester, [const LogSource(label: 'log', lines: _log)]);
      await tester.enterText(find.byKey(const Key('log-search')), 'tema-1');
      await tester.pump();
      expect(find.text('1 de 4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('log-match-next')));
      await tester.pump();
      expect(find.text('2 de 4'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('log-search')), 'zzz');
      await tester.pump();
      expect(find.text('sin resultados'), findsOneWidget);
    });

    testWidgets('con varias fuentes, se elige cuál leer', (tester) async {
      await pump(tester, [
        const LogSource(label: 'Libro · es · .log', lines: _log),
        const LogSource(
          label: 'Salida de la compilación',
          lines: ['=== doc · book · es', 'Latexmk: todo bien'],
        ),
      ]);
      expect(find.byKey(const Key('log-sources')), findsOneWidget);
      await tester.tap(find.text('Salida de la compilación'));
      await tester.pumpAndSettle();
      expect(find.text('Latexmk: todo bien'), findsOneWidget);
      expect(find.text('Sin errores marcados'), findsOneWidget);
    });
  });
}
