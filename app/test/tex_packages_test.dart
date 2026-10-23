/// Instalar el paquete de LaTeX que falta: la parte que no lanza procesos
/// --leer `tlmgr search`, qué decir a mano-- y el diálogo, con un gestor de
/// mentira.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/tex_packages.dart';
import 'package:didacta_app/model/toolchain.dart' show Host;
import 'package:didacta_app/state/build_console.dart';
import 'package:didacta_app/ui/missing_package.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String _search = '''
tlmgr: package repository https://mirror.ctan.org/systems/texlive/tlnet (verified)
tcolorbox:
\ttexmf-dist/tex/latex/tcolorbox/tcolorbox.sty
\ttexmf-dist/tex/latex/tcolorbox/tcbbreakable.code.tex
other-tcolorbox-extras:
\ttexmf-dist/tex/latex/extras/mytcolorbox.sty
''';

void main() {
  group('qué paquete trae un fichero', () {
    test('tlmgr: el que tiene el fichero con ese nombre exacto', () {
      expect(packageFromTlmgrSearch(_search, 'tcolorbox.sty'), 'tcolorbox');
      // La búsqueda es por subcadena: `mytcolorbox.sty` no es lo que se pidió.
      expect(
        packageFromTlmgrSearch(_search, 'mytcolorbox.sty'),
        'other-tcolorbox-extras',
      );
      expect(packageFromTlmgrSearch(_search, 'nada.sty'), isNull);
      expect(
        packageFromTlmgrSearch('tlmgr: package repository x\n', 'a.sty'),
        isNull,
      );
    });

    test('MiKTeX: el nombre del fichero sin extensión, salvo fuentes', () {
      expect(miktexPackageFor('tcolorbox.sty'), 'tcolorbox');
      expect(miktexPackageFor('beamer.cls'), 'beamer');
      expect(miktexPackageFor('ec-lmr10.tfm'), isNull);
    });

    test('lo que viene del log no se pasa a un proceso sin mirarlo', () {
      expect(isSafePackageName('babel-catalan'), isTrue);
      expect(isSafePackageName('l3kernel.sty'), isTrue);
      expect(isSafePackageName('x; rm -rf ~'), isFalse);
      expect(isSafePackageName("a'b"), isFalse);
      expect(isSafePackageName('-rf'), isFalse);
    });

    test('el TeX de Debian no es de tlmgr', () {
      expect(isSystemTexRoot('/usr/share/texlive'), isTrue);
      expect(isSystemTexRoot('/usr/local/texlive/2026'), isFalse);
      expect(isSystemTexRoot(null), isFalse);
    });
  });

  group('cuando no sale', () {
    test('los fallos conocidos de tlmgr se dicen en claro', () {
      expect(
        explainTlmgrFailure(
          'tlmgr: Local TeX Live (2024) is older than remote repository (2026).',
        ),
        contains('año'),
      );
      expect(
        explainTlmgrFailure('tlmgr itself needs to be updated.'),
        contains('update --self'),
      );
      expect(
        explainTlmgrFailure('mkdir: Permission denied'),
        contains('administrador'),
      );
      expect(explainTlmgrFailure('algo que nadie conoce'), isNull);
    });

    test('a mano: la orden de tlmgr, con sudo si la carpeta es de root', () {
      const manager = TexPackageManager(
        kind: TexManagerKind.tlmgr,
        program: '/Library/TeX/texbin/tlmgr',
        needsAdmin: true,
      );
      final steps = manualInstallSteps(
        manager: manager,
        host: Host.macos,
        file: 'tcolorbox.sty',
        package: 'tcolorbox',
      );
      expect(steps.single, contains('sudo /Library/TeX/texbin/tlmgr install'));
    });

    test('a mano, sin saber el paquete: primero buscarlo', () {
      const manager = TexPackageManager(kind: TexManagerKind.tlmgr);
      final steps = manualInstallSteps(
        manager: manager,
        host: Host.linux,
        file: 'x.sty',
      );
      expect(steps.first, contains('search --global --file /x.sty'));
    });

    test('el TeX de la distribución: apt y dnf', () {
      final steps = manualInstallSteps(
        manager: const TexPackageManager(kind: TexManagerKind.system),
        host: Host.linux,
        file: 'tcolorbox.sty',
      );
      expect(steps.join('\n'), contains('apt-file search tcolorbox.sty'));
      expect(steps.join('\n'), contains("tex(tcolorbox.sty)"));
    });
  });

  group('lo que sale de compilar', () {
    test('una salida dice qué ficheros le faltaban, sin repetir', () {
      const output = CompileOutput(
        profile: 'slides',
        language: 'es',
        ok: false,
        diagnostics: [
          CompileDiagnostic(
            severity: 'error',
            message: "LaTeX Error: File `tcolorbox.sty' not found.",
            code: 'missing-file',
            needs: 'tcolorbox.sty',
          ),
          CompileDiagnostic(
            severity: 'error',
            message: "LaTeX Error: File `tcolorbox.sty' not found.",
            code: 'missing-file',
            needs: 'tcolorbox.sty',
          ),
          CompileDiagnostic(severity: 'error', message: 'Emergency stop.'),
        ],
      );
      expect(output.missingFiles, ['tcolorbox.sty']);
    });

    test('la consola junta los de todas las que fallaron', () {
      final console = BuildConsole();
      addTearDown(console.dispose);
      console.start('lote');
      var retried = 0;
      console.finishBuild(const [
        CompileOutput(
          profile: 'slides',
          language: 'es',
          ok: false,
          log: '/b/x.log',
          diagnostics: [
            CompileDiagnostic(
              severity: 'error',
              message: 'x',
              code: 'missing-file',
              needs: 'a.sty',
            ),
          ],
        ),
        CompileOutput(profile: 'book', language: 'es', ok: true),
      ], retry: () async => retried += 1);
      expect(console.ok, isFalse);
      expect(console.missingFiles, ['a.sty']);
      expect(console.outputs, hasLength(2));
      expect(console.retry, isNotNull);

      // Empezar otra tira lo de la anterior, también esto.
      console.start('otra');
      expect(console.outputs, isEmpty);
      expect(console.retry, isNull);
    });
  });

  group('el diálogo', () {
    Future<void> open(
      WidgetTester tester,
      FakeTexPackages packages, {
      List<String> files = const ['tcolorbox.sty'],
      Future<void> Function()? onRecompile,
    }) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open'),
                onPressed: () => showInstallPackages(
                  context,
                  files: files,
                  packages: packages,
                  onRecompile: onRecompile,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('dice qué paquete, lo instala y ofrece volver a compilar', (
      tester,
    ) async {
      final packages = FakeTexPackages(
        provides: {'tcolorbox.sty': 'tcolorbox'},
      );
      var recompiled = 0;
      await open(tester, packages, onRecompile: () async => recompiled += 1);

      expect(find.textContaining('paquete «tcolorbox»'), findsOneWidget);
      expect(find.byKey(const Key('install-needs-admin')), findsNothing);
      await tester.tap(find.byKey(const Key('install-confirm')));
      await tester.pumpAndSettle();

      expect(packages.installed, ['tcolorbox']);
      expect(find.byKey(const Key('install-done')), findsOneWidget);
      expect(find.textContaining('install: tcolorbox'), findsOneWidget);

      await tester.tap(find.byKey(const Key('install-recompile')));
      await tester.pumpAndSettle();
      expect(recompiled, 1);
      expect(find.byKey(const Key('install-packages')), findsNothing);
    });

    testWidgets('avisa de que pedirá la contraseña al sistema', (tester) async {
      await open(
        tester,
        FakeTexPackages(
          needsAdmin: true,
          provides: {'tcolorbox.sty': 'tcolorbox'},
        ),
      );
      expect(find.byKey(const Key('install-needs-admin')), findsOneWidget);
    });

    testWidgets('lo que ya está no se vuelve a instalar', (tester) async {
      final packages = FakeTexPackages(
        provides: {'tcolorbox.sty': 'tcolorbox'},
        present: {'tcolorbox.sty'},
      );
      await open(tester, packages, onRecompile: () async {});
      expect(find.byKey(const Key('install-confirm')), findsNothing);
      expect(find.textContaining('ya está instalado'), findsOneWidget);
      expect(find.byKey(const Key('install-recompile')), findsOneWidget);
      expect(packages.installed, isEmpty);
    });

    testWidgets('sin gestor: por qué, y cómo a mano', (tester) async {
      await open(tester, FakeTexPackages(kind: TexManagerKind.none));
      expect(find.byKey(const Key('install-confirm')), findsNothing);
      expect(find.text('Para hacerlo a mano:'), findsOneWidget);
    });

    testWidgets('si falla, el motivo, los pasos a mano y reintentar', (
      tester,
    ) async {
      await open(
        tester,
        FakeTexPackages(
          provides: {'tcolorbox.sty': 'tcolorbox'},
          fails: const TexPackageException(
            'tlmgr no ha podido instalar «tcolorbox» (código 1).',
            detail: 'boom',
            manual: ['sudo tlmgr install tcolorbox'],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('install-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('install-failed')), findsOneWidget);
      expect(find.text('sudo tlmgr install tcolorbox'), findsOneWidget);
      expect(find.byKey(const Key('install-retry')), findsOneWidget);
    });
  });
}
