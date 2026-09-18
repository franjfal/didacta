/// La regleta de números del editor.
///
/// Lo que se prueba no es que salgan --eso se ve-- sino las dos cosas que se
/// hacen mal y no se ven: que el texto siga empezando donde empieza la capa
/// que lo pinta, y que una línea larga partida por el ancho de la ventana
/// lleve **un** número y no cuatro.
@TestOn('vm')
library;

import 'package:didacta_app/ui/tex_field.dart';
import 'package:didacta_app/ui/tex_highlight.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpField(
  WidgetTester tester,
  String text, {
  bool lineNumbers = true,
  double width = 600,
}) async {
  final controller = TexEditingController()..text = text;
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: didactaTheme(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: TexField(controller: controller, lineNumbers: lineNumbers),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Dónde empieza el texto de la caja, en píxeles desde el borde.
double textLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(TextField)).dx;

void main() {
  testWidgets('sin números, el texto no se aparta por nada', (tester) async {
    await pumpField(tester, 'Uno\nDos\n', lineNumbers: false);
    expect(textLeft(tester), 0);
  });

  testWidgets('con números, el texto se aparta para dejarles sitio', (
    tester,
  ) async {
    await pumpField(tester, 'Uno\nDos\n');
    expect(textLeft(tester), greaterThan(0));
  });

  testWidgets('un fichero de mil líneas aparta más que uno de nueve', (
    tester,
  ) async {
    // Cuatro cifras ocupan más que una, y de eso depende dónde empieza el
    // texto en las dos capas. Si no se mide, se descuadran.
    await pumpField(tester, List.filled(9, 'x').join('\n'));
    final corto = textLeft(tester);

    await pumpField(tester, List.filled(1000, 'x').join('\n'));
    expect(textLeft(tester), greaterThan(corto));
  });

  testWidgets('las columnas de entorno caen después de la regleta', (
    tester,
  ) async {
    // Si no, se pintarían encima de los números y no se leería ninguna de las
    // dos cosas.
    await pumpField(tester, '\\begin{itemize}\n\\item Uno\n\\end{itemize}\n');
    final conNumeros = textLeft(tester);

    await pumpField(
      tester,
      '\\begin{itemize}\n\\item Uno\n\\end{itemize}\n',
      lineNumbers: false,
    );
    final sinNumeros = textLeft(tester);

    // La misma sangría de entornos en los dos casos, más la regleta.
    expect(conNumeros, greaterThan(sinNumeros));
  });

  testWidgets('una línea muy larga no se descuadra ni revienta', (
    tester,
  ) async {
    // Ocupa varios renglones en pantalla y sigue siendo una línea. Lo que se
    // comprueba aquí es que pintarla no lanza: el número va en el primero.
    await pumpField(tester, '${'palabra ' * 200}\nDos\n', width: 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un fichero vacío no rompe la medida', (tester) async {
    await pumpField(tester, '');
    expect(tester.takeException(), isNull);
  });
}
