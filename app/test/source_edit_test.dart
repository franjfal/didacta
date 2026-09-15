/// Editar en la vista del fuente: varios ficheros en una pantalla.
///
/// Sin modo: cada fragmento es una caja de texto desde que se abre la
/// pantalla, así que aquí se escribe en ella directamente, como se haría con
/// el ratón.
///
/// Lo que se demuestra es lo que pierde trabajo si falla: que lo escrito va
/// **al fichero del que salió el trozo**, que guardar es un commit con todos
/// los tocados y ninguno más, que un fichero que ha cambiado en el repositorio
/// no se pisa —y que entonces no se escribe **nada**, ni siquiera lo que no
/// chocaba—, y que un apartado no se teclea en el sitio porque su título vive
/// en `year.yaml` en tres idiomas.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/tex_toolbar.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String definition = 'content/analysis/normed/definition';
const String banach = 'content/analysis/normed/banach';

/// Un gateway donde un fichero cambia bajo los pies entre dos lecturas.
///
/// Es el caso que hay que probar y el que no se puede montar con ficheros
/// fijos: alguien guardó mientras tú escribías.
class ShiftingGateway extends FakeGateway {
  ShiftingGateway({required super.files, required this.moved});

  final Set<String> moved;
  final Map<String, int> _reads = {};

  @override
  Future<ContentFile> read(String path) async {
    final file = await super.read(path);
    final count = (_reads[path] ?? 0) + 1;
    _reads[path] = count;
    if (moved.contains(path) && count > 1) {
      return ContentFile(path: path, text: file.text, sha: 'otro-sha');
    }
    return file;
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i += 1) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<FakeGateway> pumpSource(
  WidgetTester tester, {
  Map<String, String>? files,
  FakeGateway? gateway,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used =
      gateway ??
      FakeGateway(
        files:
            files ??
            {
              '$definition/es.tex': 'Una norma.\n',
              '$banach/es.tex': 'Banach.\n',
            },
      );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: used, catalogue: catalogue);
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
  return used;
}

/// La caja de un fichero.
/// La caja de texto de un fichero. La clave va en la caja de Didacta, que
/// lleva las columnas de color; dentro está el `TextField` de siempre.
Finder fieldFor(String path) => find.descendant(
  of: find.byKey(Key('source-field-$path')),
  matching: find.byType(TextField),
);

String textIn(WidgetTester tester, String path) =>
    tester.widget<TextField>(fieldFor(path)).controller!.text;

/// Escribe en la caja de un fichero, como se haría con el ratón.
Future<void> type(WidgetTester tester, String path, String text) async {
  await tester.enterText(fieldFor(path), text);
  await settle(tester);
}

void main() {
  testWidgets('el texto está en su caja desde el principio', (tester) async {
    await pumpSource(tester);

    // Sin modo: no hay nada que abrir, cada fichero ya es su caja.
    expect(textIn(tester, '$definition/es.tex'), 'Una norma.\n');
    expect(textIn(tester, '$banach/es.tex'), 'Banach.\n');
  });

  testWidgets('la barra está arriba y actúa sobre el fichero del cursor', (
    tester,
  ) async {
    await pumpSource(tester);

    // Arriba y siempre: apagada mientras no haya cursor en ninguna caja, en
    // lugar de aparecer y empujar la pantalla.
    expect(find.byType(TexToolbar), findsOneWidget);
    expect(
      (tester.widget(find.byKey(const Key('wrap-onlyslides'))) as dynamic)
          .onPressed,
      isNull,
    );

    await tester.tap(fieldFor('$banach/es.tex'));
    await settle(tester);

    expect(
      (tester.widget(find.byKey(const Key('wrap-onlyslides'))) as dynamic)
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('la barra envuelve en el fichero que tiene el cursor', (
    tester,
  ) async {
    await pumpSource(tester);

    await tester.tap(fieldFor('$banach/es.tex'));
    await settle(tester);
    tester.widget<TextField>(fieldFor('$banach/es.tex')).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();

    // En escritorio, pulsar un botón le quita el foco al campo. La barra no
    // puede apagarse por eso: entre que se aprieta y se suelta el botón ya
    // estaría gris y el clic no haría nada, que es exactamente lo que pasaba.
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(find.byKey(const Key('wrap-onlyslides')));
    await settle(tester);

    expect(textIn(tester, '$banach/es.tex'), '\\onlyslides{Banach.}\n');
    // Y el de al lado ni se entera.
    expect(textIn(tester, '$definition/es.tex'), 'Una norma.\n');
  });

  testWidgets('el editor aparta el texto por la sangría más honda', (
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

    // La sangría más honda del fichero es de dos niveles, y la caja tiene un
    // solo margen izquierdo: se le aparta esa, y dentro se ve el fichero tal
    // como está escrito --la sangría es de la vista y no se guarda--.
    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: fieldFor('$definition/es.tex'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect((padding.padding as EdgeInsets).left, 2 * 14.0);
  });

  testWidgets('las guías miden el texto igual que la caja', (tester) async {
    // La suposición de la que depende todo esto: que midiendo por fuera con el
    // mismo estilo y el mismo strut salen las mismas líneas que dentro de la
    // caja. Si deja de ser cierta --otra versión de Flutter, otro tema-- las
    // guías se corren y no hay forma de verlo mirando el código.
    const long =
        'Una línea deliberadamente larga para que la caja la parta en dos o '
        'en tres trozos y haya que medirla partida, que es justo el caso que '
        'descuadra si las dos capas no miden igual.\n';
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex':
            '\\begin{frame}\n\\begin{exercise}\n'
            '$long'
            '\\end{exercise}\n'
            '\\end{frame}\n',
        '$banach/es.tex': 'Banach.\n',
      },
    );

    final box = tester.renderObject<RenderBox>(
      find.descendant(
        of: fieldFor('$definition/es.tex'),
        matching: find.byType(EditableText),
      ),
    );
    final field = tester.widget<TextField>(fieldFor('$definition/es.tex'));
    final painter = TextPainter(
      text: TextSpan(text: field.controller!.text, style: field.style),
      strutStyle: field.strutStyle,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.size.width);

    expect(painter.height, moreOrLessEquals(box.size.height, epsilon: 0.5));
    // Y partida de verdad, que si no la prueba no prueba nada.
    expect(
      painter.computeLineMetrics().length,
      greaterThan(field.controller!.text.split('\n').length - 1),
    );
    painter.dispose();
  });

  testWidgets('lo escrito va al fichero del que salió el trozo', (
    tester,
  ) async {
    final gateway = await pumpSource(tester);

    await type(tester, '$banach/es.tex', 'Un espacio de Banach es completo.\n');

    expect(find.textContaining('1 fichero tocado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-save')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('source-commit-save')));
    await settle(tester);

    expect(gateway.commits.length, 1);
    expect(gateway.commits.single.path, '$banach/es.tex');
    expect(gateway.commits.single.text, 'Un espacio de Banach es completo.\n');
  });

  testWidgets('dos ficheros tocados son un commit con los dos', (tester) async {
    final gateway = await pumpSource(tester);

    await type(tester, '$definition/es.tex', 'Una norma, reescrita.\n');
    await type(tester, '$banach/es.tex', 'Banach, reescrito.\n');

    expect(find.textContaining('2 ficheros tocados'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-save')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('source-commit-save')));
    await settle(tester);

    // En orden de ruta, que es el mismo que enseñó el diálogo: el commit no
    // puede decir una cosa y la pantalla otra.
    expect(
      [for (final commit in gateway.commits) commit.path],
      ['$banach/es.tex', '$definition/es.tex'],
    );
    // Un gesto, un mensaje: se editó una cosa repartida en dos ficheros.
    expect(gateway.commits.first.message, gateway.commits.last.message);
  });

  testWidgets('si un fichero ha cambiado no se escribe ninguno', (
    tester,
  ) async {
    final gateway = ShiftingGateway(
      files: {
        '$definition/es.tex': 'Una norma.\n',
        '$banach/es.tex': 'Banach.\n',
      },
      moved: {'$banach/es.tex'},
    );
    await pumpSource(tester, gateway: gateway);

    await type(tester, '$definition/es.tex', 'Una norma, reescrita.\n');
    await type(tester, '$banach/es.tex', 'Banach, reescrito.\n');

    await tester.tap(find.byKey(const Key('source-save')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('source-commit-save')));
    await settle(tester);

    // Ni el que chocaba ni el que no: un conflicto en el segundo fichero no
    // puede dejar el primero escrito y el trabajo a medias.
    expect(gateway.commits, isEmpty);
    expect(find.textContaining('$banach/es.tex'), findsWidgets);
    expect(find.textContaining('No se ha escrito nada'), findsOneWidget);
  });

  testWidgets('descartar devuelve los ficheros a como estaban', (tester) async {
    final gateway = await pumpSource(tester);

    await type(tester, '$definition/es.tex', 'Otra cosa.\n');
    expect(find.textContaining('1 fichero tocado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-discard')));
    await settle(tester);

    expect(find.textContaining('tocado'), findsNothing);
    expect(textIn(tester, '$definition/es.tex'), 'Una norma.\n');
    expect(gateway.commits, isEmpty);
  });

  testWidgets('el idioma del documento cambia todos los fragmentos', (
    tester,
  ) async {
    await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Una norma.\n',
        '$banach/es.tex': 'Banach.\n',
        '$banach/va.tex': 'Banach en valencià.\n',
      },
    );

    await tester.tap(find.byKey(const Key('source-document-language-va')));
    await settle(tester);

    // La que está traducida, en valenciano.
    expect(textIn(tester, '$banach/va.tex'), 'Banach en valencià.\n');
    // Y la que no, en el suyo y diciéndolo: un hueco describiría un documento
    // que no es el que se compila (D13).
    expect(textIn(tester, '$definition/es.tex'), 'Una norma.\n');
  });

  group('las pestañas de idioma de un fragmento', () {
    testWidgets('cambian solo ese trozo', (tester) async {
      await pumpSource(
        tester,
        files: {
          '$definition/es.tex': 'Una norma.\n',
          '$banach/es.tex': 'Banach.\n',
          '$banach/va.tex': 'Banach en valencià.\n',
        },
      );

      await tester.tap(find.byKey(const Key('source-language-$banach/va.tex')));
      await settle(tester);

      // El fragmento cambia de idioma; el de al lado se queda como estaba.
      expect(textIn(tester, '$banach/va.tex'), 'Banach en valencià.\n');
      expect(textIn(tester, '$definition/es.tex'), 'Una norma.\n');
      expect(find.text('$banach/va.tex'), findsOneWidget);
    });

    testWidgets('un idioma que no existe se abre vacío para crearlo', (
      tester,
    ) async {
      await pumpSource(tester);

      await tester.tap(
        find.byKey(const Key('source-language-$definition/en.tex')),
      );
      await settle(tester);

      expect(textIn(tester, '$definition/en.tex'), isEmpty);
      expect(find.textContaining('No existe la versión en en'), findsOneWidget);
    });
  });

  testWidgets('el título de un apartado se escribe en year.yaml', (
    tester,
  ) async {
    final gateway = await pumpSource(
      tester,
      files: {
        '$definition/es.tex': 'Una norma.\n',
        '$banach/es.tex': 'Banach.\n',
        'courses/am-iii/2025-2026/year.yaml': yearYaml,
      },
    );

    // No se teclea en el sitio: su título vive en `year.yaml` en los tres
    // idiomas, y escrito aquí se escribiría en uno solo.
    await tester.tap(find.byKey(const Key('source-heading-0')));
    await settle(tester);

    expect(find.text('Título del apartado'), findsOneWidget);
    expect(find.byKey(const Key('heading-title-va')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('heading-title-va')), 'Normes');
    await tester.tap(find.byKey(const Key('heading-title-save')));
    await settle(tester);

    final commit = gateway.commits.single;
    expect(commit.path, 'courses/am-iii/2025-2026/year.yaml');
    expect(commit.text, contains('va: Normes'));
    // Y lo que no se tocó sigue ahí: el `# TODO: en` es la lista de trabajo
    // que un round trip por un parser habría borrado en silencio (D40).
    expect(commit.text, contains('# TODO: en'));
  });
}
