/// Con el motor, LaTeX y SyncTeX de verdad: ⌘+clic sobre una palabra de una
/// diapositiva lleva a la lección y a la línea donde está escrita.
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
import 'package:didacta_app/ui/pdf_tab.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';
import 'pdf_search_test.dart' show wait;

const lesson = 'content/calculo/limites/calculo-de-limites/algebra-de-limites';

String? engineRoot() {
  var directory = Directory.current;
  for (var i = 0; i < 4; i += 1) {
    if (File('${directory.path}/cli/didacta').existsSync()) {
      return directory.path;
    }
    directory = directory.parent;
  }
  return null;
}

bool toolsAvailable() {
  try {
    return Process.runSync('which', ['latexmk']).exitCode == 0 &&
        Process.runSync('which', ['synctex']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  testWidgets('⌘+clic en «entonces» lleva a la línea 11 de la lección', (
    tester,
  ) async {
    final engine = engineRoot();
    if (engine == null || !toolsAvailable()) {
      markTestSkipped('hace falta el motor, latexmk y synctex');
      return;
    }
    final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );

    // Una copia del ejemplo, y la lección compilada en diapositivas.
    final work = Directory.systemTemp.createTempSync('didacta-synctex-app-');
    addTearDown(() => work.deleteSync(recursive: true));
    final compiler = Compiler(enginePath: engine, repositoryPath: work.path);
    final pdf = await tester.runAsync(() async {
      await Process.run('cp', [
        '-R',
        '$engine/app/assets/ejemplo/.',
        work.path,
      ]);
      final [made] = await compiler.compile(
        unitPath: lesson,
        profiles: const ['slides'],
        languages: const ['es'],
      );
      return made.pdf!;
    });
    // Dónde está «entonces» en el PDF, según su propio texto.
    final point = await tester.runAsync(() async {
      final document = await PdfDocument.openFile(pdf!);
      final text = await document.pages.first.loadStructuredText();
      final at = text.fullText.indexOf('entonces');
      final rect = text.charRects[at + 2];
      await document.dispose();
      return PdfPoint(
        (rect.left + rect.right) / 2,
        (rect.top + rect.bottom) / 2,
      );
    });

    final catalogue = catalogueWith([
      unitJson(
        path: lesson,
        category: 'calculo',
        topic: 'limites',
        title: const {'es': 'Álgebra de límites'},
      ),
    ]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: compiler,
    );
    await session.primeForTest(catalogue);

    String? went;
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp.router(
          theme: didactaTheme(),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: PdfTabView(
                    group: PdfGroup(
                      id: 'slides',
                      panes: [
                        OpenPdf(
                          path: pdf!,
                          profile: 'slides',
                          language: 'es',
                          pages: 0,
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
            ],
            errorBuilder: (_, state) {
              went = '${state.uri}';
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await wait(tester, rounds: 10);

    final controller = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!;
    final page = controller.layout.pageLayouts.first;
    final size = controller.document.pages.first;
    final scale = page.width / size.width;
    final global = controller.documentToGlobal(
      page.topLeft + Offset(point!.x, size.height - point.y) * scale,
    )!;

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.tapAt(global);
    await tester.sendKeyUpEvent(modifier);
    for (var i = 0; i < 40 && went == null; i += 1) {
      await wait(tester, rounds: 1);
    }
    expect(went, isNotNull, reason: 'no llevó a ninguna parte');
    expect(went, contains('algebra-de-limites'));
    expect(went, contains('linea=11'));
  });
}
