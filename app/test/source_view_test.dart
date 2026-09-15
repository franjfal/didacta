/// La vista del fuente: el documento entero con los cortes a la vista.
///
/// Lo que se demuestra montado: que se leen las unidades en el orden de la
/// composición, que el apartado sale como lo que es —una entrada de
/// `year.yaml`, no texto de ningún fichero—, que una referencia rota se ve, y
/// que un entorno sin cerrar se denuncia diciendo **qué fichero y qué línea**,
/// que es justo lo que LaTeX no sabe decir.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// La caja de texto de un fichero. La clave va en la caja de Didacta, que
/// lleva las columnas de color; dentro está el `TextField` de siempre.
Finder fieldFor(String path) => find.descendant(
  of: find.byKey(Key('source-field-$path')),
  matching: find.byType(TextField),
);

String textIn(WidgetTester tester, String path) =>
    tester.widget<TextField>(fieldFor(path)).controller!.text;

const String definition = 'content/analysis/normed/definition';
const String banach = 'content/analysis/normed/banach';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpSource(
  WidgetTester tester, {
  required Map<String, String> files,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(files: files),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: DocumentPage(
            courseId: 'am-iii',
            year: '2025-2026',
            documentId: 'tema-1',
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Fuente'));
  await settle(tester);
}

void main() {
  testWidgets('las unidades salen en orden, cada una tras su ruta', (
    tester,
  ) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Una norma es una aplicación.\n',
        '$banach/es.tex': 'Un espacio de Banach es completo.\n',
      },
    );

    expect(
      textIn(tester, '$definition/es.tex'),
      'Una norma es una aplicación.\n',
    );
    expect(
      textIn(tester, '$banach/es.tex'),
      'Un espacio de Banach es completo.\n',
    );
    // La línea de puntos lleva la ruta del fichero: es a donde vuelve una
    // edición y lo que se pulsa para ir a él.
    expect(find.text('$definition/es.tex'), findsOneWidget);
    expect(find.text('$banach/es.tex'), findsOneWidget);
  });

  testWidgets('la sangría se aparta sola, y no toca el fichero', (
    tester,
  ) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex':
            '\\begin{frame}\n\\begin{exercise}\nEnunciado.\n'
            '\\end{exercise}\n\\end{frame}\n',
        '$banach/es.tex': 'Banach.\n',
      },
    );

    // Dos niveles de sangría en el fichero, dos columnas apartadas. Sin
    // pulsar nada: lo calcula el árbol y se pinta.
    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: fieldFor('$definition/es.tex'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect((padding.padding as EdgeInsets).left, 2 * 14.0);

    // Y el fichero sigue como estaba: la sangría no es un dato suyo --leída
    // sola, esta unidad no cuelga de nada-- así que no se escribe.
    expect(find.textContaining('tocado'), findsNothing);
    expect(
      textIn(tester, '$definition/es.tex'),
      startsWith('\\begin{frame}\n'),
    );
  });

  testWidgets('el apartado se ve como apartado, no como texto', (tester) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Texto.\n',
        '$banach/es.tex': 'Más texto.\n',
      },
    );

    expect(find.text('Normas'), findsOneWidget);
    // Su título vive en `year.yaml` en los tres idiomas: aquí se marca como
    // lo que es para que nadie lo teclee en uno solo.
    expect(find.text('apartado'), findsOneWidget);
  });

  testWidgets('una referencia que no resuelve se ve donde iba', (tester) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Texto.\n',
        '$banach/es.tex': 'Más texto.\n',
      },
    );

    // La composición del fixture referencia una unidad que no existe.
    // Saltarla en silencio es cómo se llega a clase con un hueco.
    expect(find.textContaining('analysis/normed/no-existe'), findsOneWidget);
  });

  testWidgets('las diapositivas se cuentan y se pueden marcar', (tester) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex':
            'Prosa que no se proyecta.\n'
            '\\begin{frame}\nEn la diapositiva.\n\\end{frame}\n',
        '$banach/es.tex': 'Más prosa.\n',
      },
    );

    expect(find.textContaining('1 diapositivas'), findsOneWidget);
    // Con diapositivas, marcar lo que no se proyecta significa algo y sale
    // encendido.
    final toggle = tester.widget<Switch>(find.byKey(const Key('source-dim')));
    expect(toggle.value, isTrue);
  });

  testWidgets('sin diapositivas no se ofrece marcar nada', (tester) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Solo prosa.\n',
        '$banach/es.tex': 'Más prosa.\n',
      },
    );

    // Todo en gris no dice nada.
    expect(find.byKey(const Key('source-dim')), findsNothing);
  });

  testWidgets('un entorno sin cerrar dice el fichero y la línea', (
    tester,
  ) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Antes.\n\\begin{frame}\nSin cerrar.\n',
        '$banach/es.tex': 'Más texto.\n',
      },
    );

    // LaTeX, ante esto, denuncia la línea de la composición que incluye la
    // unidad y saca un PDF de una página que parece correcto.
    expect(
      find.textContaining('«frame» se abre y no se cierra'),
      findsOneWidget,
    );
    expect(find.textContaining('$definition/es.tex:2'), findsOneWidget);
  });
}
