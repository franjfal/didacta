/// La interfaz en castellano, valenciano e inglés: `tr()`, los catálogos y el
/// ajuste de Apariencia.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/l10n/catalog_en.dart';
import 'package:didacta_app/l10n/catalog_va.dart';
import 'package:didacta_app/l10n/tr.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/appearance.dart';

import 'fixture.dart';

Set<String> marks(String text) => {
  for (final match in RegExp(r'\{\d+\}').allMatches(text)) match.group(0)!,
};

void main() {
  tearDown(() => useUiLanguage(UiLanguage.es));

  group('tr', () {
    test('en castellano, el texto tal cual, con sus marcadores', () {
      expect(tr('Guardado en {0}', ['GitHub']), 'Guardado en GitHub');
    });

    test('lo que no está traducido sale en castellano, no en blanco', () {
      useUiLanguage(UiLanguage.en);
      expect(
        tr('Una frase que nadie ha traducido'),
        'Una frase que nadie ha traducido',
      );
    });

    test('en inglés y en valenciano, lo del catálogo', () {
      final key = enStrings.keys.firstWhere((key) => marks(key).isEmpty);
      useUiLanguage(UiLanguage.en);
      expect(tr(key), enStrings[key]);
      useUiLanguage(UiLanguage.va);
      expect(tr(key), vaStrings[key] ?? key);
    });

    test('el del sistema: catalán y valenciano, valenciano; el resto, '
        'castellano', () {
      expect(uiLanguageFor(const Locale('ca', 'ES')), UiLanguage.va);
      expect(uiLanguageFor(const Locale('en', 'GB')), UiLanguage.en);
      expect(uiLanguageFor(const Locale('fr')), UiLanguage.es);
      expect(UiLanguage.va.materialLocale, const Locale('ca'));
    });
  });

  test('el nombre de una salida, en el idioma de la interfaz', () {
    final profile = OutputProfile.fromJson({
      'id': 'notes-teacher',
      'documentClass': 'article',
      'label': 'Apuntes (profesor)',
      'labels': {'va': 'Apunts (professor)', 'en': 'Notes (teacher)'},
    });
    expect(profile.name, 'Apuntes (profesor)');
    useUiLanguage(UiLanguage.en);
    expect(profile.name, 'Notes (teacher)');
    // Un índice de antes no los trae: va el castellano.
    expect(
      OutputProfile.fromJson({'id': 'notes', 'label': 'Apuntes'}).name,
      'Apuntes',
    );
  });

  group('los catálogos', () {
    test('cada traducción, con los mismos marcadores que su clave', () {
      for (final table in [vaStrings, enStrings]) {
        for (final entry in table.entries) {
          expect(marks(entry.value), marks(entry.key), reason: entry.key);
        }
      }
    });

    test('los dos, con las mismas claves', () {
      expect(vaStrings.keys.toSet(), enStrings.keys.toSet());
    });

    test('tienen de verdad lo de la interfaz', () {
      expect(vaStrings.length, greaterThan(2000));
      expect(enStrings['Biblioteca'], 'Library');
    });
  });

  testWidgets('cambiar el idioma repinta lo que ya está en pantalla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final preferences = MemoryPreferences();
    final appearance = Appearance(preferences: preferences);
    await appearance.load();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      preferencesOverride: preferences,
    );
    await tester.pumpWidget(
      DidactaApp(
        session: session,
        updates: offlineUpdates(),
        appearance: appearance,
      ),
    );
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Biblioteca'), findsWidgets);

    await appearance.setUiLanguage('en');
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Biblioteca'), findsNothing);
    expect(preferences.language, 'en');
  });
}
