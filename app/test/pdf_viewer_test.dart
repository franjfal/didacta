/// Los mandos del visor de PDF, sin abrir ningún PDF.
///
/// Lo que se comprueba aquí es la parte que se puede equivocar en silencio:
/// que escribir una página lleve a esa página y no a otra, que un número
/// imposible se recorte en lugar de dejar el visor en blanco, que teclear
/// «1» camino del «14» no salte a la primera, y que el lateral ofrezca el
/// índice sólo cuando el documento trae uno.
///
/// Sin `PdfViewer` a propósito: abrir uno necesita pdfium y un fichero, y
/// eso es lo que prueba compilar de verdad. Aquí lo que se prueba es la
/// interfaz, que es donde estaban los fallos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:didacta_app/ui/pdf_controls.dart';
import 'package:didacta_app/ui/pdf_sidebar.dart';

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('el número de página', () {
    testWidgets('escribirlo lleva a esa página', (tester) async {
      final asked = <int>[];
      await pump(
        tester,
        PdfPageField(page: 1, pages: 14, onGoToPage: asked.add),
      );
      await tester.enterText(find.byKey(const Key('pdf-page-field')), '9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(asked, [9]);
    });

    testWidgets('uno que no existe se recorta al último', (tester) async {
      final asked = <int>[];
      await pump(
        tester,
        PdfPageField(page: 1, pages: 14, onGoToPage: asked.add),
      );
      await tester.enterText(find.byKey(const Key('pdf-page-field')), '900');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(asked, [14]);
    });

    testWidgets('teclear no navega hasta Intro', (tester) async {
      // Escribir el `1` de «14» no puede saltar a la primera página.
      final asked = <int>[];
      await pump(
        tester,
        PdfPageField(page: 7, pages: 14, onGoToPage: asked.add),
      );
      await tester.enterText(find.byKey(const Key('pdf-page-field')), '1');
      await tester.pump();
      expect(asked, isEmpty);
    });

    testWidgets('pasar página fuera del campo lo actualiza', (tester) async {
      await pump(
        tester,
        const PdfPageField(page: 3, pages: 14, onGoToPage: _ignore),
      );
      await pump(
        tester,
        const PdfPageField(page: 4, pages: 14, onGoToPage: _ignore),
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('pdf-page-field')),
      );
      expect(field.controller!.text, '4');
    });
  });

  group('el zoom', () {
    testWidgets('sin visor listo, los mandos están apagados', (tester) async {
      await pump(
        tester,
        const PdfZoomControls(
          zoom: null,
          onZoomOut: null,
          onZoomIn: null,
          onActualSize: null,
          onFitWidth: null,
          onFitHeight: null,
          onFitPage: null,
        ),
      );
      expect(find.text('—'), findsOneWidget);
      for (final key in const [
        'pdf-zoom-in',
        'pdf-zoom-out',
        'pdf-fit-width',
        'pdf-fit-height',
        'pdf-fit-page',
      ]) {
        expect(
          tester.widget<IconButton>(find.byKey(Key(key))).onPressed,
          isNull,
          reason: key,
        );
      }
    });

    testWidgets('enseña el porcentaje y los tres ajustes', (tester) async {
      final done = <String>[];
      await pump(
        tester,
        PdfZoomControls(
          zoom: 1.37,
          onZoomOut: () => done.add('out'),
          onZoomIn: () => done.add('in'),
          onActualSize: () => done.add('real'),
          onFitWidth: () => done.add('ancho'),
          onFitHeight: () => done.add('alto'),
          onFitPage: () => done.add('página'),
        ),
      );
      expect(find.text('137%'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-fit-width')));
      await tester.tap(find.byKey(const Key('pdf-fit-height')));
      await tester.tap(find.byKey(const Key('pdf-fit-page')));
      await tester.tap(find.byKey(const Key('pdf-zoom-actual')));
      expect(done, ['ancho', 'alto', 'página', 'real']);
    });
  });

  group('la barra cabe', barFits);

  group('el lateral', () {
    const outline = [
      PdfOutlineNode(
        title: 'Apéndice',
        dest: PdfDest(9, PdfDestCommand.fit, null),
        children: [
          PdfOutlineNode(
            title: 'Logaritmos',
            dest: PdfDest(9, PdfDestCommand.fit, null),
            children: [],
          ),
        ],
      ),
    ];

    testWidgets('enseña el índice y salta a su destino', (tester) async {
      final asked = <PdfDest?>[];
      await pump(
        tester,
        SizedBox(
          height: 400,
          child: PdfSidebar(
            document: null,
            outline: outline,
            page: 1,
            onGoToPage: _ignore,
            onGoToDest: asked.add,
          ),
        ),
      );
      expect(find.text('Apéndice'), findsOneWidget);
      expect(find.text('Logaritmos'), findsOneWidget);
      await tester.tap(find.text('Logaritmos'));
      expect(asked.single?.pageNumber, 9);
    });

    testWidgets('sin marcadores no ofrece la pestaña del índice', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          height: 400,
          child: PdfSidebar(
            document: null,
            outline: [],
            page: 1,
            onGoToPage: _ignore,
            onGoToDest: _ignoreDest,
          ),
        ),
      );
      expect(find.byKey(const Key('pdf-sidebar-outline')), findsNothing);
      expect(find.byKey(const Key('pdf-sidebar-pages')), findsNothing);
    });

    testWidgets('con marcadores se puede cambiar a las páginas', (
      tester,
    ) async {
      await pump(
        tester,
        SizedBox(
          height: 400,
          child: PdfSidebar(
            document: null,
            outline: outline,
            page: 1,
            onGoToPage: _ignore,
            onGoToDest: _ignoreDest,
          ),
        ),
      );
      expect(find.byKey(const Key('pdf-outline-list')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-sidebar-pages')));
      await tester.pump();
      expect(find.byKey(const Key('pdf-outline-list')), findsNothing);
    });
  });
}

/// Los anchos donde se rompen las barras, y los de alrededor. Los mismos
/// que mide la del editor: en modo lado a lado un panel es un tercio de
/// ventana, así que los pequeños son tan reales como los grandes (D75).
const List<double> widths = [
  420,
  520,
  620,
  700,
  760,
  800,
  860,
  915,
  1000,
  1100,
  1280,
  1600,
];

void barFits() {
  for (final width in widths) {
    testWidgets('a ${width.toInt()} px de ancho la barra no se desborda', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PdfViewerBar(
                  page: 7,
                  pages: 120,
                  sidebar: false,
                  zoom: 1.37,
                  onSidebar: () {},
                  onGoToPage: _ignore,
                  onZoomOut: () {},
                  onZoomIn: () {},
                  onActualSize: () {},
                  onFitWidth: () {},
                  onFitHeight: () {},
                  onFitPage: () {},
                  label: 'Práctica 1 el número real - handout - es.pdf',
                  labelDirection: TextDirection.rtl,
                  trailing: [
                    IconButton(
                      icon: const Icon(Icons.call_split, size: 17),
                      onPressed: () {},
                    ),
                    IconButton(
                      key: const Key('pdf-recompile'),
                      icon: const Icon(Icons.tune, size: 17),
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Lo que no puede desaparecer al encoger: sin la página y sin el
      // zoom, la barra deja de servir para lo que está.
      expect(find.byKey(const Key('pdf-page-field')), findsOneWidget);
      expect(find.byKey(const Key('pdf-zoom-in')), findsOneWidget);
      expect(find.byKey(const Key('pdf-sidebar-toggle')), findsOneWidget);
      expect(find.byKey(const Key('pdf-recompile')), findsOneWidget);
      // Y los ajustes siguen alcanzables, sueltos o dentro del menú.
      expect(
        find.byKey(const Key('pdf-fit-width')).evaluate().isNotEmpty ||
            find.byKey(const Key('pdf-fit-menu')).evaluate().isNotEmpty,
        isTrue,
      );
    });
  }
}

void _ignore(int _) {}

void _ignoreDest(PdfDest? _) {}
