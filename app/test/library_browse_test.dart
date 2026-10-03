/// La biblioteca como se navega, no como se busca.
///
/// Existe porque la pantalla anterior pasaba todos sus tests y era mala: los
/// tests decían que la lista listaba, y el problema era que fuera una lista.
/// Así que esto comprueba lo que la vista tiene que hacer de verdad —bajar
/// tres niveles, contar bien, y decir a la cara cuánto está sin revisar— y no
/// que los widgets existan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/library_tree.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Map<String, dynamic>>? units,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(units ?? defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: LibraryPage()),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('al entrar cuenta lo que hay, no lista 2147 filas', (
    tester,
  ) async {
    await pumpLibrary(tester);

    // El fixture: 4 unidades en 2 categorías (analysis y algebra) y 2 temas.
    expect(find.textContaining('4 unidades'), findsOneWidget);
    expect(find.textContaining('2 categorías'), findsWidgets);
    expect(find.textContaining('2 temas'), findsWidgets);

    // Y la pregunta que responde al abrirla.
    expect(find.text('Dónde está el material'), findsOneWidget);
  });

  testWidgets('una categoría no se parte por área', (tester) async {
    await pumpLibrary(tester);

    // `analysis` tiene teoría y problemas: es una categoría, no dos. Que
    // aparezca una sola vez es justo lo que estaba mal.
    expect(find.text('Analysis'), findsNWidgets(2)); // columna y tarjeta
    expect(find.text('Algebra'), findsNWidgets(2));
  });

  testWidegtsBajar();

  testWidgets('la leyenda dice qué significan los colores', (tester) async {
    await pumpLibrary(tester);

    // Sin esto la barra es decoración. Y hace falta: el material migrado
    // está entero en `draft`, y una pared ámbar sin explicar parece un fallo.
    expect(find.textContaining('al día'), findsWidgets);
    expect(find.textContaining('por revisar'), findsWidgets);
    expect(find.textContaining('sin escribir'), findsWidgets);
  });

  testWidgets('la barra se dibuja con un tramo por estado', (tester) async {
    // Directamente sobre el widget: es la señal principal de la pantalla, y
    // una barra que no se dibuja es indistinguible de un grupo vacío.
    const progress = TranslationProgress(
      total: 4,
      done: 1,
      needsWork: 2,
      missing: 1,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: ProgressBar(progress: progress)),
        ),
      ),
    );

    final flexes = tester
        .widgetList<Expanded>(find.byType(Expanded))
        .map((e) => e.flex)
        .toList();
    expect(flexes, [1, 2, 1]);
    // Y tiene altura de verdad: a 4 px no se veía.
    final box = tester.getSize(find.byType(ProgressBar));
    expect(box.height, greaterThanOrEqualTo(5));
  });

  testWidgets('un grupo vacío no dibuja una barra falsa', (tester) async {
    const progress = TranslationProgress(
      total: 0,
      done: 0,
      needsWork: 0,
      missing: 0,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProgressBar(progress: progress)),
      ),
    );
    expect(find.byType(Expanded), findsNothing);
  });

  testWidgets('el filtro de área cambia las categorías y los recuentos', (
    tester,
  ) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('Problemas'));
    await settle(tester);

    // El fixture tiene una sola unidad en problems/, en analysis.
    expect(find.textContaining('1 unidades'), findsOneWidget);
    expect(find.textContaining('1 categorías'), findsWidgets);
    expect(find.text('Algebra'), findsNothing);
  });

  testWidgets('escribir cambia a la lista, que para buscar es lo correcto', (
    tester,
  ) async {
    await pumpLibrary(tester);

    // `exercises` está en una sola ruta; `banach` es una etiqueta de las
    // cuatro unidades del fixture y encontraría todo.
    await tester.enterText(find.byType(TextField).first, 'exercises');
    await settle(tester);

    // Ya no se explora: se buscan coincidencias, que no tienen por qué estar
    // juntas en el árbol.
    expect(find.textContaining('Buscando «exercises»'), findsOneWidget);
    expect(find.text('Dónde está el material'), findsNothing);
    expect(find.textContaining('1 unidad de 4'), findsOneWidget);
    expect(find.text('Ejercicios de normas'), findsWidgets);
  });

  testWidgets('vaciar la búsqueda vuelve al árbol', (tester) async {
    await pumpLibrary(tester);

    await tester.enterText(find.byType(TextField).first, 'exercises');
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester);

    expect(find.text('Dónde está el material'), findsOneWidget);
  });

  testWidgets('un filtro puesto se ve y se quita de un toque', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('Problemas'));
    await settle(tester);

    // La ficha: un filtro activo que no se ve es la forma más rápida de que
    // alguien crea que le falta material. Lleva el nombre del bloque, que
    // ahora sale de lo que el repositorio declare y no de una cadena escrita
    // aquí; por eso se busca por clave y no por texto, que está dos veces en
    // pantalla --en la pestaña y en la ficha--.
    final chip = find.byKey(const Key('filter-chip-block'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Problemas')),
      findsOneWidget,
    );
    await tester.tap(chip);
    await settle(tester);
    expect(find.textContaining('4 unidades'), findsOneWidget);
  });

  testWidgets('en móvil se baja un nivel a la vez', (tester) async {
    await pumpLibrary(tester, size: const Size(390, 844));

    // Sin sitio para tres columnas: primero las categorías.
    expect(find.text('Dónde está el material'), findsNothing);
    expect(find.text('Analysis'), findsOneWidget);

    await tester.tap(find.text('Analysis'));
    await settle(tester);
    // Ahora los temas, con migas de pan para volver.
    expect(find.text('Normed'), findsOneWidget);
    expect(find.text('Biblioteca'), findsWidgets);

    await tester.tap(find.text('Normed'));
    await settle(tester);
    // Los subtemas; sin ninguno declarado, el suyo es «Sin subtema».
    await tester.tap(find.text('Sin subtema'));
    await settle(tester);
    expect(find.text('Espacios normados'), findsWidgets);
  });

  group('los subtemas, en su columna', () {
    // El tercer nivel: categoría, tema, subtema, lecciones. Antes eran
    // etiquetas en fichas encima de la lista; ahora cada lección está en uno
    // solo, que es también su carpeta, y es una columna como las otras.
    List<Map<String, dynamic>> units() => [
      unitJson(
        path: 'content/analysis/normed/conceptos/definition',
        subtopic: 'conceptos',
      ),
      unitJson(
        path: 'content/analysis/normed/conceptos/banach',
        subtopic: 'conceptos',
        title: const {'es': 'Espacios de Banach'},
      ),
      unitJson(
        path: 'problems/analysis/normed/ejercicios/exercises',
        area: 'problems',
        kind: 'problem',
        subtopic: 'ejercicios',
        title: const {'es': 'Ejercicios de normas'},
      ),
      unitJson(
        path: 'content/algebra/matrices/rango/rank',
        category: 'algebra',
        topic: 'matrices',
        subtopic: 'rango',
        title: const {'es': 'El rango'},
      ),
    ];

    Future<void> entrarEnElTema(WidgetTester tester) async {
      await pumpLibrary(tester, units: units());
      await tester.tap(find.text('Analysis').first);
      await settle(tester);
      await tester.tap(find.text('Normed').first);
      await settle(tester);
    }

    testWidgets('salen en una columna, con su cuenta', (tester) async {
      await entrarEnElTema(tester);
      expect(find.text('2 SUBTEMAS'), findsOneWidget);
      expect(find.byKey(const Key('subtopic-conceptos')), findsOneWidget);
      expect(find.byKey(const Key('subtopic-ejercicios')), findsOneWidget);
      // Sin elegir ninguno no hay lista, como en el Finder: la derecha dice
      // que falta el subtema.
      expect(find.text('Ejercicios de normas'), findsNothing);
      expect(find.byKey(const Key('library-choose-subtopic')), findsOneWidget);
    });

    testWidgets('elegir uno deja solo sus lecciones', (tester) async {
      await entrarEnElTema(tester);
      await tester.tap(find.byKey(const Key('subtopic-conceptos')));
      await settle(tester);

      expect(find.text('Espacios normados'), findsWidgets);
      expect(find.text('Espacios de Banach'), findsWidgets);
      expect(find.text('Ejercicios de normas'), findsNothing);
      expect(find.text('2 unidades'), findsOneWidget);
    });

    testWidgets('el subtema es un nivel más de las migas de pan', (
      tester,
    ) async {
      await entrarEnElTema(tester);
      await tester.tap(find.byKey(const Key('subtopic-conceptos')));
      await settle(tester);

      // Y el tema vuelve a ser pulsable para salir del subtema sin salir del
      // tema.
      expect(find.byKey(const Key('crumb-subtopic')), findsOneWidget);
      await tester.tap(find.byKey(const Key('crumb-topic')));
      await settle(tester);
      expect(find.text('Espacios de Banach'), findsNothing);
      expect(find.byKey(const Key('library-choose-subtopic')), findsOneWidget);
    });

    testWidgets('cambiar de tema empieza sin subtema', (tester) async {
      await entrarEnElTema(tester);
      await tester.tap(find.byKey(const Key('subtopic-conceptos')));
      await settle(tester);

      await tester.tap(find.text('Algebra').first);
      await settle(tester);
      await tester.tap(find.text('Matrices').first);
      await settle(tester);
      expect(find.byKey(const Key('subtopic-rango')), findsOneWidget);
      expect(find.text('El rango'), findsNothing);
      await tester.tap(find.byKey(const Key('subtopic-rango')));
      await settle(tester);
      expect(find.text('El rango'), findsWidgets);
    });

    testWidgets('en una ventana mediana, las columnas de la izquierda se van', (
      tester,
    ) async {
      // Como el Finder: con un tema elegido no caben las cuatro, y las
      // categorías dejan sitio; las migas de pan dicen dónde se está.
      await pumpLibrary(tester, units: units(), size: const Size(900, 900));
      await tester.tap(find.text('Analysis').first);
      await settle(tester);
      await tester.tap(find.text('Normed').first);
      await settle(tester);
      expect(find.text('2 CATEGORÍAS'), findsNothing);
      expect(find.text('2 SUBTEMAS'), findsOneWidget);
      expect(find.byKey(const Key('crumb-category')), findsOneWidget);
    });
  });
}

/// Bajar los tres niveles hasta una unidad, que es la razón de la pantalla.
void testWidegtsBajar() {
  testWidgets('tres clics llegan a una unidad', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('Analysis').first);
    await settle(tester);
    // Los temas de la categoría, de mayor a menor.
    expect(find.text('Normed'), findsWidgets);

    await tester.tap(find.text('Normed').first);
    await settle(tester);
    // Con el tema elegido todavía no hay lista: falta el subtema.
    expect(find.text('Espacios de Banach'), findsNothing);
    expect(find.byKey(const Key('library-choose-subtopic')), findsOneWidget);
    // Sin subtemas declarados, el suyo es «Sin subtema».
    await tester.tap(find.text('Sin subtema'));
    await settle(tester);
    // Y sus unidades, con la teoría y sus ejercicios juntos.
    expect(find.text('Espacios normados'), findsWidgets);
    expect(find.text('Espacios de Banach'), findsWidgets);
    expect(find.text('Ejercicios de normas'), findsWidgets);
  });

  group('los filtros también en el árbol, sin buscar nada', () {
    // Se ponían en verde y el árbol seguía enseñándolo todo: solo hacían
    // algo escribiendo en el buscador.
    Future<void> pick(WidgetTester tester, String menu, String item) async {
      await tester.tap(find.text(menu));
      await settle(tester);
      await tester.tap(find.text(item).last);
      await settle(tester);
    }

    testWidgets('«sin usar» deja solo lo que no usa nadie, y lo dice', (
      tester,
    ) async {
      await pumpLibrary(tester);
      await pick(
        tester,
        'Traducción',
        'Solo las que no usa ninguna asignatura',
      );

      // Del fixture, dos no las usa nadie: los ejercicios y la de álgebra.
      expect(find.textContaining('2 de 4 unidades'), findsOneWidget);
      expect(find.textContaining('sin usar'), findsWidgets);
    });

    testWidgets('sin nada que enseñar lo dice y deja quitarlos', (
      tester,
    ) async {
      await pumpLibrary(tester);
      await pick(tester, 'Tipo', kindName('history'));

      expect(find.text('Nada con estos filtros'), findsOneWidget);
      await tester.tap(find.byKey(const Key('library-clear-filters')));
      await settle(tester);
      expect(find.textContaining('4 unidades'), findsOneWidget);
    });

    testWidgets('«Orden» ordena también las listas del árbol', (tester) async {
      await pumpLibrary(tester);
      await tester.tap(find.text('Analysis').first);
      await settle(tester);
      await tester.tap(find.text('Normed').first);
      await settle(tester);
      await tester.tap(find.text('Sin subtema'));
      await settle(tester);

      double top(String title) => tester.getTopLeft(find.text(title).last).dy;
      // Por ruta, de salida: `content/…/banach` antes que `problems/…`.
      expect(top('Espacios de Banach'), lessThan(top('Ejercicios de normas')));

      await pick(tester, 'Orden', 'Por título');
      expect(top('Ejercicios de normas'), lessThan(top('Espacios de Banach')));
    });
  });
}
