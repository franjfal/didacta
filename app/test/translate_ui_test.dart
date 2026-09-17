/// Las cuatro formas de mandar algo a traducir.
///
/// El mismo diálogo para una lección y para doscientas, porque las cuatro
/// preguntan lo mismo: a qué idiomas y con qué proveedor.
///
/// Lo primero que se fija aquí es el fallo que lo empezó todo: **los idiomas
/// no se heredan de la barra de arriba**. La interfaz se mira en castellano,
/// así que el botón ofrecía traducir de castellano a castellano. Lo que hace
/// falta saber no es qué idioma estás mirando, sino cuáles le faltan a esto.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/translate_tab.dart';
import 'package:didacta_app/ui/translate_unit.dart';
import 'package:didacta_app/ui/translations_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Una unidad con los idiomas que se le digan.
Map<String, dynamic> unitJson(
  String path, {
  String reference = 'es',
  Map<String, String> statuses = const {'es': 'source'},
}) => {
  'id': path.replaceAll('/', '.'),
  'path': path,
  'area': 'content',
  'block': 'theory',
  'kind': 'theory',
  'title': {reference: 'La de ${path.split('/').last}'},
  'reference': reference,
  'languages': {
    for (final entry in statuses.entries)
      entry.key: {'status': entry.value, 'exists': entry.value != 'missing'},
  },
};

Future<FakeSession> sessionWith(
  List<Map<String, dynamic>> units, {
  bool withKey = true,
}) async {
  final catalogue = catalogueWith(units);
  final secrets = MemoryTranslationSecrets();
  if (withKey) {
    await secrets.write(
      TranslationProvider.google,
      const Credentials(key: 'AIza-una-clave'),
    );
  }
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    translationSecretsOverride: secrets,
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return session;
}

Future<void> showDialogFor(
  WidgetTester tester,
  FakeSession session,
  List<Unit> units, {
  List<String>? only,
}) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: TranslateDialog(session: session, units: units, only: only),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  group('el selector de trabajo', selectorTests);

  group('qué idiomas se ofrecen', () {
    testWidgets('los que faltan, no el que se está mirando', (tester) async {
      // El fallo original: con la interfaz en castellano, el botón ofrecía
      // traducir de castellano a castellano.
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
      ]);
      expect(session.language, 'es');

      await showDialogFor(tester, session, session.catalogue.units);

      expect(find.byKey(const Key('translate-language-es')), findsNothing);
      expect(find.byKey(const Key('translate-language-va')), findsOneWidget);
      expect(find.byKey(const Key('translate-language-en')), findsOneWidget);
    });

    testWidgets('con la cuenta de a cuántas les falta', (tester) async {
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
        unitJson('content/a/dos', statuses: {'es': 'source', 'va': 'reviewed'}),
      ]);

      await showDialogFor(tester, session, session.catalogue.units);

      // A las dos les falta inglés; el valenciano solo le falta a una.
      expect(find.textContaining('English · 2'), findsOneWidget);
      expect(find.textContaining('Valencià · 1'), findsOneWidget);
    });

    testWidgets('un idioma que ya tienen todas no se ofrece', (tester) async {
      // Un clic que no hace nada.
      final session = await sessionWith([
        unitJson(
          'content/a/uno',
          statuses: {'es': 'source', 'va': 'reviewed', 'en': 'reviewed'},
        ),
      ]);

      await showDialogFor(tester, session, session.catalogue.units);
      expect(find.textContaining('No falta ningún idioma'), findsOneWidget);
    });

    testWidgets('se pueden marcar y desmarcar todos', (tester) async {
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
      ]);
      await showDialogFor(tester, session, session.catalogue.units);

      await tester.tap(find.byKey(const Key('translate-toggle-all')));
      await settle(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('translate-go')))
            .onPressed,
        isNull,
        reason: 'sin idiomas no hay nada que traducir',
      );
    });

    testWidgets('viniendo de una pestaña, solo ese idioma', (tester) async {
      // «Traducir esta lección al valenciano» ya sabe cuál: preguntarlo otra
      // vez sería hacer repetir lo que se acaba de decir.
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
      ]);

      await showDialogFor(
        tester,
        session,
        session.catalogue.units,
        only: ['va'],
      );

      expect(find.byKey(const Key('translate-language-va')), findsOneWidget);
      expect(find.byKey(const Key('translate-language-en')), findsNothing);
    });
  });

  group('cuántos ficheros salen', () {
    testWidgets('una lección por idioma que le falte', (tester) async {
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
        unitJson('content/a/dos', statuses: {'es': 'source'}),
      ]);

      await showDialogFor(tester, session, session.catalogue.units);

      // Dos lecciones × dos idiomas que faltan.
      expect(find.text('Traducir 4'), findsOneWidget);
    });

    testWidgets('sin credencial se dice dónde se pone', (tester) async {
      final session = await sessionWith([
        unitJson('content/a/uno'),
      ], withKey: false);

      await showDialogFor(tester, session, session.catalogue.units);

      expect(find.textContaining('Ajustes'), findsOneWidget);
      // El botón está, apagado: quitarlo dejaría la ventana sin decir qué se
      // esperaba que pasara al pulsarlo.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('translate-go')))
            .onPressed,
        isNull,
      );
    });
  });

  group('los huecos de un tema', () {
    Document documentWith(List<String> refs) => Document(
      id: 'tema-1',
      kind: 'theory',
      language: 'es',
      titles: const {'es': 'Tema 1'},
      profiles: const [],
      unitRefs: refs,
    );

    test('se cuentan sobre los idiomas de la asignatura', () async {
      // Un tema que solo se da en castellano y valenciano no tiene un hueco
      // en inglés: tiene un idioma que no se usa.
      final catalogue = catalogueWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
        unitJson('content/a/dos', statuses: {'es': 'source', 'va': 'draft'}),
      ]);

      final gaps = gapsIn(
        document: documentWith(['a/uno', 'a/dos']),
        catalogue: catalogue,
        languages: const ['es', 'va'],
      );

      // Las dos: a una le falta el valenciano y la otra lo tiene en borrador,
      // que es una traducción de máquina que no ha leído nadie. Lo que no
      // sale es el inglés, porque esta asignatura no se da en inglés.
      expect(gaps.length, 2);
      expect(gaps.first.languages, ['va']);
      for (final gap in gaps) {
        expect(gap.languages, ['va']);
      }
    });

    test('un borrador cuenta como pendiente', () async {
      // Es una traducción de máquina que no ha leído nadie.
      final catalogue = catalogueWith([
        unitJson('content/a/uno', statuses: {'es': 'source', 'va': 'draft'}),
      ]);
      final gaps = gapsIn(
        document: documentWith(['a/uno']),
        catalogue: catalogue,
        languages: const ['es', 'va'],
      );
      expect(gaps.single.languages, ['va']);
    });

    test('una lección repetida se cuenta una vez', () async {
      // Un tema puede llamar dos veces a la misma, y traducirla dos veces
      // sería pagarla dos veces.
      final catalogue = catalogueWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
      ]);
      final gaps = gapsIn(
        document: documentWith(['a/uno', 'a/uno']),
        catalogue: catalogue,
        languages: const ['es', 'va'],
      );
      expect(gaps.length, 1);
    });

    test('sin huecos, la lista sale vacía y la pestaña no aparece', () async {
      final catalogue = catalogueWith([
        unitJson('content/a/uno', statuses: {'es': 'source', 'va': 'reviewed'}),
      ]);
      final gaps = gapsIn(
        document: documentWith(['a/uno']),
        catalogue: catalogue,
        languages: const ['es', 'va'],
      );
      expect(gaps, isEmpty);
    });

    testWidgets('la pestaña marca todo lo escribible de entrada', (
      tester,
    ) async {
      // Se entra a traducir lo que falta, no a elegir cuál de los tres.
      final session = await sessionWith([
        unitJson('content/a/uno', statuses: {'es': 'source'}),
        unitJson('content/a/dos', statuses: {'es': 'source'}),
      ]);
      final gaps = gapsIn(
        document: documentWith(['a/uno', 'a/dos']),
        catalogue: session.catalogue,
        languages: const ['es', 'va'],
      );

      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: TranslateTab(session: session, gaps: gaps, language: 'es'),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Traducir 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gaps-none')));
      await settle(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gaps-translate')))
            .onPressed,
        isNull,
      );
    });
  });
}

/// El selector de trabajo de la cabecera.
///
/// Con la misma forma que el de idioma, al lado: son la misma decisión
/// partida en dos --qué estoy despachando-- y enseñar uno como botones y el
/// otro como texto hacía que el segundo no pareciera pulsable.
void selectorTests() {
  testWidgets('los dos selectores tienen la misma forma', (tester) async {
    final session = await sessionWith([
      unitJson('content/a/uno', statuses: {'es': 'source'}),
      unitJson('content/a/dos', statuses: {'es': 'source', 'va': 'draft'}),
    ]);
    session.language = 'va';

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: TranslationsPage()),
        ),
      ),
    );
    await settle(tester);

    // Dos `SegmentedButton`, no uno y una línea de texto.
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byKey(const Key('work-picker')), findsOneWidget);
    expect(find.text('Idioma:'), findsOneWidget);
    expect(find.text('Trabajo:'), findsOneWidget);
  });

  testWidgets('cada trabajo lleva su cuenta dentro', (tester) async {
    final session = await sessionWith([
      unitJson('content/a/uno', statuses: {'es': 'source'}),
      unitJson('content/a/dos', statuses: {'es': 'source', 'va': 'draft'}),
    ]);
    session.language = 'va';

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: TranslationsPage()),
        ),
      ),
    );
    await settle(tester);

    // Una sin traducir y una en borrador.
    expect(find.text('Sin traducir 1'), findsOneWidget);
    expect(find.text('Sin revisar 1'), findsOneWidget);
  });

  testWidgets('los tres salen siempre, con cero los que están vacíos', (
    tester,
  ) async {
    // Antes solo salían los que tenían algo, y entonces no había forma de
    // saber si lo que estabas viendo era lo que falta por traducir o lo que
    // falta por revisar. Un selector que se esconde deja de decir dónde
    // estás, que es la mitad de su trabajo.
    final session = await sessionWith([
      unitJson('content/a/uno', statuses: {'es': 'source'}),
    ]);
    session.language = 'va';

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: TranslationsPage()),
        ),
      ),
    );
    await settle(tester);

    expect(find.byKey(const Key('work-picker')), findsOneWidget);
    expect(find.text('Sin traducir 1'), findsOneWidget);
    expect(find.text('Sin revisar 0'), findsOneWidget);
    expect(find.text('Desactualizadas 0'), findsOneWidget);
  });

  testWidgets('los vacíos se pueden elegir igual, y se ven igual', (
    tester,
  ) async {
    // Apagarlos los pintaba con el borde de «no disponible» --un gris casi
    // blanco-- y el control dejaba de parecerse al de idiomas que tiene al
    // lado. Y entrar en «Sin traducir» y que conteste «nada pendiente» es
    // una respuesta, no un callejón.
    final session = await sessionWith([
      unitJson('content/a/uno', statuses: {'es': 'source'}),
    ]);
    session.language = 'va';

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: TranslationsPage()),
        ),
      ),
    );
    await settle(tester);

    final picker = tester.widget<SegmentedButton<TranslationStatus>>(
      find.byKey(const Key('work-picker')),
    );
    for (final segment in picker.segments) {
      expect(segment.enabled, isTrue, reason: '${segment.value}');
    }
    // Y se entra en el que tiene algo, no en el primero de la lista.
    expect(picker.selected, {TranslationStatus.missing});

    // Pulsar uno vacío contesta, no deja la pantalla a medias.
    await tester.tap(find.text('Sin revisar 0'));
    await settle(tester);
    expect(find.textContaining('Nada pendiente'), findsOneWidget);
  });
}
