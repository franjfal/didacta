/// El historial de un fichero: leer lo que git contesta, y enseñarlo.
///
/// Dos mitades que se prueban distinto. El parseo del diff no necesita git: es
/// un formato con reglas, y lo que se comprueba es que los números de línea de
/// las dos columnas salgan de las cabeceras `@@` y no de contar. El historial
/// sí se prueba contra git de verdad, porque lo que se está afirmando es que
/// `git log --follow` y `git show` contestan lo que esta pantalla espera.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/model/line_diff.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/history_tab.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
    environment: const {
      'GIT_AUTHOR_NAME': 'Profe',
      'GIT_AUTHOR_EMAIL': 'profe@uv.es',
      'GIT_COMMITTER_NAME': 'Profe',
      'GIT_COMMITTER_EMAIL': 'profe@uv.es',
      'GIT_TERMINAL_PROMPT': '0',
    },
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
}

void main() {
  group('leer un diff unificado', () {
    test('los números de línea salen de la cabecera, no de contar', () {
      // Lo que esto coge: un visor que empieza a contar desde uno se
      // desincroniza en el primer trozo que no empieza al principio del
      // fichero, y entonces el número que enseña manda a la línea que no era.
      const patch = '''
diff --git a/es.tex b/es.tex
index 1234567..89abcde 100644
--- a/es.tex
+++ b/es.tex
@@ -14,4 +14,5 @@ \\section{Normas}
 Una norma es una aplicación
-que cumple tres cosas.
+que cumple estas tres:
+la desigualdad triangular,
 la homogeneidad
''';
      final diff = parseUnifiedDiff(patch);
      expect(diff.hunks, hasLength(1));

      final lines = diff.hunks.single.lines;
      expect(lines.first.kind, ChangeKind.kept);
      expect(lines.first.oldLine, 14);
      expect(lines.first.newLine, 14);

      final removed = lines.firstWhere((l) => l.kind == ChangeKind.removed);
      expect(removed.text, 'que cumple tres cosas.');
      expect(removed.oldLine, 15);
      expect(removed.newLine, isNull, reason: 'ya no está en la versión nueva');

      final added = lines.where((l) => l.kind == ChangeKind.added).toList();
      expect(added.map((l) => l.newLine), [15, 16]);
      expect(added.every((l) => l.oldLine == null), isTrue);

      // Y la última de contexto va detrás de las dos añadidas, con las dos
      // columnas ya separadas.
      expect(lines.last.oldLine, 16);
      expect(lines.last.newLine, 17);

      expect(diff.added, 2);
      expect(diff.removed, 1);
    });

    test('la cabecera dice dónde cae el trozo', () {
      // Lo que va detrás de la segunda `@@` sitúa un cambio mejor que un
      // número de línea, que es por lo que git se molesta en ponerlo.
      final diff = parseUnifiedDiff(
        '@@ -1,2 +1,2 @@ \\section{Espacios normados}\n'
        '-uno\n'
        '+dos\n',
      );
      expect(diff.hunks.single.context, r'\section{Espacios normados}');
    });

    test('varios trozos se leen como varios', () {
      final diff = parseUnifiedDiff(
        '@@ -1,1 +1,1 @@\n'
        '-uno\n'
        '+UNO\n'
        '@@ -40,1 +40,1 @@\n'
        '-cuarenta\n'
        '+CUARENTA\n',
      );
      expect(diff.hunks, hasLength(2));
      expect(diff.hunks.last.lines.first.oldLine, 40);
    });

    test('un renombrado se dice', () {
      final diff = parseUnifiedDiff(
        'diff --git a/viejo.tex b/nuevo.tex\n'
        'similarity index 98%\n'
        'rename from content/a/viejo.tex\n'
        'rename to content/b/nuevo.tex\n',
      );
      expect(diff.renamedFrom, 'content/a/viejo.tex');
    });

    test('un binario se dice en lugar de fingir un diff', () {
      final diff = parseUnifiedDiff(
        'diff --git a/figura.png b/figura.png\n'
        'Binary files a/figura.png and b/figura.png differ\n',
      );
      expect(diff.isBinary, isTrue);
    });

    test('el aviso de que falta el salto final no es una línea', () {
      // `\\ No newline at end of file` no es contenido del fichero, y contarla
      // como tal haría que el diff dijera una línea de más.
      final diff = parseUnifiedDiff(
        '@@ -1,1 +1,1 @@\n'
        '-uno\n'
        '\\ No newline at end of file\n'
        '+dos\n',
      );
      expect(diff.hunks.single.lines, hasLength(2));
      expect(diff.added, 1);
      expect(diff.removed, 1);
    });

    test('un commit que no cambió el contenido se nota', () {
      expect(parseUnifiedDiff('').isEmpty, isTrue);
    });
  });

  group('contra git de verdad', () {
    late Directory root;
    late LocalClone clone;
    const file = 'content/analysis/normed/def/es.tex';

    setUp(() async {
      root = await Directory.systemTemp.createTemp('didacta-historial-');
      await Directory(
        '${root.path}/content/analysis/normed/def',
      ).create(recursive: true);
      await git(['init', '--initial-branch=main', '.'], root.path);

      File('${root.path}/$file').writeAsStringSync('Primera versión.\n');
      await git(['add', '.'], root.path);
      await git(['commit', '-m', 'La primera versión'], root.path);

      File(
        '${root.path}/$file',
      ).writeAsStringSync('Primera versión.\nY una línea más.\n');
      await git(['commit', '-am', 'Añadir una línea'], root.path);

      clone = LocalClone(directory: root.path);
    });

    tearDown(() => root.delete(recursive: true));

    test('los commits que tocaron el fichero, del último al primero', () async {
      final history = await clone.history(file);

      expect(history, hasLength(2));
      expect(history.first.subject, 'Añadir una línea');
      expect(history.last.subject, 'La primera versión');
      expect(history.first.author, 'Profe');
      expect(history.first.email, 'profe@uv.es');
      expect(history.first.shortSha, hasLength(7));
      expect(history.first.when.isAfter(DateTime(2000)), isTrue);
    });

    test('solo los de ese fichero', () async {
      File('${root.path}/otro.tex').writeAsStringSync('Otra cosa.\n');
      await git(['add', '.'], root.path);
      await git(['commit', '-m', 'Otro fichero'], root.path);

      final history = await clone.history(file);
      expect(history.map((c) => c.subject), isNot(contains('Otro fichero')));
    });

    test('un fichero movido conserva su historial', () async {
      // `--follow`. Reorganizar `content/` pasa, y sin esto una unidad movida
      // abre su historial vacía, como si se acabara de escribir.
      const moved = 'content/analysis/normed/definicion/es.tex';
      await Directory(
        '${root.path}/content/analysis/normed/definicion',
      ).create(recursive: true);
      await git(['mv', file, moved], root.path);
      await git(['commit', '-m', 'Mover la unidad'], root.path);

      final history = await clone.history(moved);
      expect(history, hasLength(3));
      expect(history.map((c) => c.subject), contains('La primera versión'));
    });

    test('el diff de un commit es lo que ese commit cambió', () async {
      final history = await clone.history(file);
      final diff = await clone.diffOf(sha: history.first.sha, path: file);

      expect(diff.added, 1);
      expect(diff.removed, 0);
      final added = diff.hunks.single.lines.firstWhere(
        (l) => l.kind == ChangeKind.added,
      );
      expect(added.text, 'Y una línea más.');
    });

    test('el diff del primer commit es el fichero entero', () async {
      final history = await clone.history(file);
      final diff = await clone.diffOf(sha: history.last.sha, path: file);

      expect(diff.removed, 0);
      expect(diff.added, 1);
      expect(diff.hunks.single.lines.single.text, 'Primera versión.');
    });

    test('un asunto con caracteres raros no rompe el parseo', () async {
      // El separador es una unidad de separación de ASCII y no una coma, que
      // es lo que hace que esto siga funcionando el día que alguien escriba
      // un mensaje con comas, tabuladores y saltos dentro.
      File('${root.path}/$file').writeAsStringSync('Tres.\n');
      await git([
        'commit',
        '-am',
        'Quitar comas, tabuladores\ty lo que sea',
      ], root.path);

      final history = await clone.history(file);
      expect(history.first.subject, 'Quitar comas, tabuladores\ty lo que sea');
      expect(history, hasLength(3));
    });

    test('el límite se respeta: un historial se lee por arriba', () async {
      expect(await clone.history(file, limit: 1), hasLength(1));
    });

    test('el fichero entero trae también lo que no cambió', () async {
      // Lo que esto coge: un contexto de tres líneas contesta «qué tocó este
      // commit», no «cómo estaba el fichero ese día», que es lo que se viene
      // a leer. Con el fichero entero las dos preguntas se contestan a la vez.
      final history = await clone.history(file);
      final diff = await clone.diffOf(
        sha: history.first.sha,
        path: file,
        context: LocalClone.wholeFile,
      );

      final lines = diff.hunks.single.lines;
      expect(lines.map((l) => l.text), [
        'Primera versión.',
        'Y una línea más.',
      ]);
      expect(lines.first.kind, ChangeKind.kept);
      expect(lines.last.kind, ChangeKind.added);
      // Y sigue contando solo lo que cambió: el contexto no es un cambio.
      expect(diff.added, 1);
      expect(diff.removed, 0);
    });

    test('el contenido de una versión se lee tal cual', () async {
      final history = await clone.history(file);

      expect(
        await clone.fileAt(sha: history.last.sha, path: file),
        'Primera versión.',
      );
      expect(
        await clone.fileAt(sha: history.first.sha, path: file),
        'Primera versión.\nY una línea más.',
      );
    });

    test('una versión en la que el fichero no estaba se dice', () async {
      // Null y no una excepción: que un fichero no existiera todavía es una
      // respuesta, y quien pregunta tiene que poder enseñarla.
      final history = await clone.history(file);
      expect(
        await clone.fileAt(sha: history.last.sha, path: 'content/otro.tex'),
        isNull,
      );
    });
  });

  group('la pantalla', () {
    Future<FakeClone> pump(
      WidgetTester tester,
      FakeClone clone, {
      Size size = const Size(1200, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final catalogue = catalogueWith([unitJson()]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        cloneOverride: clone,
      );
      await session.primeForTest(catalogue);

      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: HistoryTab(
                state: HistoryState(
                  session: session,
                  repo: null,
                  path: 'content/a/b/c/es.tex',
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      return clone;
    }

    testWidgets('enseña los commits y abre el último', (tester) async {
      // El último abierto de entrada: es el que se viene a mirar nueve de cada
      // diez veces, y pedir un clic para enseñar lo obvio es media pantalla
      // que sobra.
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'aaaaaaabbbbbbb',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'Reescribir la definición',
          ),
          FileCommit(
            sha: 'cccccccddddddd',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 3, 2),
            subject: 'La primera versión',
          ),
        ]
        ..diffs['aaaaaaabbbbbbb'] = parseUnifiedDiff(
          '@@ -1,1 +1,1 @@\n-lo viejo\n+lo nuevo\n',
        );

      await pump(tester, clone);

      expect(find.text('Reescribir la definición'), findsWidgets);
      expect(find.text('La primera versión'), findsOneWidget);
      // Y su diff, ya cargado, con el texto de las dos versiones.
      expect(clone.diffAsked, ['aaaaaaabbbbbbb:content/a/b/c/es.tex']);
      expect(find.text('lo viejo'), findsOneWidget);
      expect(find.text('lo nuevo'), findsOneWidget);
    });

    testWidgets('pulsar otro commit enseña su diff', (tester) async {
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'nuevo000',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'El último',
          ),
          FileCommit(
            sha: 'viejo000',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 3, 2),
            subject: 'El primero',
          ),
        ]
        ..diffs['nuevo000'] = parseUnifiedDiff('@@ -1,1 +1,1 @@\n+reciente\n')
        ..diffs['viejo000'] = parseUnifiedDiff('@@ -1,1 +1,1 @@\n+antiguo\n');

      await pump(tester, clone);
      expect(find.text('reciente'), findsOneWidget);

      await tester.tap(find.byKey(const Key('commit-viejo000')));
      await settle(tester);

      expect(find.text('antiguo'), findsOneWidget);
      expect(find.text('reciente'), findsNothing);
    });

    testWidgets('se abre el fichero entero, no el recorte', (tester) async {
      // Lo que se viene a ver es cómo estaba la unidad ese día. Un diff de
      // tres líneas alrededor del cambio enseña un cambio suelto sin el texto
      // al que pertenece, que es media respuesta.
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'aaaaaaabbbbbbb',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'Reescribir la definición',
          ),
        ]
        ..diffs['aaaaaaabbbbbbb'] = parseUnifiedDiff(
          '@@ -1,3 +1,3 @@\n lo de siempre\n-lo viejo\n+lo nuevo\n lo de abajo\n',
        );

      await pump(tester, clone);

      expect(clone.contextAsked, [LocalClone.wholeFile]);
      // El contenido, con lo que cambió marcado dentro.
      expect(find.text('lo de siempre'), findsOneWidget);
      expect(find.text('lo de abajo'), findsOneWidget);
      expect(find.text('lo viejo'), findsOneWidget);
      expect(find.text('lo nuevo'), findsOneWidget);
    });

    testWidgets('el commit no se enseña hasta que se pide', (tester) async {
      // Lo que ocupa la pantalla es el contenido. Quién lo escribió y con qué
      // mensaje es información sobre el cambio, no el cambio, y va detrás de
      // un botón.
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'aaaaaaabbbbbbb',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'Reescribir la definición',
            body: 'La de antes se entendía mal.',
          ),
        ]
        ..diffs['aaaaaaabbbbbbb'] = parseUnifiedDiff(
          '@@ -1,1 +1,1 @@\n+lo nuevo\n',
        );

      await pump(tester, clone);

      expect(find.text('La de antes se entendía mal.'), findsNothing);
      expect(find.text('aaaaaaabbbbbbb'), findsNothing);
      // Pero sí se dice de qué versión es lo que se está leyendo.
      expect(find.text('Versión del 10/09/2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('commit-info')));
      await tester.pumpAndSettle();

      expect(find.text('La de antes se entendía mal.'), findsOneWidget);
      expect(find.text('aaaaaaabbbbbbb'), findsOneWidget);
      expect(find.text('Javier <javier@uv.es>'), findsOneWidget);
      expect(find.text('10/09/2026 00:00'), findsOneWidget);
    });

    testWidgets('un commit que no tocó el contenido enseña la versión', (
      tester,
    ) async {
      // Un renombrado no cambia ni una línea, y aun así hay un fichero que
      // enseñar. De git no sale diff, así que el contenido se pide aparte.
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'movido00',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'Mover la unidad',
          ),
        ]
        ..contents['movido00'] = 'Una línea.\nY otra.';

      await pump(tester, clone);

      expect(find.text('Una línea.'), findsOneWidget);
      expect(find.text('Y otra.'), findsOneWidget);
    });

    testWidgets('en una ventana estrecha sigue cabiendo', (tester) async {
      // Una fila que se desborda es un error en las pruebas, así que basta
      // con montarla estrecha: lo que esto coge es la barra de la versión,
      // que lleva fecha, hash, la marca de «ahora» y los dos contadores.
      final clone = FakeClone()
        ..log['content/a/b/c/es.tex'] = [
          FileCommit(
            sha: 'aaaaaaabbbbbbb',
            author: 'Javier',
            email: 'javier@uv.es',
            when: DateTime(2026, 9, 10),
            subject: 'Reescribir la definición',
          ),
        ]
        ..diffs['aaaaaaabbbbbbb'] = parseUnifiedDiff(
          '@@ -1,1 +1,1 @@\n-lo viejo\n+lo nuevo\n',
        );

      await pump(tester, clone, size: const Size(420, 700));

      expect(find.text('Versión del 10/09/2026'), findsOneWidget);
      expect(find.text('lo nuevo'), findsOneWidget);
    });

    testWidgets('un fichero sin historial lo dice', (tester) async {
      await pump(tester, FakeClone());
      expect(find.textContaining('todavía no tiene historial'), findsOneWidget);
    });

    testWidgets('pregunta por el fichero que se está mirando', (tester) async {
      final clone = await pump(tester, FakeClone());
      expect(clone.historyAsked, ['content/a/b/c/es.tex']);
    });
  });
}
