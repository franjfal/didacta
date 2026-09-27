/// Las capturas de lo nuevo de traducir: revisar lado a lado, la franja de una
/// desactualizada, el diálogo con la estimación y Ajustes con Apertium y el
/// glosario.
///
///     cd app && DIDACTA_SHOTS_OUT=<carpeta> flutter test tool/shots_translation.dart
///
/// Con `DIDACTA_SHOTS_DARK=1`, en oscuro.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/model/source_hash.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';
import 'package:didacta_app/ui/translate_unit.dart';
import 'package:didacta_app/ui/unit_page.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart' show loadFonts, shotTheme;

final String outputDir =
    Platform.environment['DIDACTA_SHOTS_OUT'] ?? '/tmp/didacta-shots';
final bool dark = Platform.environment['DIDACTA_SHOTS_DARK'] == '1';
final GlobalKey _frame = GlobalKey();

const String original = r'''\begin{definition}[Norma]
Una \keyterm{norma} en un espacio vectorial $V$ es una aplicación
$\|\cdot\| \colon V \to \mathbb{R}$ que cumple, para todo $x, y \in V$:
\begin{itemize}
  \item $\|x\| \ge 0$, y $\|x\| = 0$ si y solo si $x = 0$;
  \item $\|\lambda x\| = |\lambda|\,\|x\|$;
  \item $\|x + y\| \le \|x\| + \|y\|$.
\end{itemize}
\end{definition}
''';

const String translation = r'''\begin{definition}[Norma]
Una \keyterm{norma} en un espai vectorial $V$ és una aplicació
$\|\cdot\| \colon V \to \mathbb{R}$ que compleix, per a tot $x, y \in V$:
\begin{itemize}
  \item $\|x\| \ge 0$, i $\|x\| = 0$ si i només si $x = 0$;
  \item $\|\lambda x\| = \lambda\,\|x\|$;
  \item $\|x + y\| \le \|x\| + \|y\|$.
\end{itemize}
\end{definition}
''';

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes;
  });
  final file = File('$outputDir/$name${dark ? '-oscuro' : ''}.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${file.path}');
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<FakeSession> sessionFor(String status) async {
  final catalogue = catalogueWith([
    {
      ...unitJson(),
      'languages': {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': status, 'exists': true},
      },
    },
  ]);
  final clone = FakeClone();
  clone.log['$unitPath/es.tex'] = [
    FileCommit(
      sha: 'viejo',
      author: 'Javier Falcó',
      email: 'j@uv.es',
      when: DateTime(2026, 9, 2),
      subject: 'La norma',
    ),
  ];
  const before = r'''\begin{definition}[Norma]
Una norma en un espacio vectorial $V$ es una aplicación que cumple:
\end{definition}
''';
  clone.contents['viejo'] = before;
  final secrets = MemoryTranslationSecrets();
  await secrets.write(
    TranslationProvider.google,
    const Credentials(key: 'AIza-una-clave'),
  );
  await secrets.write(
    TranslationProvider.apertium,
    const Credentials(key: 'on'),
  );
  final session = FakeSession(
    gatewayOverride: FakeGateway(
      files: {
        '$unitPath/es.tex': original,
        '$unitPath/va.tex': translation,
        '$unitPath/unit.yaml':
            'title:\n  es: Espacios normados\nlanguages:\n'
            '  es: {status: source}\n'
            '  va: {status: reviewed, source_hash: ${contentHash(before)}}\n',
        'translation/glossary.tsv':
            'es\tva\ten\nnorma\tnorma\tnorm\nsucesión\tsuccessió\tsequence\n',
      },
    ),
    catalogue: catalogue,
    cloneOverride: clone,
    translationSecretsOverride: secrets,
  );
  // ignore: invalid_use_of_visible_for_testing_member
  await session.primeForTest(catalogue);
  // ignore: invalid_use_of_visible_for_testing_member
  await session.useCloneForTest('/tmp/didacta-test');
  return session;
}

Future<void> mount(
  WidgetTester tester,
  Session session,
  Widget page, {
  Size size = const Size(1280, 820),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<McpService>(
          create: (_) => McpService(
            openRunner: () => const UnavailableRunner('Sin servidor.'),
          ),
        ),
        ChangeNotifierProvider<UpdateService>(create: (_) => offlineUpdates()),
        ChangeNotifierProvider<TourController>(create: (_) => TourController()),
      ],
      child: RepaintBoundary(
        key: _frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shotTheme(dark ? DidactaPalette.dark : DidactaPalette.light),
          home: Scaffold(body: page),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  setUpAll(() async {
    await loadFonts();
  });

  testWidgets('revisar lado a lado', (tester) async {
    final session = await sessionFor('draft');
    await session.setSplitEditors(true);
    await mount(
      tester,
      session,
      const UnitPage(unitPath: unitPath, language: 'va'),
      size: const Size(1500, 860),
    );
    await shoot(tester, 'traducir-lado-a-lado');
  });

  testWidgets('una desactualizada', (tester) async {
    final session = await sessionFor('outdated');
    await mount(
      tester,
      session,
      const UnitPage(unitPath: unitPath, language: 'va'),
    );
    await tester.tap(find.byKey(const Key('show-original-changes')));
    await settle(tester);
    await shoot(tester, 'traducir-desactualizada');
  });

  testWidgets('el diálogo con la estimación', (tester) async {
    final session = await sessionFor('draft');
    session.language = 'en';
    await mount(
      tester,
      session,
      Center(
        child: TranslateDialog(
          session: session,
          units: session.catalogue.units,
        ),
      ),
      size: const Size(900, 640),
    );
    await shoot(tester, 'traducir-dialogo');
  });

  testWidgets('Ajustes, con Apertium y el glosario', (tester) async {
    final session = await sessionFor('draft');
    await mount(
      tester,
      session,
      const SettingsPage(section: 'traduccion'),
      size: const Size(1280, 1500),
    );
    await shoot(tester, 'traducir-ajustes');
  });
}
