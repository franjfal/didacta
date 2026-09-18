/// Las preferencias que viajan de un ordenador a otro.
///
/// El problema que resuelve, y por qué no es el mismo que el de las demás
/// preferencias: plegar el Tema 3 porque este año no se da es una decisión
/// sobre **el material**, no sobre esta máquina. Quien la toma en el despacho
/// espera encontrarla en casa. La ruta del clon o dónde está TeX son justo lo
/// contrario: son de la máquina, y sincronizarlas rompería la de al lado.
///
/// Dónde viven
/// -----------
///
/// En un repositorio de contenido, el que la persona elija, como
/// `.didacta/prefs/<login>.json`. Tres cosas que eso resuelve de golpe:
///
/// **Se sincroniza con lo que ya hay.** Un repositorio de contenido ya se
/// clona, se trae y se envía, con sesión de GitHub y commits firmados. Las
/// preferencias viajan por ese camino y no por uno nuevo.
///
/// **Dos personas no se pisan.** El nombre del fichero es el login de GitHub
/// de quien entró, así que un departamento entero puede compartir repositorio
/// y cada uno tiene el suyo. Nadie lee ni escribe el de otro.
///
/// **No hay un repositorio «de preferencias» impuesto.** Cada uno tiene los
/// suyos y no coinciden, así que se elige. Sin elegir ninguno, esto sigue
/// funcionando en local: lo que no se puede es encontrarlo en otro ordenador.
///
/// Qué NO va aquí: nada que identifique a una máquina --rutas, la carpeta de
/// clones, dónde está TeX-- y nada secreto. El token sigue en el llavero.
library;

import 'dart:convert';

/// El formato del fichero. Si algún día cambia, esto es lo que dirá desde
/// cuándo: un fichero de una versión que no se entiende se ignora entero en
/// lugar de leerse a medias.
const int syncedPrefsVersion = 1;

class SyncedPrefs {
  const SyncedPrefs({
    this.collapsedThemes = const {},
    this.hiddenRepos = const {},
    this.favouriteCourses = const {},
    this.favouriteYears = const {},
    this.enabledLanguages = const {},
  });

  /// Lee lo que haya, y ante la duda devuelve vacío.
  ///
  /// Nunca lanza. Unas preferencias que no se entienden son unas preferencias
  /// que no se aplican, y eso es un panel desplegado de más: hacer que la
  /// aplicación no abra por un fichero de ajustes sería desproporcionado.
  factory SyncedPrefs.fromJson(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const SyncedPrefs();
      if ((data['version'] as num?)?.toInt() != syncedPrefsVersion) {
        return const SyncedPrefs();
      }
      final collapsed = <String, Set<String>>{};
      final themes = data['collapsedThemes'];
      if (themes is Map) {
        for (final entry in themes.entries) {
          final value = entry.value;
          if (value is! List) continue;
          collapsed[entry.key.toString()] = {
            for (final id in value) id.toString(),
          };
        }
      }
      final hidden = <String>{};
      final repos = data['hiddenRepos'];
      if (repos is List) {
        for (final repo in repos) {
          hidden.add(repo.toString());
        }
      }
      return SyncedPrefs(
        collapsedThemes: collapsed,
        hiddenRepos: hidden,
        favouriteCourses: _names(data['favouriteCourses']),
        favouriteYears: _names(data['favouriteYears']),
        enabledLanguages: _names(data['enabledLanguages']),
      );
    } catch (_) {
      return const SyncedPrefs();
    }
  }

  /// Los temas plegados, por curso. La clave es `asignatura@año`, que es como
  /// se nombra un curso en todo lo demás.
  final Map<String, Set<String>> collapsedThemes;

  /// Las asignaturas marcadas. Se ponen arriba, saltándose el orden.
  ///
  /// Arriba y no en una lista aparte: quien da tres asignaturas de veinte no
  /// quiere dos sitios donde mirar, quiere las tres primero. El resto sigue
  /// donde estaba y en el mismo orden.
  final Set<String> favouriteCourses;

  /// Los cursos marcados, como `asignatura@año`.
  ///
  /// Aparte de las asignaturas y no derivado de ellas: marcar Análisis
  /// Matemático I no dice nada de cuál de sus seis cursos se está dando, que
  /// es justo lo que hay que tener a mano.
  final Set<String> favouriteYears;

  /// Los idiomas con los que se quiere trabajar.
  ///
  /// **Vacío es «todos»**, y no «ninguno»: es lo que hace que esto se pueda
  /// añadir sin cambiar nada para quien no lo toque, y lo que impide que un
  /// fichero a medio escribir deje la aplicación sin ningún idioma.
  ///
  /// Es un **filtro**, nunca una autoridad sobre los ficheros. A qué idiomas
  /// se traduce lo dicen `didacta.yaml` y `course.yaml`, que son del material
  /// y los ve todo el mundo; esto es de quien mira, y viaja con el resto de
  /// preferencias. Apagar el inglés aquí no quita el inglés de ninguna
  /// asignatura: deja de ofrecerse donde hay que elegir uno, y ya está. Por
  /// eso las pantallas que escriben enseñan además lo que el fichero que
  /// tienen delante ya declara, esté apagado o no --si no, guardar la ficha
  /// de una asignatura le quitaría un idioma que nadie pidió quitar--.
  ///
  /// Aquí y no en las preferencias de la máquina por lo mismo que los temas
  /// plegados: quien trabaja en castellano y valenciano lo hace en los dos
  /// ordenadores.
  final Set<String> enabledLanguages;

  /// Si un idioma se ofrece. Sin nada elegido, todos.
  bool isLanguageEnabled(String code) =>
      enabledLanguages.isEmpty || enabledLanguages.contains(code);

  /// Enciende o apaga un idioma.
  ///
  /// Apagar el último deja el conjunto vacío, que es «todos»: no hay forma de
  /// quedarse sin ninguno, porque una aplicación sin ningún idioma no puede
  /// enseñar una sola línea de material.
  SyncedPrefs withLanguageEnabled(
    String code,
    bool on, {
    required Iterable<String> all,
  }) {
    final next = enabledLanguages.isEmpty ? {...all} : {...enabledLanguages};
    if (on) {
      next.add(code);
    } else {
      next.remove(code);
    }
    // Todos marcados es lo mismo que no haber elegido, y se guarda igual:
    // así el fichero no crece con una lista que hay que mantener cada vez que
    // un repositorio añade un idioma.
    if (next.isEmpty || all.every(next.contains)) {
      return _copy(enabledLanguages: const {});
    }
    return _copy(enabledLanguages: next);
  }

  /// Los repositorios apagados en la interfaz.
  ///
  /// Apagar no es quitar: el repositorio sigue abierto, sigue clonándose y
  /// sigue guardando. Lo que se decide aquí es qué se está mirando ahora, y
  /// por eso viaja de un ordenador a otro como el resto: quien deja de mirar
  /// el repositorio del departamento no quiere volver a apagarlo mañana.
  final Set<String> hiddenRepos;

  static String key(String course, String year) => '$course@$year';

  Set<String> collapsedIn(String course, String year) =>
      collapsedThemes[key(course, year)] ?? const {};

  SyncedPrefs withRepoHidden(String repo, bool hidden) =>
      _copy(hiddenRepos: _toggled(hiddenRepos, repo, hidden));

  SyncedPrefs withFavouriteCourse(String course, bool favourite) =>
      _copy(favouriteCourses: _toggled(favouriteCourses, course, favourite));

  SyncedPrefs withFavouriteYear(String course, String year, bool favourite) =>
      _copy(
        favouriteYears: _toggled(favouriteYears, key(course, year), favourite),
      );

  bool isFavouriteCourse(String course) => favouriteCourses.contains(course);

  bool isFavouriteYear(String course, String year) =>
      favouriteYears.contains(key(course, year));

  static Set<String> _toggled(Set<String> from, String name, bool on) {
    final next = {...from};
    if (on) {
      next.add(name);
    } else {
      next.remove(name);
    }
    return next;
  }

  static Set<String> _names(Object? raw) => raw is List
      ? {for (final name in raw) name.toString()}
      : const <String>{};

  SyncedPrefs _copy({
    Map<String, Set<String>>? collapsedThemes,
    Set<String>? hiddenRepos,
    Set<String>? favouriteCourses,
    Set<String>? favouriteYears,
    Set<String>? enabledLanguages,
  }) => SyncedPrefs(
    collapsedThemes: collapsedThemes ?? this.collapsedThemes,
    hiddenRepos: hiddenRepos ?? this.hiddenRepos,
    favouriteCourses: favouriteCourses ?? this.favouriteCourses,
    favouriteYears: favouriteYears ?? this.favouriteYears,
    enabledLanguages: enabledLanguages ?? this.enabledLanguages,
  );

  SyncedPrefs withThemeCollapsed({
    required String course,
    required String year,
    required String theme,
    required bool collapsed,
  }) {
    final where = key(course, year);
    final next = {
      for (final entry in collapsedThemes.entries) entry.key: {...entry.value},
    };
    final themes = next.putIfAbsent(where, () => <String>{});
    if (collapsed) {
      themes.add(theme);
    } else {
      themes.remove(theme);
    }
    if (themes.isEmpty) next.remove(where);
    return _copy(collapsedThemes: next);
  }

  /// Escrito ordenado y con saltos de línea, a propósito: esto acaba en un
  /// commit, y un fichero cuyas claves salen en un orden distinto cada vez da
  /// un diff ilegible y un commit por nada.
  String toJson() {
    final courses = collapsedThemes.keys.toList()..sort();
    return '${const JsonEncoder.withIndent('  ').convert({
      'version': syncedPrefsVersion,
      'collapsedThemes': {for (final course in courses)
        if (collapsedThemes[course]!.isNotEmpty) course: (collapsedThemes[course]!.toList()..sort())},
      'hiddenRepos': hiddenRepos.toList()..sort(),
      'favouriteCourses': favouriteCourses.toList()..sort(),
      'favouriteYears': favouriteYears.toList()..sort(),
      'enabledLanguages': enabledLanguages.toList()..sort(),
    })}\n';
  }

  bool get isEmpty =>
      collapsedThemes.isEmpty &&
      hiddenRepos.isEmpty &&
      favouriteCourses.isEmpty &&
      favouriteYears.isEmpty &&
      enabledLanguages.isEmpty;
}
