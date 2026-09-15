/// El terminal de la compilación.
///
/// Lo que se comprueba aquí es lo que la pantalla no podía decir antes: que
/// compilar abre una ventana, que lo que el motor va escribiendo aparece en
/// ella **mientras compila** y no al final, y que se queda cuando algo falla
/// --que es cuando hace falta leerla-- y se quita cuando no.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/build_console.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_preview.dart';

import 'fixture.dart';

final Finder compile = find.byKey(const Key('compile'));
final Finder consoleLines = find.byKey(const Key('build-console-lines'));

/// Un motor que escribe unas líneas y **se queda ahí** hasta que el test lo
/// suelta.
///
/// Es la única forma de mirar dentro de una compilación en marcha: con un
/// motor que contesta al instante, «durante» y «después» son el mismo
/// fotograma, y lo que esta pantalla promete es justo lo de durante.
class _SlowCompiler extends FakeCompiler {
  _SlowCompiler({this.fails = false});

  final bool fails;
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    onOutput?.call('=== preview/unidad · slides · es');
    onOutput?.call(r'$ latexmk -pdf -g');
    onOutput?.call('This is pdfTeX, Version 3.141592653');
    await gate.future;
    onOutput?.call('Output written on salida.pdf (3 pages)');
    return [
      for (final id in profiles)
        for (final language in languages)
          CompileOutput(
            profile: id,
            language: language,
            ok: !fails,
            pdf: fails ? null : '/salida/$id-$language.pdf',
            pages: fails ? 0 : 3,
            errors: fails
                ? const ['es.tex:4: Undefined control sequence']
                : const [],
          ),
    ];
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.unit, required this.session});

  final Unit unit;
  final Session session;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  PreviewState? _state;

  @override
  Widget build(BuildContext context) => UnitPreview(
    onOpen: (_) {},
    state: _state ??= PreviewState(
      target: UnitTarget(widget.unit),
      session: widget.session,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onCompiled: (_) {},
    ),
    onExternal: (path, {required bool reveal}) {},
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<Session> pumpPreview(WidgetTester tester, FakeCompiler compiler) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: _Host(unit: catalogue.unitByPath(unitPath)!, session: session),
        ),
      ),
    ),
  );
  await settle(tester);
  return session;
}

void main() {
  group('el registro', () {
    test('guarda las líneas en orden y dice cuánto llevó', () {
      final console = BuildConsole();
      addTearDown(console.dispose);

      console.start('Compilando esta unidad');
      expect(console.running, isTrue);
      console
        ..add('una')
        ..add('dos');
      console.finish();

      expect(console.lines, ['una', 'dos']);
      expect(console.running, isFalse);
      expect(console.ok, isTrue);
      expect(console.took, isNotNull);
      expect(console.text, 'una\ndos');
    });

    test('empezar otra tira lo de la anterior', () {
      // Lo que interesa es lo que está pasando ahora. Un registro acumulado
      // obliga a buscar dónde empieza la compilación que se está mirando.
      final console = BuildConsole();
      addTearDown(console.dispose);

      console
        ..start('primera')
        ..add('vieja');
      console.finish();
      console.start('segunda');

      expect(console.lines, isEmpty);
      expect(console.title, 'segunda');
    });

    test('un fallo de lanzamiento entra en el registro y lo marca', () {
      final console = BuildConsole();
      addTearDown(console.dispose);

      console.start('x');
      console.finish(failure: 'no se pudo lanzar el motor');

      expect(console.ok, isFalse);
      expect(console.lines.single, contains('no se pudo lanzar el motor'));
    });

    test('que LaTeX no compile también cuenta como que no fue bien', () {
      final console = BuildConsole();
      addTearDown(console.dispose);

      console.start('x');
      console.finish(ok: false);

      expect(console.ok, isFalse);
      expect(console.failure, isNull, reason: 'el motor sí arrancó');
    });
  });

  testWidgets('compilar abre el terminal y enseña lo que escribe el motor', (
    tester,
  ) async {
    final compiler = _SlowCompiler();
    await pumpPreview(tester, compiler);

    await tester.tap(compile);
    await settle(tester);

    // Mientras compila, no después: el motor sigue parado en la puerta.
    expect(consoleLines, findsOneWidget);
    expect(find.textContaining('This is pdfTeX'), findsOneWidget);
    expect(find.textContaining(r'$ latexmk'), findsOneWidget);
    expect(find.textContaining('En marcha'), findsOneWidget);

    compiler.gate.complete();
    await settle(tester);
  });

  testWidgets('cuando acaba bien se quita de en medio', (tester) async {
    // Lo que se quiere después de compilar es el PDF. Un modal que hay que
    // cerrar cada vez acaba siendo un clic de peaje.
    final compiler = _SlowCompiler();
    await pumpPreview(tester, compiler);

    await tester.tap(compile);
    await settle(tester);
    expect(consoleLines, findsOneWidget);

    compiler.gate.complete();
    await settle(tester);

    expect(consoleLines, findsNothing);
    expect(find.textContaining('3 páginas'), findsWidgets);
  });

  testWidgets('cuando algo no compila se queda, con la salida entera', (
    tester,
  ) async {
    final compiler = _SlowCompiler(fails: true);
    await pumpPreview(tester, compiler);

    await tester.tap(compile);
    await settle(tester);
    compiler.gate.complete();
    await settle(tester);

    expect(consoleLines, findsOneWidget);
    expect(find.textContaining('Terminada en'), findsOneWidget);
    expect(find.textContaining('Output written on'), findsOneWidget);
  });

  testWidgets('se puede volver a abrir después de cerrarlo', (tester) async {
    // El registro sobrevive a la ventana: se cierra para ver el PDF, y el
    // aviso que pasó volando sigue estando.
    final compiler = _SlowCompiler();
    final session = await pumpPreview(tester, compiler);

    await tester.tap(compile);
    await settle(tester);
    compiler.gate.complete();
    await settle(tester);
    expect(consoleLines, findsNothing);

    expect(session.buildConsole.lines, isNotEmpty);
    await tester.tap(find.byKey(const Key('show-console')));
    await settle(tester);

    expect(consoleLines, findsOneWidget);
    expect(find.textContaining('This is pdfTeX'), findsOneWidget);

    // Y consultarlo no lo cierra solo, aunque la compilación fuera bien.
    await settle(tester);
    expect(consoleLines, findsOneWidget);
  });

  testWidgets('sin ninguna compilación todavía no ofrece registro', (
    tester,
  ) async {
    await pumpPreview(tester, FakeCompiler());
    expect(find.byKey(const Key('show-console')), findsNothing);
  });
}
