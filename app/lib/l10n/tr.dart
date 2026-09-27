/// La interfaz en castellano, valenciano o inglés.
///
/// **La clave es el texto en castellano**: `tr('Guardar')` devuelve «Guardar»,
/// «Desa» o «Save» según el idioma de la interfaz. Así el código se sigue
/// leyendo en castellano, que es como está escrito y pensado, y lo que todavía
/// no esté traducido sale en castellano en lugar de salir como un hueco o como
/// un identificador.
///
/// Lo que cambia en cada mensaje va con marcadores numerados:
///
///     tr('Guardado en {0}', [repo])
///
/// y la traducción los pone donde toque en su idioma: «Desat a {0}», «Saved to
/// {0}». Los plurales van como en castellano, con dos mensajes y la condición
/// en el código: los tres idiomas pluralizan igual (uno, y los demás).
///
/// Las traducciones están en `l10n/va.json` y `l10n/en.json`, de donde
/// `tool/l10n.py` escribe `catalog_va.dart` y `catalog_en.dart`. Qué falta por
/// traducir lo dice `test/l10n_test.dart`.
///
/// No es el idioma del material --el que se mira en la biblioteca--: una
/// profesora que trabaja la interfaz en valenciano prepara igual los apuntes
/// en castellano y en inglés.
library;

import 'dart:ui' show Locale;

import 'catalog_en.dart';
import 'catalog_va.dart';

/// Los idiomas de la interfaz, con su nombre en su propio idioma: es como
/// lo busca quien no entiende el que hay puesto.
enum UiLanguage {
  es('Castellano'),
  va('Valencià'),
  en('English');

  const UiLanguage(this.label);

  /// Cómo se llama en su idioma.
  final String label;

  static UiLanguage? parse(String? code) {
    for (final language in values) {
      if (language.name == code) return language;
    }
    return null;
  }

  /// `es`, `va` o `en`.
  String get code => name;

  /// El de Material --cortar, pegar, el calendario--: el valenciano va con el
  /// catalán, que es el que trae Flutter.
  Locale get materialLocale => Locale(this == va ? 'ca' : code);
}

UiLanguage _current = UiLanguage.es;

/// El idioma de la interfaz ahora mismo.
UiLanguage get uiLanguage => _current;

/// Cambia el idioma de la interfaz. Quien lo llama repinta la aplicación: lo
/// que ya está en pantalla no se entera solo.
void useUiLanguage(UiLanguage language) => _current = language;

/// El que corresponde al del sistema: catalán y valenciano, valenciano;
/// inglés, inglés; todo lo demás, castellano, que es el original.
UiLanguage uiLanguageFor(Locale system) => switch (system.languageCode) {
  'ca' || 'va' => UiLanguage.va,
  'en' => UiLanguage.en,
  _ => UiLanguage.es,
};

/// [source], en el idioma de la interfaz, con [args] en sus marcadores.
String tr(String source, [List<Object?> args = const []]) {
  final table = switch (_current) {
    UiLanguage.va => vaStrings,
    UiLanguage.en => enStrings,
    UiLanguage.es => null,
  };
  var text = table?[source] ?? source;
  for (var index = 0; index < args.length; index += 1) {
    text = text.replaceAll('{$index}', '${args[index]}');
  }
  return text;
}
