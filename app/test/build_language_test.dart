/// En qué idioma se compila, y en cuál se mira lo compilado.
///
/// Didacta compilaba siempre el idioma propio de cada documento. Eso está bien
/// para quien da la asignatura en uno solo, y es exactamente lo contrario de
/// lo que quiere quien la da en dos: la víspera de la clase en valenciano no
/// se quieren los tres idiomas --media hora de compilación-- sino el
/// valenciano.
///
/// Así que **pulsar compila el idioma en el que se está trabajando** y
/// mantener pulsado abre el menú. Y el visor de PDF, que antes solo podía
/// enseñar un idioma porque el motor solo miraba ese, ahora tiene una fila de
/// idiomas encima de la de versiones.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/ui/build_button.dart';
import 'package:didacta_app/ui/pdf_dialog.dart';
import 'package:didacta_app/ui/theme.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const List<LanguageOption> tres = [
  LanguageOption(code: 'es', name: 'Castellano'),
  LanguageOption(code: 'va', name: 'Valencià'),
  LanguageOption(code: 'en', name: 'English'),
];

ExistingOutput output(
  String profile, {
  required String language,
  String? label,
  bool stale = false,
}) => ExistingOutput(
  profile: profile,
  label: label ?? profile,
  family: 'notes',
  language: language,
  pdf: '/tmp/$profile-$language.pdf',
  exists: true,
  stale: stale,
);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: didactaTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await settle(tester);
}

void main() {
  group('qué idiomas se ofrecen', () {
    test('los que declara la asignatura', () {
      final options = buildLanguagesOf(
        declared: const ['es', 'va'],
        known: tres,
        fallback: 'es',
      );
      expect(options.map((o) => o.code), ['es', 'va']);
      expect(options.first.name, 'Castellano');
    });

    test('sin declarar ninguno, los del espacio de trabajo', () {
      // Es lo que hacía todo antes de que una asignatura pudiera decir los
      // suyos, y lo que sigue valiendo para quien no los haya tocado.
      final options = buildLanguagesOf(
        declared: const [],
        known: tres,
        fallback: 'es',
      );
      expect(options.map((o) => o.code), ['es', 'va', 'en']);
    });

    test('un idioma sin nombre se ofrece por su código', () {
      // Con un índice viejo no hay nombres, y quedarse sin la opción sería
      // perder el idioma por no saber cómo se llama.
      final options = buildLanguagesOf(
        declared: const ['es', 'zz'],
        known: tres,
        fallback: 'es',
      );
      expect(options.map((o) => o.name), ['Castellano', 'zz']);
    });

    test('nunca sale vacío', () {
      // Un botón de compilar que no puede compilar nada, y sin decir por qué.
      final options = buildLanguagesOf(
        declared: const [],
        known: const [],
        fallback: 'va',
      );
      expect(options.single.code, 'va');
    });
  });

  group('el botón de compilar', () {
    testWidgets('pulsar compila el idioma en el que se está', (tester) async {
      final asked = <List<String>>[];
      await pump(
        tester,
        BuildButton(
          id: 'x',
          what: 'esto',
          options: tres,
          current: 'va',
          onBuild: asked.add,
        ),
      );

      await tester.tap(find.byKey(const Key('build-x')));
      await settle(tester);

      expect(asked, [
        ['va'],
      ]);
    });

    testWidgets('mantener pulsado ofrece el actual o todos', (tester) async {
      final asked = <List<String>>[];
      await pump(
        tester,
        BuildButton(
          id: 'x',
          what: 'esto',
          options: tres,
          current: 'va',
          onBuild: asked.add,
        ),
      );

      await tester.longPress(find.byKey(const Key('build-x')));
      await settle(tester);

      // Con su nombre: «compilar en va» no dice nada a quien no se sabe los
      // códigos, y quien los sabe tampoco tiene por qué leerlos.
      expect(find.text('Compilar en Valencià'), findsOneWidget);
      expect(find.text('Compilar en los 3 idiomas'), findsOneWidget);

      await tester.tap(find.byKey(const Key('build-all-languages')));
      await settle(tester);

      expect(asked, [
        ['es', 'va', 'en'],
      ]);
    });

    testWidgets('con un solo idioma no hay menú', (tester) async {
      // Un menú de una opción es un clic de más.
      final asked = <List<String>>[];
      await pump(
        tester,
        BuildButton(
          id: 'x',
          what: 'esto',
          options: const [LanguageOption(code: 'es', name: 'Castellano')],
          current: 'es',
          onBuild: asked.add,
        ),
      );

      await tester.longPress(find.byKey(const Key('build-x')));
      await settle(tester);

      expect(find.byKey(const Key('build-all-languages')), findsNothing);
    });

    testWidgets('si la asignatura no da el idioma actual, compila el suyo', (
      tester,
    ) async {
      // La barra de arriba es del espacio de trabajo y la asignatura puede no
      // darlo. Compilar «el actual» y sacar otra cosa sin avisar sería peor
      // que no ofrecerlo.
      final asked = <List<String>>[];
      await pump(
        tester,
        BuildButton(
          id: 'x',
          what: 'esto',
          options: const [
            LanguageOption(code: 'va', name: 'Valencià'),
            LanguageOption(code: 'en', name: 'English'),
          ],
          current: 'es',
          onBuild: asked.add,
        ),
      );

      await tester.tap(find.byKey(const Key('build-x')));
      await settle(tester);
      expect(asked, [
        ['va'],
      ]);

      await tester.longPress(find.byKey(const Key('build-x')));
      await settle(tester);
      expect(find.text('Compilar en Valencià'), findsOneWidget);
    });
  });

  group('el visor de PDF', () {
    Future<void> show(
      WidgetTester tester,
      List<ExistingOutput> outputs, {
      String language = 'es',
    }) => pump(
      tester,
      BuiltPdfsDialog(
        title: 'Tema 1',
        outputs: outputs,
        language: language,
        languages: tres,
      ),
    );

    testWidgets('la fila de idiomas va encima de la de versiones', (
      tester,
    ) async {
      await show(tester, [
        output('notes', language: 'es'),
        output('slides', language: 'es'),
        output('notes', language: 'va'),
      ]);

      final language = tester.getTopLeft(
        find.byKey(const Key('pdf-language-es')),
      );
      final version = tester.getTopLeft(find.byKey(const Key('pdf-tab-notes')));
      expect(language.dy, lessThan(version.dy));
    });

    testWidgets('entra en el idioma en el que se está trabajando', (
      tester,
    ) async {
      await show(tester, [
        output('notes', language: 'es'),
        output('notes', language: 'va'),
      ], language: 'va');

      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('pdf-language-va')),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('si de ese no hay nada, el primero que haya', (tester) async {
      // Respetar la preferencia hasta enseñar un visor vacío no ayuda a nadie.
      await show(tester, [output('notes', language: 'en')], language: 'va');

      expect(find.byKey(const Key('pdf-language-en')), findsNothing);
      expect(find.textContaining('English'), findsWidgets);
    });

    testWidgets('cada idioma lista solo sus versiones', (tester) async {
      // No tienen por qué ser las mismas: el valenciano puede tener los
      // apuntes y no las diapositivas.
      await show(tester, [
        output('notes', language: 'es', label: 'Apuntes'),
        output('slides', language: 'es', label: 'Diapositivas'),
        output('notes', language: 'va', label: 'Apuntes'),
      ]);

      expect(find.byKey(const Key('pdf-tab-slides')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-language-va')));
      await settle(tester);

      expect(find.byKey(const Key('pdf-tab-slides')), findsNothing);
    });

    testWidgets('con un idioma solo, no hay fila de idiomas', (tester) async {
      await show(tester, [
        output('notes', language: 'es'),
        output('slides', language: 'es'),
      ]);

      expect(find.byKey(const Key('pdf-language-es')), findsNothing);
      expect(find.byKey(const Key('pdf-tab-notes')), findsOneWidget);
    });

    testWidgets('el orden de los idiomas es el de la asignatura', (
      tester,
    ) async {
      await show(tester, [
        output('notes', language: 'en'),
        output('notes', language: 'es'),
      ]);

      expect(
        tester.getTopLeft(find.byKey(const Key('pdf-language-es'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('pdf-language-en'))).dx,
        ),
      );
    });
  });
}
