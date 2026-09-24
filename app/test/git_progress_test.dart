/// Lo que se entiende de lo que escribe git mientras clona, y cómo se enseña.
///
/// Se prueba porque es lo único que distingue un clon largo de una
/// aplicación colgada: si esto deja de reconocer las líneas, la barra no sale
/// y se vuelve a lo de antes, un círculo girando al lado de «Cloning into».
///
/// Las líneas son copiadas de git, con sus espacios de relleno. Y una en
/// castellano, porque git traduce sus mensajes y la aplicación no le fuerza
/// el inglés: lo que se reconoce es la forma, no las palabras.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/git_progress.dart';
import 'package:didacta_app/ui/working.dart';

void main() {
  group('una línea de git', () {
    test('lo que hace GitHub, sin el «remote:» delante', () {
      final progress = GitProgress.parse(
        'remote: Counting objects:  13% (280/2151)        ',
      )!;
      expect(progress.phase, 'Counting objects');
      expect(progress.percent, 13);
      expect(progress.done, 280);
      expect(progress.total, 2151);
      expect(progress.transfer, isEmpty);
      expect(progress.fraction, closeTo(0.13, 1e-9));
    });

    test('lo que se baja, con cuánto y a qué velocidad', () {
      final progress = GitProgress.parse(
        'Receiving objects:  45% (450/1000), 12.00 MiB | 3.00 MiB/s',
      )!;
      expect(progress.phase, 'Receiving objects');
      expect(progress.transfer, '12.00 MiB | 3.00 MiB/s');
      expect(
        progress.summary,
        'Receiving objects: 45 % (450/1000) · 12.00 MiB | 3.00 MiB/s',
      );
    });

    test('el «done» del final no se cuenta como descarga', () {
      final plain = GitProgress.parse(
        'Resolving deltas: 100% (1172/1172), done.',
      )!;
      expect(plain.percent, 100);
      expect(plain.transfer, isEmpty);

      final downloaded = GitProgress.parse(
        'Receiving objects: 100% (2151/2151), 3.07 MiB | 59.26 MiB/s, done.',
      )!;
      expect(downloaded.transfer, '3.07 MiB | 59.26 MiB/s');
    });

    test('en otro idioma se reconoce igual', () {
      final progress = GitProgress.parse(
        'remoto: Comprimiendo objetos:  50% (435/870), listo.',
      )!;
      expect(progress.phase, 'Comprimiendo objetos');
      expect(progress.percent, 50);
      expect(progress.transfer, isEmpty);
    });

    test('lo que no es progreso no se toma por progreso', () {
      for (final line in const [
        "Cloning into '.'...",
        'remote: Enumerating objects: 2151, done.',
        'remote: Total 2151 (delta 1172), reused 2151 (delta 1172)',
        "fatal: repository 'https://github.com/x/y.git/' not found",
        '',
      ]) {
        expect(GitProgress.parse(line), isNull, reason: line);
      }
    });
  });

  group('mientras trabaja', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 600, child: child)),
    );

    final bar = find.byKey(const Key('working-bar'));
    final clock = find.byKey(const Key('working-elapsed'));

    testWidgets('dice qué se clona, y debajo por dónde va git', (tester) async {
      await tester.pumpWidget(
        host(
          const Working(
            step: 'Clonando didacta/curso…',
            line: 'Receiving objects:  45% (450/1000), 12.00 MiB | 3.00 MiB/s',
          ),
        ),
      );
      expect(find.text('Clonando didacta/curso…'), findsOneWidget);
      expect(
        find.text(
          'Receiving objects: 45 % (450/1000) · 12.00 MiB | 3.00 MiB/s',
        ),
        findsOneWidget,
      );
      expect(tester.widget<LinearProgressIndicator>(bar).value, 0.45);
    });

    testWidgets('sin porcentaje no hay barra, y la línea sale tal cual', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Working(
            step: 'Clonando didacta/curso…',
            line: "Cloning into '.'...",
          ),
        ),
      );
      expect(bar, findsNothing);
      expect(find.text("Cloning into '.'..."), findsOneWidget);
    });

    testWidgets('sin paso, la línea hace de título', (tester) async {
      // Lo que pasa al instalar LaTeX o Python: no hay más que la salida.
      await tester.pumpWidget(
        host(const Working(line: '==> Downloading basictex')),
      );
      expect(find.text('==> Downloading basictex'), findsOneWidget);
    });

    testWidgets('cuenta cuánto lleva, y vuelve a cero con cada paso', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const Working(step: 'Clonando a (1 de 2)…')),
      );
      // Los primeros segundos, nada: lo corto no necesita reloj.
      await tester.pump(const Duration(seconds: 1));
      expect(clock, findsNothing);

      await tester.pump(const Duration(seconds: 4));
      expect(clock, findsOneWidget);
      expect(tester.widget<Text>(clock).data, '0:05');

      await tester.pumpWidget(
        host(const Working(step: 'Clonando b (2 de 2)…')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(clock, findsNothing);
    });
  });
}
