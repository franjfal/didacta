/// Exportar un curso de principio a fin: lo viejo se avisa y se recompila
/// solo eso, la carpeta se recuerda por asignatura y sale un .zip si se pide.
@TestOn('vm')
library;

// El de la plataforma, que es el que se sustituye; viene con file_selector.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/export_actions.dart';
import 'package:didacta_app/ui/publish_folder.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// El selector de carpetas del sistema, contestando siempre lo mismo y
/// apuntando desde dónde se abrió.
class FakeFileSelector extends FileSelectorPlatform {
  FakeFileSelector(this.answer);

  final String answer;
  final List<String?> openedAt = [];

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openedAt.add(initialDirectory);
    return answer;
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ExistingOutput pdf(String profile, {bool stale = false}) => ExistingOutput(
  profile: profile,
  label: profile,
  family: 'notes',
  language: 'es',
  pdf: '/tmp/$profile.pdf',
  exists: true,
  stale: stale,
);

void main() {
  late FakeFileSelector selector;
  late FakeCompiler compiler;
  late MemoryPreferences preferences;

  setUp(() {
    selector = FakeFileSelector('/tmp/reparto');
    FileSelectorPlatform.instance = selector;
    compiler = FakeCompiler()
      ..documentOutputList = {
        'tema-1': [pdf('notes', stale: true), pdf('slides')],
        'hoja-1': [pdf('problems')],
      };
    preferences = MemoryPreferences();
  });

  Future<void> pumpCourses(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: compiler,
      preferencesOverride: preferences,
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: CoursesPage()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> exportOnce(
    WidgetTester tester, {
    bool zip = false,
    bool html = false,
  }) async {
    await tester.tap(find.byKey(const Key('export-year-am-iii-2025-2026')));
    await settle(tester);
    if (zip) {
      await tester.ensureVisible(find.byKey(const Key('export-zip')));
      await tester.tap(find.byKey(const Key('export-zip')));
      await settle(tester);
    }
    if (html) {
      await tester.ensureVisible(find.byKey(const Key('export-html')));
      await tester.tap(find.byKey(const Key('export-html')));
      await settle(tester);
    }
    await tester.ensureVisible(find.byKey(const Key('export-confirm')));
    await tester.tap(find.byKey(const Key('export-confirm')));
    await settle(tester);
  }

  testWidgets('lo viejo se avisa, y se recompila solo eso', (tester) async {
    await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('export-year-am-iii-2025-2026')));
    await settle(tester);

    final note = tester.widget<Note>(find.byKey(const Key('export-stale')));
    expect(note.text, contains('«Tema 1. Espacios normados»'));
    expect(note.text, startsWith('Un documento tiene'));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('export-rebuild-stale')),
          )
          .value,
      isTrue,
    );

    await tester.ensureVisible(find.byKey(const Key('export-confirm')));
    await tester.tap(find.byKey(const Key('export-confirm')));
    await settle(tester);

    expect(
      [for (final call in compiler.documentCalls) call.document],
      ['am-iii@2025-2026/tema-1'],
    );
    expect(compiler.exports, hasLength(1));
  });

  testWidgets('la carpeta se recuerda, por asignatura', (tester) async {
    await pumpCourses(tester);
    await exportOnce(tester);
    expect(selector.openedAt, [null]);
    expect(preferences.exportFolders['am-iii'], '/tmp/reparto');

    // Cerrar la consola de compilar que abrió la primera.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await exportOnce(tester);
    expect(selector.openedAt.last, '/tmp/reparto');
  });

  testWidgets('un .zip con el nombre del curso, si se pide', (tester) async {
    await pumpCourses(tester);
    await exportOnce(tester, zip: true);
    expect(
      compiler.zips.single.zip,
      '/tmp/reparto/Análisis Matemático III 2025-2026.zip',
    );
    expect(compiler.zips.single.append, isFalse);
    // Y sin HTML, que no se ha pedido.
    expect(compiler.exportsWithHtml, [false]);
  });

  testWidgets('con carpeta de reparto, «Publicar» no pregunta dónde', (
    tester,
  ) async {
    preferences.publish = '/tmp/nube';
    await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('year-menu-am-iii-2025-2026')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('publish-year-am-iii-2025-2026')));
    await settle(tester);
    expect(
      find.text('Publicar Análisis Matemático III · 2025-2026'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('export-confirm')));
    await tester.tap(find.byKey(const Key('export-confirm')));
    await settle(tester);

    expect(selector.openedAt, isEmpty);
    expect(
      compiler.exports.single.to,
      '/tmp/nube/Análisis Matemático III 2025-2026',
    );
    // Y no cambia la carpeta de exportar, que es otra cosa.
    expect(preferences.exportFolders, isEmpty);
  });

  testWidgets('sin ella, no se ofrece', (tester) async {
    await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('year-menu-am-iii-2025-2026')));
    await settle(tester);
    expect(
      find.byKey(const Key('publish-year-am-iii-2025-2026')),
      findsNothing,
    );
  });

  testWidgets('se elige en Ajustes, y se deja de usar', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      preferencesOverride: preferences,
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: PublishFolderSection(session: session)),
      ),
    );
    await settle(tester);
    expect(find.text('Sin carpeta de reparto.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('publish-folder-choose')));
    await settle(tester);
    expect(preferences.publish, '/tmp/reparto');
    expect(find.text('/tmp/reparto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('publish-folder-clear')));
    await settle(tester);
    expect(preferences.publish, isNull);
  });

  test('el nombre del .zip no lleva lo que un sistema no admite', () {
    expect(
      zipNameFor('Álgebra: lineal / II', '2025-2026'),
      'Álgebra lineal II 2025-2026.zip',
    );
    expect(zipNameFor('', '2025-2026'), 'curso 2025-2026.zip');
  });

  testWidgets('los apuntes en HTML, si se piden', (tester) async {
    await pumpCourses(tester);
    await exportOnce(tester, html: true);
    expect(compiler.exportsWithHtml, [true]);
  });
}
