/// Los snippets: lo que la barra del editor envuelve, repositorio a repositorio.
///
/// La barra tenía una lista fija --[didactaWrappers]-- y ninguna forma de
/// ampliarla: un entorno propio que usa medio departamento había que
/// escribirlo a mano cada vez, y en el repositorio de problemas seguía
/// ofreciéndose «Teorema» aunque allí no se escriba ninguno.
///
/// Ahora cada repositorio declara los suyos en `snippets.yaml`, y el motor
/// los pone en el índice. Cuatro reglas dan forma a lo que hay aquí:
///
/// **Sin fichero, los de serie.** Un repositorio que no dice nada ofrece lo
/// que se ofrecía antes de que esto existiera: los treinta y tantos de
/// Didacta, en su orden. Con fichero, exactamente lo que el fichero dice.
///
/// **Una entrada con solo el id es la de Didacta.** `- id: theorem` es el
/// teorema de siempre; los campos que se escriban lo retocan --otro nombre,
/// otro grupo-- sin copiar lo demás. Por eso [LatexSnippet.toDeclaration]
/// escribe solo lo que difiere.
///
/// **El mismo id en dos repositorios es el mismo snippet.** Como un bloque o
/// una plantilla: se declara donde se use, y si los dos repositorios dicen
/// cosas distintas de él, eso es trabajo pendiente que se enseña en «Entre
/// repositorios» ([snippetConflicts]). Nada se iguala solo.
///
/// **Sin Flutter.** Como la envoltura: lo que decide qué ofrece la barra y
/// qué se escribe en el fichero de otra persona tiene que poder probarse.
library;

import 'catalogue.dart';
import 'tex_wrap.dart';
import '../l10n/tr.dart';

/// Cómo se escribe alrededor de lo marcado.
enum SnippetShape {
  /// `\begin{x}` … `\end{x}`.
  environment,

  /// `\x{…}`.
  command,

  /// Las dos: la orden para una frase, el entorno para párrafos. Es lo que
  /// hacen los canales (`\onlyslides{…}` y `slidesonly`).
  either,
}

/// Lo que dice una entrada de `snippets.yaml`, tal cual.
///
/// Null es «no lo dice», que en una de Didacta quiere decir «lo de serie».
class SnippetDeclaration {
  const SnippetDeclaration({
    required this.id,
    this.label,
    this.group,
    this.description,
    this.environment,
    this.command,
    this.environmentAliases,
    this.commandAliases,
    this.arguments,
    this.block,
    this.definition,
    this.sample,
  });

  factory SnippetDeclaration.fromJson(Map<String, dynamic> json) {
    List<String>? names(Object? value) =>
        value is List ? [for (final each in value) '$each'] : null;
    return SnippetDeclaration(
      id: json['id'] as String? ?? '',
      label: json['label'] as String?,
      group: json['group'] as String?,
      description: json['description'] as String?,
      environment: json['environment'] as String?,
      command: json['command'] as String?,
      environmentAliases: names(json['environmentAliases']),
      commandAliases: names(json['commandAliases']),
      arguments: json['arguments'] as String?,
      block: json['block'] as bool?,
      definition: json['definition'] as String?,
      sample: json['sample'] as String?,
    );
  }

  final String id;
  final String? label;
  final String? group;
  final String? description;
  final String? environment;
  final String? command;
  final List<String>? environmentAliases;
  final List<String>? commandAliases;
  final String? arguments;
  final bool? block;
  final String? definition;
  final String? sample;

  /// Si no dice nada más que el id: la de Didacta, tal cual.
  bool get isReference =>
      label == null &&
      group == null &&
      description == null &&
      environment == null &&
      command == null &&
      environmentAliases == null &&
      commandAliases == null &&
      arguments == null &&
      block == null &&
      definition == null &&
      sample == null;
}

/// El nombre con que se enseña cada grupo de los de serie.
Map<TexWrapGroup, String> get snippetGroupNames => {
  TexWrapGroup.channel: tr('Canales'),
  TexWrapGroup.format: tr('Formato'),
  TexWrapGroup.slide: tr('Diapositiva'),
  TexWrapGroup.problem: tr('Problema'),
  TexWrapGroup.theory: tr('Teoría'),
  TexWrapGroup.teacher: tr('Profesor'),
  TexWrapGroup.custom: tr('Propios'),
};

/// El texto de ejemplo de los de serie, por grupo: lo que se ve en la vista
/// previa antes de que nadie escriba el suyo.
Map<TexWrapGroup, String> get _sampleByGroup => {
  TexWrapGroup.channel: tr(
    'Este párrafo solo sale en una de las salidas: compila en las dos para '
    'ver la diferencia.',
  ),
  TexWrapGroup.format: tr('una palabra'),
  TexWrapGroup.slide: tr('El contenido de la diapositiva.'),
  TexWrapGroup.problem: tr(r'Calcula la derivada de $f(x) = x^2 \sin x$.'),
  TexWrapGroup.theory: tr(
    'Toda función continua en un intervalo cerrado y acotado alcanza su '
    'máximo y su mínimo.',
  ),
  TexWrapGroup.teacher: tr(
    'Conviene detenerse aquí: es el paso que más cuesta en clase.',
  ),
  TexWrapGroup.custom: tr('Un texto de ejemplo para ver cómo queda.'),
};

/// Un snippet ya resuelto: lo de Didacta con lo que retoque el repositorio.
class LatexSnippet {
  const LatexSnippet({
    required this.id,
    required this.label,
    required this.group,
    this.description = '',
    this.environment,
    this.command,
    this.environmentAliases = const [],
    this.commandAliases = const [],
    this.arguments = '',
    this.block = false,
    this.definition = '',
    this.sample = '',
    this.base,
  });

  /// El de Didacta, sin retocar.
  factory LatexSnippet.fromWrapper(TexWrapper wrapper) => LatexSnippet(
    id: wrapper.id,
    label: wrapper.label,
    group: wrapper.groupLabel ?? snippetGroupNames[wrapper.group]!,
    environment: wrapper.environment,
    command: wrapper.macro,
    environmentAliases: wrapper.environmentAliases,
    commandAliases: wrapper.macroAliases,
    arguments: wrapper.arguments,
    block: wrapper.block,
    sample: _sampleByGroup[wrapper.group] ?? '',
    base: wrapper,
  );

  /// Lo que dice una entrada, encima del de Didacta si lleva su id.
  factory LatexSnippet.resolve(SnippetDeclaration declared) {
    final wrapper = didactaWrapperById(declared.id);
    final base = wrapper == null ? null : LatexSnippet.fromWrapper(wrapper);
    return LatexSnippet(
      id: declared.id,
      label: declared.label ?? base?.label ?? declared.id,
      group:
          declared.group ??
          base?.group ??
          snippetGroupNames[TexWrapGroup.custom]!,
      description: declared.description ?? base?.description ?? '',
      environment: declared.environment ?? base?.environment,
      command: declared.command ?? base?.command,
      environmentAliases:
          declared.environmentAliases ?? base?.environmentAliases ?? const [],
      commandAliases:
          declared.commandAliases ?? base?.commandAliases ?? const [],
      arguments: declared.arguments ?? base?.arguments ?? '',
      block: declared.block ?? base?.block ?? false,
      definition: declared.definition ?? '',
      sample: declared.sample ?? base?.sample ?? '',
      base: wrapper,
    );
  }

  final String id;
  final String label;

  /// Dónde se enseña en el selector: «Teoría», «Canales», «Mis cajas».
  final String group;

  /// Para qué sirve, en una frase. Sale en el selector y en el gestor.
  final String description;

  final String? environment;
  final String? command;
  final List<String> environmentAliases;
  final List<String> commandAliases;

  /// Lo que va entre el nombre y el cuerpo: `[Título]`, `{red}`.
  final String arguments;

  /// Siempre entorno, aunque lo marcado sea una frase. Solo tiene sentido
  /// cuando tiene las dos formas.
  final bool block;

  /// El LaTeX que lo define, si no lo define ya Didacta o un paquete. Va al
  /// preámbulo de todo lo que se compila en el repositorio.
  final String definition;

  /// Lo que se escribe dentro en la vista previa.
  final String sample;

  /// El de Didacta con el mismo id, si lo hay.
  final TexWrapper? base;

  /// Si viene de los de serie, retocado o no.
  bool get fromDidacta => base != null;

  /// Si dice algo que el de serie no dice.
  bool get retouched => base != null && !toDeclaration().isReference;

  /// Si sabe envolver algo. Una entrada con un id que no es de Didacta y sin
  /// nombre no sabe: se enseña en el gestor, para arreglarla, y no en la
  /// barra.
  bool get usable => environment != null || command != null;

  SnippetShape get shape {
    if (environment != null && command != null) return SnippetShape.either;
    return environment != null
        ? SnippetShape.environment
        : SnippetShape.command;
  }

  /// Lo que la barra usa para envolver y desenvolver.
  ///
  /// Solo para uno [usable]: un [TexWrapper] tiene que tener alguna forma.
  TexWrapper get wrapper => TexWrapper(
    id: id,
    label: label,
    group: base?.group ?? TexWrapGroup.custom,
    macro: command,
    environment: environment,
    macroAliases: commandAliases,
    environmentAliases: environmentAliases,
    block: block,
    arguments: arguments,
    groupLabel: group,
  );

  /// Cómo se escribe, en una línea: lo que se lee al lado del nombre.
  String get usage {
    if (!usable) return '';
    final env = environment == null
        ? ''
        : '\\begin{$environment}$arguments … \\end{$environment}';
    final cmd = command == null ? '' : '\\$command$arguments{…}';
    return switch (shape) {
      SnippetShape.environment => env,
      SnippetShape.command => cmd,
      SnippetShape.either => block ? env : '$cmd  ·  $env',
    };
  }

  /// Cómo empieza, en corto: lo que cabe al lado del nombre en el selector.
  String get opening {
    if (!usable) return '';
    final asEnvironment = environment != null && (command == null || block);
    return asEnvironment
        ? '\\begin{$environment}$arguments'
        : '\\$command$arguments{…}';
  }

  /// Lo que la vista previa compila: el texto de ejemplo envuelto.
  String get previewBody {
    if (!usable) return sample;
    final text = sample.trim().isEmpty
        ? _sampleByGroup[TexWrapGroup.custom]!
        : sample.trim();
    return toggleWrap(text, 0, text.length, wrapper).text;
  }

  /// Todas las palabras por las que se le puede encontrar.
  String get searchable => [
    label,
    group,
    description,
    id,
    ?environment,
    ?command,
    ...environmentAliases,
    ...commandAliases,
  ].join(' ');

  /// Lo que se compara entre repositorios, con el nombre que se enseña.
  ///
  /// Todo lo que cambia lo que se escribe o lo que compila. Un snippet con
  /// la misma definición y otro rótulo es una molestia; con otra definición,
  /// el mismo `\begin{resumen}` sale distinto según el repositorio, y eso es
  /// lo que no puede pasar sin que nadie lo sepa.
  Map<String, String> get comparable => {
    tr('rótulo'): label,
    tr('grupo'): group,
    tr('descripción'): description,
    tr('entorno'): environment ?? '',
    tr('orden'): command == null ? '' : '\\$command',
    tr('nombres heredados'): [
      ...environmentAliases,
      for (final name in commandAliases) '\\$name',
    ].join(', '),
    tr('argumentos'): arguments,
    tr('siempre como entorno'): shape == SnippetShape.either
        ? (block ? tr('sí') : tr('no'))
        : '',
    tr('definición'): definition.trim(),
    tr('texto de ejemplo'): sample.trim(),
  };

  /// Lo que se escribe en `snippets.yaml`: de uno de serie, solo lo que
  /// cambia; de uno propio, todo lo que tiene.
  SnippetDeclaration toDeclaration() {
    final original = base == null ? null : LatexSnippet.fromWrapper(base!);
    T? ifChanged<T>(T mine, T? theirs, {bool Function(T)? empty}) {
      if (original == null) {
        return (empty?.call(mine) ?? false) ? null : mine;
      }
      return _same(mine, theirs) ? null : mine;
    }

    return SnippetDeclaration(
      id: id,
      label: ifChanged(label, original?.label),
      group: ifChanged(group, original?.group),
      description: ifChanged(
        description,
        original?.description,
        empty: (value) => value.isEmpty,
      ),
      environment: original == null
          ? environment
          : (environment == original.environment ? null : environment),
      command: original == null
          ? command
          : (command == original.command ? null : command),
      environmentAliases: ifChanged(
        environmentAliases,
        original?.environmentAliases,
        empty: (value) => value.isEmpty,
      ),
      commandAliases: ifChanged(
        commandAliases,
        original?.commandAliases,
        empty: (value) => value.isEmpty,
      ),
      arguments: ifChanged(
        arguments,
        original?.arguments,
        empty: (value) => value.isEmpty,
      ),
      block: shape == SnippetShape.either
          ? ifChanged(block, original?.block, empty: (value) => !value)
          : null,
      definition: definition.trim().isEmpty ? null : definition,
      sample: ifChanged(
        sample,
        original?.sample,
        empty: (value) => value.isEmpty,
      ),
    );
  }

  LatexSnippet copyWith({
    String? id,
    String? label,
    String? group,
    String? description,
    String? environment,
    bool clearEnvironment = false,
    String? command,
    bool clearCommand = false,
    List<String>? environmentAliases,
    List<String>? commandAliases,
    String? arguments,
    bool? block,
    String? definition,
    String? sample,
  }) => LatexSnippet(
    id: id ?? this.id,
    label: label ?? this.label,
    group: group ?? this.group,
    description: description ?? this.description,
    environment: clearEnvironment ? null : (environment ?? this.environment),
    command: clearCommand ? null : (command ?? this.command),
    environmentAliases: environmentAliases ?? this.environmentAliases,
    commandAliases: commandAliases ?? this.commandAliases,
    arguments: arguments ?? this.arguments,
    block: block ?? this.block,
    definition: definition ?? this.definition,
    sample: sample ?? this.sample,
    base: id == null || id == this.id ? base : didactaWrapperById(id),
  );

  /// Si dicen lo mismo, campo a campo.
  bool sameAs(LatexSnippet other) {
    final mine = comparable;
    final theirs = other.comparable;
    for (final key in mine.keys) {
      if (mine[key] != theirs[key]) return false;
    }
    return true;
  }
}

bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}

/// El de Didacta con ese id, o null.
TexWrapper? didactaWrapperById(String id) {
  for (final wrapper in didactaWrappers) {
    if (wrapper.id == id) return wrapper;
  }
  return null;
}

/// Los de serie, en su orden: lo que ofrece un repositorio sin fichero.
final List<LatexSnippet> didactaSnippets = [
  for (final wrapper in didactaWrappers) LatexSnippet.fromWrapper(wrapper),
];

/// La lista de un repositorio: la declarada, o la de serie si no declara.
List<LatexSnippet> resolveSnippets(List<SnippetDeclaration>? declared) =>
    declared == null
    ? didactaSnippets
    : [for (final entry in declared) LatexSnippet.resolve(entry)];

/// Un snippet en la biblioteca: en qué repositorios está y qué dice en cada
/// uno.
class SnippetEntry {
  const SnippetEntry({required this.id, required this.byRepo, this.base});

  final String id;

  /// Lo que dice cada repositorio que lo tiene, en el orden de los
  /// repositorios. Vacío para uno de serie que no está en ninguno.
  final Map<String, LatexSnippet> byRepo;

  final TexWrapper? base;

  /// El que se enseña: el del primer repositorio que lo tenga, o el de serie.
  LatexSnippet get shown =>
      byRepo.isNotEmpty ? byRepo.values.first : LatexSnippet.fromWrapper(base!);

  bool get fromDidacta => base != null;

  /// Los campos en que no coinciden los repositorios, con lo que dice cada
  /// uno. Vacío si coinciden o si solo lo tiene uno.
  Map<String, Map<String, String>> get differences {
    if (byRepo.length < 2) return const {};
    final out = <String, Map<String, String>>{};
    final fields = byRepo.values.first.comparable.keys;
    for (final field in fields) {
      final values = {
        for (final entry in byRepo.entries)
          entry.key: entry.value.comparable[field] ?? '',
      };
      if (values.values.toSet().length > 1) out[field] = values;
    }
    return out;
  }

  bool get diverges => differences.isNotEmpty;
}

/// Un snippet que dos repositorios declaran distinto.
class SnippetConflict {
  const SnippetConflict({required this.entry, required this.differences});

  final SnippetEntry entry;
  final Map<String, Map<String, String>> differences;

  String get id => entry.id;
}

/// Lo que el catálogo sabe de los snippets.
extension CatalogueSnippets on Catalogue {
  /// Los que ofrece la barra en un repositorio, en su orden.
  ///
  /// Sin repositorio --un editor que no sabe de dónde es su fichero-- o con
  /// uno que el índice no trae, los de serie: es lo que se ofrecía antes, y
  /// no ofrecer nada dejaría la barra vacía por un dato que falta.
  List<LatexSnippet> snippetsIn(String? repo) {
    if (repo == null || !snippets.containsKey(repo)) return didactaSnippets;
    return resolveSnippets(snippets[repo]);
  }

  /// Si el repositorio tiene su propio `snippets.yaml`.
  bool declaresSnippets(String repo) => snippets[repo] != null;

  /// Todos los snippets de los repositorios [repos], juntos y en orden.
  ///
  /// El orden es el de cada fichero, cosido: primero el del primer
  /// repositorio, y lo que solo tenga otro entra detrás del que tiene
  /// delante en su propio fichero. Al final, los de serie que no están en
  /// ninguno, para poder volver a ponerlos.
  List<SnippetEntry> snippetLibrary(List<String> repos) {
    final order = <String>[];
    final byId = <String, Map<String, LatexSnippet>>{};
    for (final repo in repos) {
      String? previous;
      for (final snippet in snippetsIn(repo)) {
        byId.putIfAbsent(snippet.id, () => {})[repo] = snippet;
        if (!order.contains(snippet.id)) {
          order.insert(
            previous == null ? 0 : order.indexOf(previous) + 1,
            snippet.id,
          );
        }
        previous = snippet.id;
      }
    }
    for (final wrapper in didactaWrappers) {
      if (!order.contains(wrapper.id)) order.add(wrapper.id);
    }
    return [
      for (final id in order)
        SnippetEntry(
          id: id,
          byRepo: byId[id] ?? const {},
          base: didactaWrapperById(id),
        ),
    ];
  }

  /// Los que dos repositorios declaran distinto.
  List<SnippetConflict> snippetConflicts(List<String> repos) => [
    for (final entry in snippetLibrary(repos))
      if (entry.diverges)
        SnippetConflict(entry: entry, differences: entry.differences),
  ];
}

/// Lo que devuelve la vista previa de un snippet: el PDF, o por qué no hay.
class SnippetPreview {
  const SnippetPreview({
    required this.ok,
    this.pdf,
    this.errors = const [],
    this.seconds = 0,
    this.slides = false,
    this.engineFailed = false,
  });

  factory SnippetPreview.fromJson(Map<String, dynamic> json) {
    final errors = <String>[
      if (json['error'] is String) json['error'] as String,
      for (final item in (json['diagnostics'] as List?) ?? const [])
        if (item is Map && item['severity'] == 'error')
          [
            '${item['message'] ?? ''}',
            if ((item['context'] as String?)?.trim().isNotEmpty ?? false)
              '  ${(item['context'] as String).trim()}',
          ].join('\n'),
    ];
    return SnippetPreview(
      ok: json['ok'] == true,
      pdf: json['pdf'] as String?,
      errors: errors,
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      slides: json['slides'] == true,
    );
  }

  final bool ok;
  final String? pdf;

  /// Los errores de LaTeX, ya en frases: lo primero que hay que leer cuando
  /// la definición no compila.
  final List<String> errors;
  final double seconds;
  final bool slides;

  /// Si lo que falló fue el motor --no arrancó, no contestó-- y no el LaTeX.
  final bool engineFailed;
}
