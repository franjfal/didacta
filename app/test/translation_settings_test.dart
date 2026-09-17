/// La pantalla donde se ponen las claves de traducción.
///
/// Lo que se fija aquí, además de que funcione: que **la clave no vuelva a la
/// pantalla** una vez guardada. Un campo que la devuelve entera es una clave
/// en una captura de pantalla, y las capturas se pegan en correos.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/translation_settings.dart';

const String secreta = 'AIzaSyD-clave-larguisima-de-verdad-1234';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pump(WidgetTester tester, TranslationSecrets secrets) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: didactaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TranslationSection(secrets: secrets),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('hay un sitio para cada proveedor', (tester) async {
    await pump(tester, MemoryTranslationSecrets());
    expect(find.byKey(const Key('translation-google')), findsOneWidget);
    expect(find.byKey(const Key('translation-azure')), findsOneWidget);
    expect(find.text('Google Cloud Translation'), findsOneWidget);
    expect(find.text('Azure AI Translator'), findsOneWidget);
  });

  testWidgets('guardar la deja en el llavero', (tester) async {
    final secrets = MemoryTranslationSecrets();
    await pump(tester, secrets);

    await tester.enterText(
      find.byKey(const Key('translation-google-key')),
      secreta,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('translation-google-save')));
    await settle(tester);

    expect(secrets.stored[TranslationProvider.google]!.key, secreta);
  });

  testWidgets('y no vuelve a enseñarse', (tester) async {
    // Se dice que hay una y se enseñan sus últimos cuatro caracteres, lo
    // justo para reconocer cuál de las tuyas pusiste.
    final secrets = MemoryTranslationSecrets()
      ..stored[TranslationProvider.google] = const Credentials(key: secreta);
    await pump(tester, secrets);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('translation-google-key')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.textContaining('1234'), findsOneWidget);
    expect(find.textContaining(secreta), findsNothing);
  });

  testWidgets('el campo de la clave va tapado', (tester) async {
    await pump(tester, MemoryTranslationSecrets());
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('translation-google-key')))
          .obscureText,
      isTrue,
    );
  });

  testWidgets('la región vuelve, que no es un secreto', (tester) async {
    // Tener que reescribir `westeurope` cada vez que se cambia la clave es un
    // paso de más que además se equivoca.
    final secrets = MemoryTranslationSecrets()
      ..stored[TranslationProvider.azure] = const Credentials(
        key: secreta,
        region: 'westeurope',
      );
    await pump(tester, secrets);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('translation-azure-region')))
          .controller!
          .text,
      'westeurope',
    );
  });

  testWidgets('Azure pide región y Google no', (tester) async {
    await pump(tester, MemoryTranslationSecrets());
    expect(find.byKey(const Key('translation-azure-region')), findsOneWidget);
    expect(find.byKey(const Key('translation-google-region')), findsNothing);
  });

  testWidgets('sin clave no se puede guardar ni probar', (tester) async {
    await pump(tester, MemoryTranslationSecrets());
    for (final what in ['save', 'test']) {
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(Key('translation-google-$what')),
            )
            .onPressed,
        isNull,
        reason: what,
      );
    }
  });

  testWidgets('quitar la borra del llavero', (tester) async {
    final secrets = MemoryTranslationSecrets()
      ..stored[TranslationProvider.google] = const Credentials(key: secreta);
    await pump(tester, secrets);

    await tester.tap(find.byKey(const Key('translation-google-clear')));
    await settle(tester);

    expect(secrets.stored, isEmpty);
  });

  testWidgets('sin quitar no sale el botón de quitar', (tester) async {
    await pump(tester, MemoryTranslationSecrets());
    expect(find.byKey(const Key('translation-google-clear')), findsNothing);
  });

  testWidgets('donde no se puede guardar, se dice y no se deja', (
    tester,
  ) async {
    // En un navegador «almacenamiento seguro» es almacenamiento del
    // navegador. La aplicación no puede ofrecerse a guardar lo que no puede
    // proteger.
    await pump(tester, MemoryTranslationSecrets(safe: false));

    expect(find.textContaining('de forma segura'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('translation-google-key')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('dice que no salen del llavero, que es lo que hay que saber', (
    tester,
  ) async {
    await pump(tester, MemoryTranslationSecrets());
    expect(find.textContaining('llavero del sistema'), findsOneWidget);
    expect(
      find.textContaining('No entran en ningún repositorio'),
      findsOneWidget,
    );
  });
}
