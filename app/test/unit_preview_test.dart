/// La pestaña de compilar, sin lanzar nada.
///
/// Lo que se comprueba aquí es la parte que no cubre el motor: que las dos
/// versiones que se pidieron vengan preseleccionadas, que se compile lo que
/// se eligió y no otra cosa, que un fallo se lea, y --lo que más importa--
/// que **cuando no se puede compilar la pantalla lo diga** en lugar de
/// ofrecer un botón que falla.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';
import 'package:didacta_app/ui/unit_preview.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final Finder compile = find.byKey(const Key('compile'));

/// Lo que la pantalla dijo que había compilado, que es lo que la página
/// abre en pestañas.
final List<CompileOutput> compiled = [];

/// Las rutas que pidió abrir fuera, con si era el Finder.
final List<({String path, bool reveal})> external = [];

/// Un anfitrión mínimo que hace lo que hace la página: conservar el estado
/// entre reconstrucciones, que es la razón de que el estado no viva en el
/// widget.
class _Host extends StatefulWidget {
  const _Host({
    required this.unit,
    required this.session,
    required this.external,
  });

  final Unit unit;
  final Session session;
  final List<({String path, bool reveal})> external;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  PreviewState? _state;

  @override
  Widget build(BuildContext context) => UnitPreview(
    state: _state ??= PreviewState(
      unit: widget.unit,
      session: widget.session,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onCompiled: compiled.addAll,
    ),
    onExternal: (path, {required bool reveal}) =>
        widget.external.add((path: path, reveal: reveal)),
  );
}

Future<FakeCompiler?> pumpPreview(
  WidgetTester tester, {
  FakeCompiler? compiler,
  bool none = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  compiled.clear();
  external.clear();
  final used = none ? null : (compiler ?? FakeCompiler());
  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: used,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: _Host(
            unit: catalogue.unitByPath(unitPath)!,
            session: session,
            external: external,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return used;
}

/// La etiqueta con la que el motor nombra un perfil.
String _labelOf(String id) => switch (id) {
  'slides' => 'Diapositivas',
  'book' => 'Libro',
  'notes' => 'Apuntes',
  _ => id,
};

void main() {
  testWidgets('ofrece las versiones, con presentación y libro marcadas', (
    tester,
  ) async {
    await pumpPreview(tester);

    // Las dos que se pidieron, más los apuntes, preseleccionadas: son la
    // respuesta casi siempre que alguien abre esto.
    for (final label in ['Diapositivas', 'Libro', 'Apuntes']) {
      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, label),
      );
      expect(chip.selected, isTrue, reason: label);
    }
    // Y las variantes que nadie pidió, no.
    final teacher = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Apuntes (profesor)'),
    );
    expect(teacher.selected, isFalse);

    expect(find.text('Compilar 3 versiones'), findsOneWidget);
  });

  testWidgets('dice que el preámbulo lo pone Didacta', (tester) async {
    // Era la duda explícita: el preámbulo hace falta para compilar y no
    // tiene que verse en la biblioteca.
    await pumpPreview(tester);
    expect(find.textContaining('El preámbulo lo pone Didacta'), findsOneWidget);
  });

  testWidgets('compila lo elegido, y nada más', (tester) async {
    final compiler = (await pumpPreview(tester))!;

    // Se quitan los apuntes y se deja presentación y libro.
    await tester.tap(find.widgetWithText(FilterChip, 'Apuntes'));
    await settle(tester);
    await tester.tap(compile);
    await settle(tester);

    expect(compiler.calls, hasLength(1));
    expect(compiler.calls.single.profiles, ['slides', 'book']);
    expect(compiler.calls.single.languages, ['es']);
  });

  testWidgets('el idioma de la salida no es el que se está editando', (
    tester,
  ) async {
    // Se compila en valenciano para ver si la traducción cuadra con las
    // figuras, sin dejar de estar en la unidad.
    final compiler = (await pumpPreview(tester))!;

    // Se quita el castellano y se pone el valenciano.
    await tester.tap(find.byKey(const Key('language-va')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('language-es')));
    await settle(tester);
    await tester.tap(compile);
    await settle(tester);

    expect(compiler.calls.single.languages, ['va']);
  });

  testWidgets('el resultado dice páginas y abre el PDF', (tester) async {
    await pumpPreview(tester);

    await tester.tap(compile);
    await settle(tester);

    expect(find.textContaining('5 páginas'), findsOneWidget);
    expect(find.textContaining('1 página'), findsWidgets);

    // Se abren solas: acabas de pedir estas versiones, y quererlas ver es la
    // única razón por la que las pediste.
    expect(compiled.map((r) => r.pdf), contains('/salida/slides-es.pdf'));

    // Y el visor del sistema sigue estando: pantalla completa para pasar
    // diapositivas de verdad.
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Visor del sistema').first,
    );
    await settle(tester);
    expect(external.single.path, '/salida/slides-es.pdf');
    expect(external.single.reveal, isFalse);
  });

  testWidgets('avisa de que la numeración será la del documento', (
    tester,
  ) async {
    // Una unidad sola sale como `0.0.1`, y decirlo evita que alguien lo tome
    // por un fallo.
    await pumpPreview(tester);
    await tester.tap(compile);
    await settle(tester);
    expect(find.textContaining('numeración de apartados'), findsOneWidget);
  });

  testWidgets('un error de LaTeX se lee, con su fichero y su línea', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        outputs: const [
          CompileOutput(
            profile: 'slides',
            language: 'es',
            ok: false,
            errors: ['es.tex:14: Undefined control sequence \\nosequence'],
          ),
        ],
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(
      find.textContaining('es.tex:14: Undefined control sequence'),
      findsOneWidget,
    );
  });

  testWidgets('un aviso de traducción se muestra, que es el accionable', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        outputs: const [
          CompileOutput(
            profile: 'notes',
            language: 'en',
            ok: true,
            pdf: '/salida/notes-en.pdf',
            pages: 1,
            warnings: [
              "No `en' version of `analysis/normed/definition'; using `es'",
            ],
          ),
        ],
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(find.textContaining("No `en' version"), findsOneWidget);
  });

  testWidgets('si el motor no arranca, lo cuenta en lugar de callarse', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        failWith: const CompileException(
          'No se pudo lanzar el motor (/no/existe/cli/didacta).',
          detail: 'No such file or directory',
        ),
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(find.text('La compilación no se pudo lanzar'), findsOneWidget);
    expect(find.textContaining('No such file or directory'), findsOneWidget);
  });

  testWidgets('sin nada con lo que compilar, ofrece Ajustes y no un botón', (
    tester,
  ) async {
    // El estado que de verdad importa: la web, y un escritorio sin motor
    // configurado. Un botón que no puede funcionar es peor que su ausencia
    // explicada.
    await pumpPreview(tester, none: true);

    expect(find.text('Todavía no se puede compilar aquí'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ir a Ajustes'), findsOneWidget);
    expect(compile, findsNothing);
  });

  testWidgets('falta latexmk: lo dice, con el nombre de lo que falta', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        ready: false,
        problem: 'Falta latexmk. Didacta necesita una distribución de TeX.',
      ),
    );

    expect(find.textContaining('Falta latexmk'), findsOneWidget);
    expect(compile, findsNothing);
  });

  group('las pestañas de PDF', () {
    /// La unidad entera, con la pestaña de compilar abierta y los idiomas
    /// que se pidan marcados.
    Future<FakeCompiler> pumpUnit(
      WidgetTester tester, {
      List<String> profiles = const ['slides'],
      List<String> languages = const ['es'],
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final compiler = FakeCompiler();
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
            home: const Scaffold(body: UnitPage(unitPath: unitPath)),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('compilar'));
      await settle(tester);

      // Los perfiles: se dejan solo los pedidos.
      for (final id in const ['slides', 'book', 'notes']) {
        final wanted = profiles.contains(id);
        final chip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, _labelOf(id)),
        );
        if (chip.selected != wanted) {
          await tester.tap(find.widgetWithText(FilterChip, _labelOf(id)));
          await settle(tester);
        }
      }
      // Los idiomas: igual.
      for (final code in const ['es', 'va', 'en']) {
        final wanted = languages.contains(code);
        final chip = tester.widget<FilterChip>(
          find.byKey(Key('language-$code')),
        );
        if (chip.selected != wanted) {
          await tester.tap(find.byKey(Key('language-$code')));
          await settle(tester);
        }
      }

      await tester.tap(compile);
      await settle(tester);
      return compiler;
    }

    testWidgets('compilar abre las pestañas, sin pulsar nada más', (
      tester,
    ) async {
      // Acabas de pedir estas versiones: quererlas ver es la única razón por
      // la que las pediste.
      await pumpUnit(tester, profiles: const ['slides', 'book']);

      expect(find.text('slides · es'), findsWidgets);
      expect(find.text('book · es'), findsWidgets);
      // Y se queda en la primera, mirándola.
      expect(find.byIcon(Icons.first_page), findsOneWidget);
    });

    testWidgets('dos idiomas de un perfil van en la misma pestaña', (
      tester,
    ) async {
      // La comparación que importa: si la traducción valenciana sigue
      // cabiendo en la diapositiva no se sabe sin las dos delante.
      await pumpUnit(tester, languages: const ['es', 'va']);

      // Una sola pestaña, rotulada con los dos idiomas.
      expect(find.text('slides · es va'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      // Y dos paneles, cada uno con su idioma y sus propias acciones.
      expect(find.textContaining('2 versiones'), findsOneWidget);
      expect(find.byKey(const Key('pane-external-es')), findsOneWidget);
      expect(find.byKey(const Key('pane-external-va')), findsOneWidget);
    });

    testWidgets('dos perfiles son dos pestañas, no una', (tester) async {
      // Se agrupa por perfil y no por todo: comparar diapositivas con libro
      // lado a lado no dice nada, son formatos distintos del mismo texto.
      await pumpUnit(
        tester,
        profiles: const ['slides', 'book'],
        languages: const ['es', 'va'],
      );
      expect(find.text('slides · es va'), findsOneWidget);
      expect(find.text('book · es va'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('con una sola versión no hay botón de separar', (tester) async {
      // Separar de una sola cosa no es nada.
      await pumpUnit(tester);
      expect(find.byKey(const Key('pdf-detach')), findsNothing);
    });

    testWidgets('con dos, separar no pregunta cuál', (tester) async {
      // Es la única cosa que se puede querer, y un menú de una opción es un
      // clic de más.
      await pumpUnit(tester, languages: const ['es', 'va']);
      expect(find.text('slides · es va'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-detach')));
      await settle(tester);

      // Dos pestañas, una por idioma.
      expect(find.text('slides · es'), findsWidgets);
      expect(find.text('slides · va'), findsWidgets);
      expect(find.text('slides · es va'), findsNothing);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('con tres, separar pregunta cuál', (tester) async {
      // Con tres, «separar» no dice cuál, así que lo pregunta.
      await pumpUnit(tester, languages: const ['es', 'va', 'en']);
      expect(find.text('slides · es va en'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-detach')));
      await settle(tester);
      expect(find.text('Separar va'), findsOneWidget);

      await tester.tap(find.byKey(const Key('detach-va')));
      await settle(tester);

      expect(find.text('slides · es en'), findsOneWidget);
      expect(find.text('slides · va'), findsWidgets);
    });

    testWidgets('recompilar vuelve a juntar lo que se había separado', (
      tester,
    ) async {
      // Si no, la pestaña separada apuntaría a un PDF viejo.
      await pumpUnit(tester, languages: const ['es', 'va']);
      await tester.tap(find.byKey(const Key('pdf-detach')));
      await settle(tester);
      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.text('compilar'));
      await settle(tester);
      await tester.tap(compile);
      await settle(tester);

      expect(find.text('slides · es va'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('se cierran, y al cerrar se vuelve a compilar', (tester) async {
      await pumpUnit(tester);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Compilar esta unidad'), findsOneWidget);
    });

    testWidgets('cada panel abre el suyo, sin preguntar cuál', (tester) async {
      // La corrección: con dos PDF a la vez, un botón en la barra de la
      // pestaña no dice cuál, y un menú que lo pregunta es un clic de más
      // para contestar algo que el sitio del botón ya contesta.
      // Aquí el anfitrión es la página de verdad, así que lo que se abre
      // fuera pasa por el compilador.
      final compiler = await pumpUnit(tester, languages: const ['es', 'va']);

      await tester.tap(find.byKey(const Key('pane-external-va')));
      await settle(tester);
      expect(compiler.opened, ['/salida/slides-va.pdf']);

      await tester.tap(find.byKey(const Key('pane-reveal-es')));
      await settle(tester);
      expect(compiler.revealed, ['/salida/slides-es.pdf']);
    });

    testWidgets('recompilar un panel no toca el de al lado', (tester) async {
      // La acción de después de editar: cambias el valenciano, lo recompilas
      // y se actualiza esa columna sin perder de vista la otra.
      final compiler = await pumpUnit(tester, languages: const ['es', 'va']);
      expect(compiler.calls, hasLength(1));

      await tester.tap(find.byKey(const Key('pane-recompile-va')));
      await settle(tester);

      // Una compilación más, de un solo perfil y un solo idioma.
      expect(compiler.calls, hasLength(2));
      expect(compiler.calls.last.profiles, ['slides']);
      expect(compiler.calls.last.languages, ['va']);
      // Y la pestaña sigue teniendo los dos paneles.
      expect(find.text('slides · es va'), findsOneWidget);
      expect(find.byKey(const Key('pane-recompile-es')), findsOneWidget);
    });
  });

  testWidgets('se llega desde la pestaña de la unidad', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: FakeCompiler(),
    );
    await session.primeForTest(catalogue);

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: UnitPage(unitPath: unitPath)),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('compilar'));
    await settle(tester);
    expect(find.text('Compilar esta unidad'), findsOneWidget);
  });
}
