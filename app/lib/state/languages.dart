/// Los idiomas del material: cuál se está mirando y cuáles ofrece cada
/// selector.
///
/// Era una parte de la sesión. Aparte porque es una sola pregunta --qué
/// idiomas se enseñan aquí-- con una docena de variantes, y de la sesión solo
/// necesita el catálogo y lo que cada cual ha encendido en Ajustes. Cambiar el
/// idioma que se mira cambia lo que enseñan todas las pantallas, así que avisa
/// por la sesión, que lo sigue ofreciendo con los mismos nombres.
library;

import 'package:flutter/foundation.dart';

import '../model/catalogue.dart';
import 'session.dart';

class LanguageChoices {
  LanguageChoices(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a quien mira: la sesión, que avisa a las pantallas.
  final VoidCallback onChanged;

  /// El idioma del material que se está mirando.
  String _language = 'es';
  String get language => _language;

  set language(String code) {
    if (_language == code) return;
    _language = code;
    onChanged();
  }

  /// El de salida de un catálogo, sin avisar: lo pone el arranque, que ya
  /// avisa al terminar.
  void resetTo(Catalogue catalogue) => _language = catalogue.defaultLanguage;

  bool _enabled(String code) =>
      session.libraryPrefs.synced.isLanguageEnabled(code);

  /// Si un idioma está encendido en esta aplicación. Ver
  /// `SyncedPrefs.enabledLanguages` para qué es y qué no es.
  bool isEnabled(String code) => _enabled(code);

  /// Enciende o apaga un idioma, y lo apunta donde toque.
  ///
  /// Si se apaga el que se estaba mirando, se pasa al primero que quede: la
  /// alternativa es una barra que enseña un idioma que ya no ofrece y una
  /// biblioteca con la pestaña marcada fuera de la fila.
  Future<void> setEnabled(String code, bool on) => session.libraryPrefs.change(
    (prefs) => prefs.withLanguageEnabled(
      code,
      on,
      all: session.catalogueOrNull?.languages ?? const [],
    ),
    then: () {
      final offered = choices;
      if (offered.isNotEmpty &&
          offered.every((option) => option.code != _language)) {
        _language = offered.first.code;
      }
    },
  );

  /// Los idiomas que ofrece cualquier selector: los del material ∩ los
  /// encendidos, con su nombre y en el orden del registro.
  ///
  /// Nunca vacío. Si el filtro se quedara sin nada --se apagó un repositorio
  /// y con él el único idioma encendido-- valen los del material: un selector
  /// sin ninguna opción no es un filtro, es una pantalla rota.
  List<LanguageOption> get choices {
    final catalogue = session.catalogueOrNull;
    if (catalogue == null) return const [];
    return named([
      for (final code in catalogue.languages)
        if (_enabled(code)) code,
    ], or: catalogue.languages);
  }

  /// Los idiomas que se ofrecen para una asignatura.
  ///
  /// Los suyos --ya cruzados con lo que mantienen sus repositorios-- y luego
  /// el filtro. Lo que la asignatura declara y está apagado **no se pierde**:
  /// las pantallas que escriben lo añaden con [toEdit].
  List<LanguageOption> choicesFor(Course course) {
    final catalogue = session.catalogueOrNull;
    if (catalogue == null) return const [];
    final hers = catalogue.languagesForCourse(course);
    return named([
      for (final code in hers)
        if (_enabled(code)) code,
    ], or: hers);
  }

  /// Los idiomas de una asignatura por su id, o los del material cuando no se
  /// sabe de cuál se habla.
  ///
  /// Lo que usa una pantalla que ya está dentro de una asignatura --una
  /// composición, el fuente de un documento-- y solo tiene el id a mano.
  List<String> codesIn(String? courseId) {
    final course = courseId == null ? null : session.courseById(courseId);
    final options = course == null ? choices : choicesFor(course);
    return [for (final option in options) option.code];
  }

  /// Lo que ofrece una pantalla que **escribe** un idioma en un fichero.
  ///
  /// Lo que se puede elegir, más lo que ese fichero ya dice. Apagar un idioma
  /// en Ajustes es dejar de mirarlo, no borrarlo del material: sin esta unión,
  /// abrir la ficha de una asignatura que se da en inglés con el inglés
  /// apagado y darle a guardar se lo quitaría, sin que nadie lo pidiera y sin
  /// que se viera.
  List<LanguageOption> toEdit({
    required List<String> allowed,
    required List<String> declared,
  }) => named([
    for (final code in allowed)
      if (_enabled(code) || declared.contains(code)) code,
  ], or: allowed);

  /// Los códigos con su nombre, en el orden del registro, o [or] si no queda
  /// ninguno.
  List<LanguageOption> named(List<String> codes, {List<String> or = const []}) {
    final wanted = codes.isEmpty ? or : codes;
    final known =
        session.catalogueOrNull?.languageOptions ?? const <LanguageOption>[];
    // El orden del registro y no el de la lista: así la barra de arriba, el
    // menú de compilar y la ficha de la asignatura enseñan los mismos idiomas
    // en el mismo sitio, que es lo que permite ir a ciegas.
    final ordered = [
      for (final option in known)
        if (wanted.contains(option.code)) option,
    ];
    final rest = [
      for (final code in wanted)
        if (!known.any((option) => option.code == code))
          LanguageOption(code: code, name: code),
    ];
    return [...ordered, ...rest];
  }
}
