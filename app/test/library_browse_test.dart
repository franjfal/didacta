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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
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
    // alguien crea que le falta material.
    expect(find.text('problemas'), findsOneWidget);
    await tester.tap(find.text('problemas'));
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
    expect(find.text('Espacios normados'), findsWidgets);
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
    // Y sus unidades, con la teoría y sus ejercicios juntos.
    expect(find.text('Espacios normados'), findsWidgets);
    expect(find.text('Espacios de Banach'), findsWidgets);
    expect(find.text('Ejercicios de normas'), findsWidgets);
  });
}
