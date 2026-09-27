/// La carpeta de compilación en Ajustes: cuánto ocupa, y vaciarla.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/ui/build_folder.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('el tamaño, como se lee', () {
    expect(const BuildFolder(path: 'b', bytes: 0).size, '0 B');
    expect(const BuildFolder(path: 'b', bytes: 1536).size, '1,5 KB');
    expect(const BuildFolder(path: 'b', bytes: 462064922).size, '440,7 MB');
    expect(const BuildFolder(path: 'b', bytes: 0).isEmpty, isTrue);
  });

  testWidgets('dice cuánto ocupa y, preguntando, la vacía', (tester) async {
    final compiler = FakeCompiler()
      ..folder = const BuildFolder(
        path: '.didacta-build',
        bytes: 462064922,
        files: 1149,
      );
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: compiler,
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: BuildFolders(session: session)),
      ),
    );
    await settle(tester);
    expect(find.text('440,7 MB en 1149 ficheros'), findsOneWidget);

    final empty = find.byWidgetPredicate(
      (widget) =>
          widget is TextButton &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'build-folder-empty-',
          ),
    );
    await tester.tap(empty);
    await settle(tester);
    expect(find.byKey(const Key('build-folder-confirm')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(compiler.cleans, 0);

    await tester.tap(empty);
    await settle(tester);
    await tester.tap(find.byKey(const Key('build-folder-go')));
    await settle(tester);
    expect(compiler.cleans, 1);
    expect(find.text('vacía'), findsOneWidget);
    expect(tester.widget<TextButton>(empty).onPressed, isNull);
  });
}
