/// Quitar un repositorio llevándose su carpeta, abrirla en el Finder, y
/// dejar Didacta como recién instalada.
///
/// Con clones de verdad, porque lo que se dice antes de tirar una carpeta
/// --cuánto trabajo hay sin enviar-- sale de git. Y con un explorador de
/// archivos de mentira ([RecordingFileManager]), porque tirar carpetas de
/// verdad en una prueba no demuestra nada más que apuntar cuáles.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/model/catalogue.dart' show supportedSchemaVersion;
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/start_over.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import 'fixture.dart';

Future<void> _git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
    environment: const {
      'GIT_AUTHOR_NAME': 'Alguien',
      'GIT_AUTHOR_EMAIL': 'alguien@example.com',
      'GIT_COMMITTER_NAME': 'Alguien',
      'GIT_COMMITTER_EMAIL': 'alguien@example.com',
    },
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
}

/// Un repositorio `x/<name>` con su remoto, clonado bajo [base].
Future<String> _repo(String root, String base, String name) async {
  await Directory('$root/x').create(recursive: true);
  final remote = '$root/x/$name.git';
  final seed = '$root/$name-seed';
  await _git(['init', '--bare', '--initial-branch=main', remote], root);
  await Directory('$seed/content/a/b').create(recursive: true);
  File('$seed/content/a/b/es.tex').writeAsStringSync('De $name.\n');
  File('$seed/didacta.yaml').writeAsStringSync('name: $name\n');
  File('$seed/.gitignore').writeAsStringSync('generated/\n');
  await _git(['init', '--initial-branch=main', seed], root);
  await _git(['add', '.'], seed);
  await _git(['commit', '-m', 'Semilla'], seed);
  await _git(['remote', 'add', 'origin', remote], seed);
  await _git(['push', '-u', 'origin', 'main'], seed);
  final clone = '$base/$name';
  await _git(['clone', '--branch', 'main', remote, clone], root);
  // Un índice vacío y válido: Ajustes necesita un catálogo, y el de un clon
  // sale de lo que el motor deja en `generated/`.
  await Directory('$clone/generated').create();
  for (final (file, list) in [
    ('manifest', null),
    ('units', 'units'),
    ('courses', 'courses'),
  ]) {
    File('$clone/generated/$file.json').writeAsStringSync(
      jsonEncode({'schemaVersion': supportedSchemaVersion, ?list: const []}),
    );
  }
  return clone;
}

void main() {
  late Directory root;
  late String base;
  late String uno;
  late String dos;
  late RecordingFileManager files;
  late MemoryPreferences preferences;
  late StubStore token;
  late MemoryTranslationSecrets secrets;

  Future<LocalSession> started() async {
    final session = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: token,
      preferences: preferences,
      translationSecrets: secrets,
      files: files,
    );
    await session.start();
    return session;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-quitar-');
    base = '${root.path}/Didacta';
    uno = await _repo(root.path, base, 'uno');
    dos = await _repo(root.path, base, 'dos');
    files = RecordingFileManager();
    token = StubStore();
    secrets = MemoryTranslationSecrets();
    await secrets.write(
      TranslationProvider.azure,
      const Credentials(key: 'clave-de-azure'),
    );
    preferences = MemoryPreferences(
      base: base,
      repos: Workspace([
        ContentRepo(owner: 'x', name: 'uno', directory: uno),
        ContentRepo(owner: 'x', name: 'dos', directory: dos),
      ]).toJson(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('quitar un repositorio', () {
    test('como siempre, la carpeta se queda', () async {
      final session = await started();
      final problem = await session.removeRepository('x/uno');
      expect(problem, isNull);
      expect(session.workspace.repos.map((r) => r.id), ['x/dos']);
      expect(files.trashed, isEmpty);
    });

    test('si se pide, la carpeta va a la Papelera', () async {
      final session = await started();
      final problem = await session.removeRepository(
        'x/uno',
        trashFolder: true,
      );
      expect(problem, isNull);
      expect(files.trashed, [uno]);
      expect(session.workspace.repos.map((r) => r.id), ['x/dos']);
    });

    test('una que no se deja tirar se queda, y se dice', () async {
      files.canTrash = false;
      final session = await started();
      final problem = await session.removeRepository(
        'x/uno',
        trashFolder: true,
      );
      expect(problem, contains('sigue donde estaba'));
      // Quitarlo de la lista sí se ha hecho: es lo que se pidió primero.
      expect(session.workspace.repos.map((r) => r.id), ['x/dos']);
    });

    test('nunca la carpeta donde se clonan todos', () async {
      // Una lista mal guardada que apunta a la carpeta de los clones: tirarla
      // se llevaría también el otro repositorio.
      preferences.repos = Workspace([
        ContentRepo(owner: 'x', name: 'uno', directory: base),
        ContentRepo(owner: 'x', name: 'dos', directory: dos),
      ]).toJson();
      final session = await started();
      final problem = await session.removeRepository(
        'x/uno',
        trashFolder: true,
      );
      expect(problem, contains('se clonan todos'));
      expect(files.trashed, isEmpty);
    });
  });

  group('restablecer', () {
    test(
      'borra la sesión, las claves y los ajustes, y la bienvenida vuelve',
      () async {
        final session = await started();
        final problems = await session.resetEverything();
        expect(problems, isEmpty);
        expect(token.token, isNull);
        expect((await secrets.read(TranslationProvider.azure)).isEmpty, isTrue);
        expect(preferences.cleared, isTrue);
        expect(preferences.welcome, isFalse);
        expect(preferences.repos, isNull);
        // Las carpetas, sólo si se pide.
        expect(files.trashed, isEmpty);
      },
    );

    test('las carpetas, a la Papelera, si se marca', () async {
      final session = await started();
      await session.resetEverything(folders: true);
      expect(files.trashed, unorderedEquals([uno, dos]));
    });

    test('una carpeta que no se tira no deja la sesión abierta', () async {
      files.canTrash = false;
      final session = await started();
      final problems = await session.resetEverything(folders: true);
      expect(problems, hasLength(2));
      expect(token.token, isNull);
      expect(preferences.cleared, isTrue);
    });
  });

  group('en Ajustes', () {
    Future<void> settleReal(WidgetTester tester, {int rounds = 8}) async {
      for (var round = 0; round < rounds; round += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<Session> pumpSettings(WidgetTester tester) async {
      final session = (await tester.runAsync(started))!;
      tester.view.physicalSize = const Size(1280, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: session),
            ChangeNotifierProvider<McpService>(
              create: (_) => McpService(
                openRunner: () =>
                    const UnavailableRunner('Sin servidor en las pruebas.'),
              ),
            ),
            ChangeNotifierProvider<UpdateService>(
              create: (_) => offlineUpdates(),
            ),
            ChangeNotifierProvider<TourController>(
              create: (_) => TourController(),
            ),
          ],
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await settleReal(tester);
      return session;
    }

    testWidgets('la carpeta de un repositorio se abre en el Finder', (
      tester,
    ) async {
      await pumpSettings(tester);
      final open = find.byKey(const Key('repo-open-x/uno'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await settleReal(tester);
      expect(files.opened, [uno]);
    });

    testWidgets('quitar pregunta, avisa de lo que hay sin guardar y tira', (
      tester,
    ) async {
      File('$uno/content/a/b/es.tex').writeAsStringSync('A medias.\n');
      final session = await pumpSettings(tester);

      final remove = find.byKey(const Key('repo-remove-x/uno'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await settleReal(tester);

      final dialog = find.byType(AlertDialog);
      expect(find.text('Quitar x/uno'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text(uno)),
        findsOneWidget,
      );
      expect(find.textContaining('un cambio sin guardar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-trash-folder')));
      // Quitarlo vuelve a mirar los repositorios con git: más rato.
      await settleReal(tester, rounds: 30);

      expect(files.trashed, [uno]);
      expect(session.workspace.repos.map((r) => r.id), ['x/dos']);
      expect(find.textContaining('está en la Papelera'), findsOneWidget);
    });

    testWidgets('cancelar no quita nada', (tester) async {
      final session = await pumpSettings(tester);
      final remove = find.byKey(const Key('repo-remove-x/dos'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await settleReal(tester);
      await tester.tap(find.text('Cancelar'));
      await settleReal(tester);
      expect(session.workspace.repos, hasLength(2));
      expect(files.trashed, isEmpty);
    });

    testWidgets('«Restablecer» está al final de Ajustes', (tester) async {
      await pumpSettings(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('start-over')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('start-over')), findsOneWidget);
    });
  });

  group('restablecer, en la pantalla', () {
    testWidgets('pregunta qué más tirar, borra y vuelve a abrir', (
      tester,
    ) async {
      final session = (await tester.runAsync(started))!;
      var restarted = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: StartOverSection(
              session: session,
              restart: () async => restarted += 1,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('start-over')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('la lista de repositorios (2)'),
        findsOneWidget,
      );
      expect(find.text('En GitHub no se toca nada.'), findsOneWidget);

      // Sin marcar nada, las carpetas se quedan.
      await tester.tap(find.byKey(const Key('start-over-folders')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('start-over-confirm')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(files.trashed, unorderedEquals([uno, dos]));
      expect(token.token, isNull);
      expect(preferences.welcome, isFalse);
      expect(restarted, 1);
    });

    testWidgets('cancelar no borra nada', (tester) async {
      final session = (await tester.runAsync(started))!;
      var restarted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StartOverSection(
              session: session,
              restart: () async => restarted += 1,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('start-over')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(token.token, isNotNull);
      expect(preferences.cleared, isFalse);
      expect(restarted, 0);
    });
  });
}
