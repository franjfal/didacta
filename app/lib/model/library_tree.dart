/// The shape the library actually has.
///
/// A `unit.yaml` records an area, a category and a topic, and the repository
/// is laid out that way on disk: `content/analysis/normed/definition`. That is
/// a four-level tree, and it is not decoration — it is how the material was
/// organised by the person who wrote it.
///
/// Measured on the real repository, the tree is exactly the right size to
/// browse:
///
/// | | |
/// |---|---|
/// | áreas | 2 |
/// | categorías | 51 |
/// | temas | 444 |
/// | unidades | 2147 |
/// | unidades por tema | mediana 3, máximo 131 |
///
/// Fifty-one things, then a handful, then a handful. Three clicks reach any
/// unit. A flat list of 2147 rows reaches the same unit by scrolling past
/// two thousand others, and throws away the grouping the author already did.
///
/// This is pure Dart and separate from the widgets on purpose: the counts and
/// the translation progress are the part with arithmetic in it, and a count
/// that is quietly wrong is invisible in an interface.
library;

import 'catalogue.dart';

/// How much of a group is translated into one language.
///
/// Kept as counts rather than a single percentage because the interface has to
/// distinguish the two cases a percentage flattens: nothing written yet, and
/// written but out of date. They need different work.
class TranslationProgress {
  const TranslationProgress({
    required this.total,
    required this.done,
    required this.needsWork,
    required this.missing,
  });

  factory TranslationProgress.of(Iterable<Unit> units, String language) {
    var total = 0;
    var done = 0;
    var needsWork = 0;
    var missing = 0;
    for (final unit in units) {
      total += 1;
      final status = unit.statusIn(language);
      if (!status.exists) {
        missing += 1;
      } else if (status.needsWork) {
        needsWork += 1;
      } else {
        done += 1;
      }
    }
    return TranslationProgress(
      total: total,
      done: done,
      needsWork: needsWork,
      missing: missing,
    );
  }

  final int total;

  /// Present and current: `source`, `reviewed` or `translated`.
  final int done;

  /// Present but a draft or behind the original.
  final int needsWork;

  /// Not written in this language at all.
  final int missing;

  double get fractionDone => total == 0 ? 0 : done / total;

  bool get isComplete => total > 0 && done == total;

  /// Nothing at all in this language. Worth its own answer: a category with
  /// no Valencian is a different situation from one that is half done.
  bool get isUntouched => total > 0 && done == 0 && needsWork == 0;
}

/// Una etiqueta y cuántas unidades la llevan.
class TagCount {
  const TagCount(this.tag, this.count);

  final String tag;
  final int count;
}

/// Las etiquetas de un montón de unidades, de mayor a menor.
///
/// De mayor a menor y no alfabéticas: esta lista se lee para decidir por
/// dónde entrar, y por donde se entra casi siempre es por donde más hay. A
/// igualdad, alfabéticas, para que dos etiquetas con las mismas unidades no
/// se cambien de sitio entre una pantalla y la siguiente.
List<TagCount> tagCounts(Iterable<Unit> units) {
  final counts = <String, int>{};
  for (final unit in units) {
    for (final tag in unit.tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [for (final entry in entries) TagCount(entry.key, entry.value)];
}

/// One topic: the leaf group, holding units.
class TopicNode {
  const TopicNode({
    required this.category,
    required this.topic,
    required this.units,
  });

  final String category;
  final String topic;

  /// In path order, which is the order a topic is taught in often enough to
  /// be the useful default.
  final List<Unit> units;

  int get count => units.length;

  /// The kinds present, so a topic can show at a glance that it is theory
  /// plus a problem sheet.
  Set<String> get kinds => {for (final unit in units) unit.kind};

  /// The areas present. Now that the area is not a level of the tree, this
  /// is how a group says it holds both theory and exercises.
  Set<String> get blocks => {for (final unit in units) unit.block};

  /// Las etiquetas de sus unidades. Es el nivel de navegación que hay dentro
  /// de un tema: la categoría dice de qué asignatura es esto, el tema de qué
  /// va, y la etiqueta por qué sección de la práctica anda.
  List<TagCount> get tags => tagCounts(units);

  TranslationProgress progressIn(String language) =>
      TranslationProgress.of(units, language);

  /// A readable name. Topics are slugs on disk; this is the best that can be
  /// done without the author writing one, and it is better than `normed-spaces`.
  String get label => humaniseSlug(topic);
}

/// One category: a group of topics, and the level worth showing first.
class CategoryNode {
  const CategoryNode({
    required this.category,
    required this.topics,
    required this.units,
  });

  final String category;

  /// Ordered by size, largest first. Fifty-one categories in alphabetical
  /// order buries the ones being taught; ordering by how much is in them puts
  /// the working material at the top.
  final List<TopicNode> topics;

  /// Every unit in the category, across its topics.
  final List<Unit> units;

  int get count => units.length;

  String get label => humaniseSlug(category);

  TranslationProgress progressIn(String language) =>
      TranslationProgress.of(units, language);

  /// How many of the category's units no composition references.
  ///
  /// After a migration this is the number that matters most: material that
  /// arrived and is not being taught, which is either a gap in a subject or a
  /// candidate for deletion.
  int get unused => units.where((unit) => unit.usedBy.isEmpty).length;

  Set<String> get blocks => {for (final unit in units) unit.block};

  /// How many units are exercises, so a category can say it comes with
  /// problem sheets without opening it.
  int get problems => units.where((unit) => unit.isProblem).length;

  /// Las etiquetas de toda la categoría, para cuando todavía no se ha entrado
  /// en ningún tema.
  List<TagCount> get tags => tagCounts(units);

  TopicNode? topic(String name) {
    for (final node in topics) {
      if (node.topic == name) return node;
    }
    return null;
  }
}

/// El nombre del idioma, para escribirlo en una frase.
///
/// «lo que hay traducido a es» no es castellano; «al castellano» sí.
String languageName(String code) => switch (code) {
  'es' => 'castellano',
  'va' => 'valenciano',
  'ca' => 'catalán',
  'gl' => 'gallego',
  'eu' => 'euskera',
  'en' => 'inglés',
  'fr' => 'francés',
  'de' => 'alemán',
  'it' => 'italiano',
  'pt' => 'portugués',
  // Lo que Didacta no traiga se dice por su código. Preferible a inventarse
  // un nombre: el código es exactamente lo que hay en el nombre del fichero.
  _ => code,
};

/// The whole library, as a tree.
///
/// Built once per catalogue and held by the screen, because walking 2147
/// units on every frame to count a badge is the kind of thing that makes a
/// scroll stutter for no reason anyone can see.
///
/// **The area is not a level of this tree**, and that is a decision worth
/// stating because the first version got it wrong. Making `content` and
/// `problems` the top level split `analysis` into two categories with the
/// same name — the interface said "63 categorías" where the repository has
/// 51, and listed «Análisis real una variable» twice.
///
/// It is also the wrong shape for the question people ask. «¿Qué tengo de
/// espacios normados?» wants the theory *and* the exercises; they are the
/// same subject, taught together. So the area is a filter over the units the
/// tree is built from, and it shows on each unit as its kind.
class LibraryTree {
  const LibraryTree({required this.categories, required this.byPath});

  /// Builds the tree from [units], which the caller has already filtered by
  /// area if it wants to.
  factory LibraryTree.of(Iterable<Unit> units) {
    final grouped = <String, Map<String, List<Unit>>>{};
    final byPath = <String, Unit>{};

    for (final unit in units) {
      byPath[unit.path] = unit;
      grouped
          .putIfAbsent(unit.category, () => {})
          .putIfAbsent(unit.topic, () => [])
          .add(unit);
    }

    final nodes = <CategoryNode>[];
    for (final entry in grouped.entries) {
      final topics = <TopicNode>[];
      final categoryUnits = <Unit>[];
      for (final topic in entry.value.entries) {
        final sorted = [...topic.value]
          ..sort((a, b) => a.path.compareTo(b.path));
        topics.add(
          TopicNode(category: entry.key, topic: topic.key, units: sorted),
        );
        categoryUnits.addAll(sorted);
      }
      topics.sort(_bySizeThenName((node) => (node.count, node.topic)));
      categoryUnits.sort((a, b) => a.path.compareTo(b.path));
      nodes.add(
        CategoryNode(category: entry.key, topics: topics, units: categoryUnits),
      );
    }
    nodes.sort(_bySizeThenName((node) => (node.count, node.category)));

    return LibraryTree(categories: nodes, byPath: byPath);
  }

  /// Largest first, then alphabetically so the order is stable rather than
  /// dependent on which unit happened to be read first.
  static int Function(T, T) _bySizeThenName<T>((int, String) Function(T) key) =>
      (a, b) {
        final left = key(a);
        final right = key(b);
        final bySize = right.$1.compareTo(left.$1);
        return bySize != 0 ? bySize : left.$2.compareTo(right.$2);
      };

  /// Ordered by size, largest first. Fifty-one categories in alphabetical
  /// order buries the ones being taught; ordering by how much is in them puts
  /// the working material at the top.
  final List<CategoryNode> categories;

  /// Every unit by path, so a selection survives a catalogue reload without
  /// searching the tree for it.
  final Map<String, Unit> byPath;

  int get unitCount => byPath.length;

  int get categoryCount => categories.length;

  int get topicCount =>
      categories.fold(0, (sum, category) => sum + category.topics.length);

  /// How many of these units belong to each area, for the filter to say what
  /// choosing it would give.
  Map<String, int> get byBlock {
    final counts = <String, int>{};
    for (final unit in byPath.values) {
      counts[unit.block] = (counts[unit.block] ?? 0) + 1;
    }
    return counts;
  }

  CategoryNode? category(String name) {
    for (final node in categories) {
      if (node.category == name) return node;
    }
    return null;
  }

  TopicNode? topic(String category, String name) =>
      this.category(category)?.topic(name);
}

/// A slug as something worth reading.
///
/// `analisis-real-una-variable` becomes `Análisis real una variable`. It
/// cannot be perfect — the slugs lost their accents on the way in and no
/// amount of code puts them all back — but it beats showing the slug, and the
/// accent table below covers the words this repository actually uses.
String humaniseSlug(String slug) {
  if (slug.isEmpty) return slug;
  final words = slug.split(RegExp(r'[-_]'));
  final restored = [for (final word in words) _accents[word] ?? word];
  final joined = restored.join(' ');
  return joined[0].toUpperCase() + joined.substring(1);
}

/// The accents the slugs dropped, for the words that appear in this
/// repository. Deliberately a table and not a guess: adding one is a one-line
/// change, and inventing accents from rules would put them in the wrong
/// places in the words nobody checked.
const Map<String, String> _accents = {
  'analisis': 'análisis',
  'aplicacion': 'aplicación',
  'calculo': 'cálculo',
  'conicas': 'cónicas',
  'criptografia': 'criptografía',
  'demostracion': 'demostración',
  'derivacion': 'derivación',
  'ecuacion': 'ecuación',
  'funcion': 'función',
  'geometria': 'geometría',
  'grafica': 'gráfica',
  'graficas': 'gráficas',
  'integracion': 'integración',
  'limite': 'límite',
  'limites': 'límites',
  'logica': 'lógica',
  'matematicas': 'matemáticas',
  'matematico': 'matemático',
  'maximos': 'máximos',
  'metodo': 'método',
  'metodos': 'métodos',
  'metrica': 'métrica',
  'metricas': 'métricas',
  'minimos': 'mínimos',
  'numeros': 'números',
  'orbitas': 'órbitas',
  'polinomica': 'polinómica',
  'practica': 'práctica',
  'practicas': 'prácticas',
  'razon': 'razón',
  'reduccion': 'reducción',
  'seccion': 'sección',
  'secciones': 'secciones',
  'solucion': 'solución',
  'soluciones': 'soluciones',
  'sucesion': 'sucesión',
  'sucesiones': 'sucesiones',
  'teoria': 'teoría',
  'topologia': 'topología',
  'trigonometria': 'trigonometría',
  'variacion': 'variación',
};
