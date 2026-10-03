/// Lo que ya existe, para sugerirlo al escribir los metadatos de una lección.
///
/// La categoría, el tema, las etiquetas y los prerrequisitos son texto libre,
/// y una errata --`analisys`, `norma` por `normas`-- crea una categoría o una
/// etiqueta nueva sin que nadie lo note, con una lección que desaparece de su
/// sitio en la biblioteca. Aquí se reúne lo que ya usan las demás lecciones,
/// con cuántas lo usan, para ofrecerlo y para decir cuándo lo escrito es
/// nuevo.
library;

import 'catalogue.dart';
import 'slug.dart';
import '../l10n/tr.dart';

/// Una sugerencia: el valor, cuántas lecciones lo usan y algo que lo aclare.
class Suggestion {
  const Suggestion(
    this.value, {
    this.uses = 0,
    this.detail,
    this.isNew = false,
  });

  final String value;
  final int uses;

  /// Lo que se enseña al lado: el título de una lección, en los
  /// prerrequisitos.
  final String? detail;

  /// Lo escrito tal cual, cuando no existe: va primero para que Intro lo
  /// deje como está y no lo cambie por la sugerencia más parecida.
  final bool isNew;
}

class MetadataSuggestions {
  MetadataSuggestions._(
    this._categories,
    this._topics,
    this._tags,
    this._units,
  );

  factory MetadataSuggestions.of(Catalogue catalogue, {String? language}) {
    final categories = <String, int>{};
    final topics = <String, Map<String, int>>{};
    final tags = <String, int>{};
    final units = <String, (String, String)>{};
    for (final unit in catalogue.units) {
      if (unit.category.isNotEmpty) {
        categories[unit.category] = (categories[unit.category] ?? 0) + 1;
        if (unit.topic.isNotEmpty) {
          final inCategory = topics.putIfAbsent(unit.category, () => {});
          inCategory[unit.topic] = (inCategory[unit.topic] ?? 0) + 1;
        }
      }
      for (final tag in unit.tags) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }
      units[unit.reference_] = (
        unit.title(language ?? unit.reference),
        unit.pathReference,
      );
    }
    return MetadataSuggestions._(categories, topics, tags, units);
  }

  final Map<String, int> _categories;
  final Map<String, Map<String, int>> _topics;
  final Map<String, int> _tags;

  /// Las lecciones por su referencia --su id, que es lo que se escribe--, con
  /// su título y su ruta, que es por lo que se las busca.
  final Map<String, (String, String)> _units;

  List<Suggestion> categories(String typed) =>
      _rank(typed, _categories, fresh: tr('categoría nueva'));

  /// Los temas de [category] primero, y después los de las demás: un tema se
  /// llama igual en dos categorías más a menudo de lo que parece.
  List<Suggestion> topics(String typed, {String? category}) {
    final own = _topics[category] ?? const {};
    final others = <String, int>{};
    for (final entry in _topics.entries) {
      if (entry.key == category) continue;
      entry.value.forEach((topic, uses) {
        if (!own.containsKey(topic)) {
          others[topic] = (others[topic] ?? 0) + uses;
        }
      });
    }
    final first = _rank(
      typed,
      own,
      fresh: tr('tema nuevo'),
      known: {...own, ...others},
    );
    final rest = _rank(typed, others, fresh: null);
    return [...first, ...rest].take(_limit).toList();
  }

  List<Suggestion> tags(String typed, {Set<String> except = const {}}) => _rank(
    typed,
    {
      for (final entry in _tags.entries)
        if (!except.contains(entry.key)) entry.key: entry.value,
    },
    fresh: tr('etiqueta nueva'),
    known: _tags,
  );

  /// Las lecciones que se pueden poner de prerrequisito, buscando en la ruta
  /// y en el título.
  List<Suggestion> units(String typed, {String? except}) {
    final wanted = _folded(typed);
    final starts = <Suggestion>[];
    final contains = <Suggestion>[];
    for (final entry in _units.entries) {
      if (entry.key == except) continue;
      final path = _folded(entry.value.$2);
      final title = _folded(entry.value.$1);
      final suggestion = Suggestion(entry.key, detail: entry.value.$1);
      if (wanted.isEmpty || path.startsWith(wanted)) {
        starts.add(suggestion);
      } else if (path.contains(wanted) || title.contains(wanted)) {
        contains.add(suggestion);
      }
    }
    return [...starts, ...contains].take(_limit).toList();
  }

  bool knowsCategory(String value) => _categories.containsKey(value);

  bool knowsTopic(String value) =>
      _topics.values.any((topics) => topics.containsKey(value));

  /// Si nombra una lección: por su id, o por su ruta como se escribía antes.
  bool knowsUnit(String value) =>
      _units.containsKey(value.trim()) ||
      _units.values.any((unit) => unit.$2 == value.trim());

  static const int _limit = 8;

  /// Lo que coincide con [typed], lo que empieza por él antes que lo que lo
  /// contiene y, a igualdad, lo más usado. Con [fresh], lo escrito va delante
  /// si no existe en [known], con ese rótulo: es una categoría o una etiqueta
  /// nueva, y tiene que verse que lo es.
  List<Suggestion> _rank(
    String typed,
    Map<String, int> values, {
    required String? fresh,
    Map<String, int>? known,
  }) {
    final wanted = _folded(typed);
    final starts = <Suggestion>[];
    final contains = <Suggestion>[];
    for (final entry in values.entries) {
      final value = _folded(entry.key);
      final suggestion = Suggestion(entry.key, uses: entry.value);
      if (wanted.isEmpty || value.startsWith(wanted)) {
        starts.add(suggestion);
      } else if (value.contains(wanted)) {
        contains.add(suggestion);
      }
    }
    int byUse(Suggestion a, Suggestion b) => b.uses.compareTo(a.uses);
    starts.sort(byUse);
    contains.sort(byUse);
    final text = typed.trim();
    final exists = (known ?? values).containsKey(text);
    return [
      if (fresh != null && text.isNotEmpty && !exists)
        Suggestion(text, isNew: true, detail: fresh),
      ...starts,
      ...contains,
    ].take(_limit).toList();
  }
}

String _folded(String text) => fold(text.trim().toLowerCase());
