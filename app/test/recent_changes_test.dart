/// «Cambios recientes»: la lista, y un deshacer que no pisa lo de después.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/recent_changes.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Un clon que sabe el contenido de cada fichero en cada commit.
class PathClone extends FakeClone {
  final Map<String, String?> files = {};

  @override
  Future<String?> fileAt({required String sha, required String path}) async =>
      files['$sha:$path'];
}

FileCommit commitOf(String sha, String subject, DateTime when) => FileCommit(
  sha: sha,
  author: 'Javier',
  email: 'j@uv.es',
  when: when,
  subject: subject,
);

final FileCommit removal = commitOf(
  'quitarquitar',
  'Quitar el grupo hoja-1 de am-iii 2025-2026',
  DateTime(2026, 9, 20),
);

PathClone cloneWith({required bool touchedLater}) => PathClone()
  ..recentCommits = [
    commitOf('otrootro', 'Corregir la definición', DateTime(2026, 9, 21)),
    removal,
  ]
  ..changes = const [
    TreeChange(
      kind: TreeChangeKind.modified,
      path: 'courses/am-iii/2025-2026/year.yaml',
    ),
    TreeChange(kind: TreeChangeKind.modified, path: 'generated/manifest.json'),
  ]
  ..files['quitarquitar:courses/am-iii/2025-2026/year.yaml'] = 'sin la hoja'
  ..files['HEAD:courses/am-iii/2025-2026/year.yaml'] = touchedLater
      ? 'sin la hoja, y otra cosa'
      : 'sin la hoja';

void main() {
  test('se deshace lo que nadie ha vuelto a tocar, sin el índice', () async {
    final plan = await planUndo(cloneWith(touchedLater: false), removal);
    expect(plan.blocked, isNull);
    // El índice no: se regenera.
    expect(plan.paths, ['courses/am-iii/2025-2026/year.yaml']);
  });

  test('lo que se tocó después no se pisa, y se dice cuál', () async {
    final plan = await planUndo(cloneWith(touchedLater: true), removal);
    expect(plan.blocked, contains('courses/am-iii/2025-2026/year.yaml'));
  });

  Future<(PathClone, FakeCompiler)> pumpDialog(
    WidgetTester tester, {
    required bool touchedLater,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final clone = cloneWith(touchedLater: touchedLater);
    final engine = FakeCompiler();
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: engine,
      cloneOverride: clone,
      adminOverride: CourseAdmin(
        compiler: engine,
        clone: clone,
        author: (name: 'Javier', email: 'javier@uv.es'),
        token: '',
        pushOnCommit: false,
      ),
    );
    await session.primeForTest(catalogue);
    await session.useCloneForTest('/tmp/didacta-test');
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecentChanges(context, session),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await settle(tester);
    return (clone, engine);
  }

  testWidgets('la lista, de lo más reciente a lo más antiguo', (tester) async {
    await pumpDialog(tester, touchedLater: false);
    final first = tester.getTopLeft(find.text('Corregir la definición')).dy;
    final second = tester
        .getTopLeft(find.text('Quitar el grupo hoja-1 de am-iii 2025-2026'))
        .dy;
    expect(first, lessThan(second));
  });

  testWidgets('deshacer trae lo de antes, en un commit nuevo', (tester) async {
    final (clone, _) = await pumpDialog(tester, touchedLater: false);
    await tester.tap(find.byKey(const Key('undo-quitarquitar')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-undo')));
    await settle(tester);

    expect(clone.restored.single.sha, 'quitarquitar~1');
    expect(clone.restored.single.paths, ['courses/am-iii/2025-2026/year.yaml']);
    expect(
      clone.commits.last.message,
      'Deshacer: Quitar el grupo hoja-1 de am-iii 2025-2026',
    );
  });

  testWidgets('y si se tocó después, no deshace nada', (tester) async {
    final (clone, _) = await pumpDialog(tester, touchedLater: true);
    await tester.tap(find.byKey(const Key('undo-quitarquitar')));
    await settle(tester);
    expect(find.byKey(const Key('undo-blocked')), findsOneWidget);
    expect(clone.restored, isEmpty);
    expect(clone.commits, isEmpty);
  });
}
