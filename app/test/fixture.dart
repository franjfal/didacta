/// The catalogue, gateway and session the widget tests run against.
///
/// Shared rather than copied into each test file, because the point of these
/// fixtures is that every screen is exercised against *the same* awkward
/// data: a unit with two missing translations, a composition with a broken
/// reference, a document with no profiles. Data that is too tidy proves
/// nothing.
library;

import 'dart:io';

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/data/secrets.dart';
import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/toolchain.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:didacta_app/model/tex_indent.dart';
import 'package:didacta_app/model/toolchain.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';

/// Un actualizador que no pregunta nada a nadie.
///
/// Los tests de pantalla no tienen red y no la quieren: lo que prueban es la
/// interfaz. Se le da una comprobación recién hecha y ningún token, así que
/// ni la automática ni la manual llegan a salir de la máquina.
///
/// Está aquí y no en cada fichero porque `DidactaApp` lo pide siempre: la
/// aplicación real no se levanta sin saber qué versión es.
UpdateService offlineUpdates() => UpdateService(
  info: const AppInfo(
    version: AppVersion(1, 0, 0),
    build: 1,
    packageName: 'es.uv.didacta',
    platform: UpdatePlatform.macos,
    architecture: 'universal',
  ),
  preferences: MemoryPreferences()..checked = DateTime.now(),
);

const String unitPath = 'content/analysis/normed/definition';

/// A `unit.yaml` in the shape the migrator writes them, comments and all.
///
/// The comments are load-bearing in these tests: the metadata editor's whole
/// claim is that they survive an edit.
const String unitYaml = '''
# Espacios normados
#
# Migrated from:
#   00classnotes/901Analysis/01Handouts/01-normed/00CAST-definicion.tex
#
# The fields marked TODO are the ones the legacy material did not record.

id: analysis.normed.definition
kind: theory

title:
  # TODO: check the title against the handout
  es: Espacios normados

category: analysis
topic: normed
tags: [norma, banach]

reference: es

# Only languages that exist are listed; absence is what `missing` means.
languages:
  es: {status: source}

# TODO: what this unit assumes, and what a student can do after it.
prerequisites: []
objectives: []

duration_minutes: null
difficulty: null
''';

Map<String, dynamic> unitJson({
  String path = unitPath,
  String area = 'content',
  String kind = 'theory',
  String category = 'analysis',
  String topic = 'normed',
  Map<String, String> title = const {'es': 'Espacios normados'},
  Map<String, dynamic>? languages,
  List<Map<String, String>> usedBy = const [
    {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
  ],
  List<String> prerequisites = const <String>[],
  List<String> warnings = const <String>[],
  List<String> tags = const ['norma', 'banach'],
  String? block,
}) => {
  'id': path.split('/').skip(1).join('.'),
  'path': path,
  'area': area,
  'kind': kind,
  'block': block ?? (area == 'problems' ? 'problems' : 'theory'),
  'category': category,
  'topic': topic,
  'tags': tags,
  'title': title,
  'reference': 'es',
  'languages':
      languages ??
      const {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': 'missing', 'exists': false},
        'en': {'status': 'missing', 'exists': false},
      },
  'prerequisites': prerequisites,
  'objectives': const ['Reconocer una norma', 'Distinguir norma de métrica'],
  'usedBy': usedBy,
  'warnings': warnings,
};

/// Enough units to exercise a list, a filter and a broken reference.
List<Map<String, dynamic>> defaultUnits() => [
  unitJson(),
  unitJson(
    path: 'content/analysis/normed/banach',
    title: const {'es': 'Espacios de Banach'},
    prerequisites: const ['analysis/normed/definition', 'analysis/no/existe'],
    languages: const {
      'es': {'status': 'source', 'exists': true},
      'va': {'status': 'outdated', 'exists': true},
      'en': {'status': 'missing', 'exists': false},
    },
  ),
  unitJson(
    path: 'problems/analysis/normed/exercises',
    area: 'problems',
    // El tipo que le pone el motor a una unidad de `problems/`, y uno de los
    // que acepta: `exercise` no está entre ellos y aquí decidía si la pantalla
    // ofrece los tres campos.
    kind: 'problem',
    tags: const ['ejercicios'],
    title: const {'es': 'Ejercicios de normas'},
    usedBy: const <Map<String, String>>[],
    warnings: const ['La figura `norma.pdf` no se encontró'],
  ),
  unitJson(
    path: 'content/algebra/matrices/rank',
    category: 'algebra',
    topic: 'matrices',
    // No Spanish title at all: a real case in migrated material.
    title: const {},
    usedBy: const <Map<String, String>>[],
  ),
];

/// A `year.yaml` matching [courseJson], in the shape the migrator writes.
///
/// It has the two things that make composition editing interesting: a
/// commented-out entry, and a heading whose title is per language with a TODO
/// for the ones still missing.
const String yearYaml = '''
# Análisis Matemático III -- 2025-2026
#
# Selection, order and structure. No content: every entry below is a
# reference into content/ or problems/.

course: am-iii
year: 2025-2026
group: A
language: es

documents:
  - id: tema-1
    kind: theory
    title:
      es: Tema 1. Espacios normados
    profiles: [handout, slides]
    structure:
      - section:
          es: Normas
          # TODO: va
          # TODO: en
      - unit: analysis/normed/definition
      - unit: analysis/normed/banach
      # - unit: analysis/normed/dedekind
      - unit: analysis/normed/no-existe

  - id: hoja-1
    kind: problems
    title:
      es: Hoja 1
    structure:
      - problem: analysis/normed/exercises
''';

Map<String, dynamic> courseJson() => {
  'id': 'am-iii',
  'title': const {'es': 'Análisis Matemático III'},
  'language': 'es',
  'code': '34567',
  'teacher': 'Javier Falcó',
  'institution': 'Universitat de València',
  'years': {
    '2025-2026': {
      'year': '2025-2026',
      'language': 'es',
      'group': 'A',
      'documents': [
        {
          'id': 'tema-1',
          'kind': 'theory',
          'language': 'es',
          'title': const {'es': 'Tema 1. Espacios normados'},
          // Lo que este tema **permite** compilar. Desde que se puede
          // restringir, esto no es una preselección: es la lista de lo que
          // puede salir de él.
          'profiles': const ['slides', 'notes'],
          'unitRefs': const [
            'analysis/normed/definition',
            'analysis/normed/banach',
            // Deliberately broken: a composition that silently skips what
            // is missing looks complete and compiles short.
            'analysis/normed/no-existe',
          ],
          // Con su apartado, como la escribe el motor: la lista plana dice
          // qué se compila, y esto cómo está repartido.
          'structure': const [
            {
              'section': {'es': 'Normas'},
            },
            {'unit': 'analysis/normed/definition'},
            {'unit': 'analysis/normed/banach'},
            {'unit': 'analysis/normed/no-existe'},
          ],
        },
        {
          'id': 'hoja-1',
          'kind': 'problems',
          'language': 'es',
          'title': const {'es': 'Hoja 1'},
          'profiles': const <String>[],
          'unitRefs': const ['analysis/normed/exercises'],
          'structure': const [
            {'problem': 'analysis/normed/exercises'},
          ],
        },
      ],
    },
  },
};

Catalogue catalogueWith(
  List<Map<String, dynamic>> units, {
  List<Map<String, dynamic>>? courses,
  List<Map<String, dynamic>>? profiles,

  /// Los temas compartidos, con las ubicaciones que los dan. Vacío es lo
  /// corriente: sin nada vinculado, todo se ve como se veía.
  List<Map<String, dynamic>> shared = const [],
  String repo = '',

  /// A los que traduce este repositorio. Se puede cambiar porque dos
  /// repositorios abiertos no tienen por qué mantener los mismos, y esa es
  /// justo la situación que decide qué se puede escribir en cada uno.
  List<String> languages = const ['es', 'va', 'en'],
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': languages,
    // Con más de los que el repositorio usa, que es la situación real desde
    // que Didacta trae diez ficheros de idioma: una pantalla que ofrece
    // activar idiomas se prueba contra una lista más larga que la de uso, o
    // no prueba nada.
    'availableLanguages': const [
      {'code': 'es', 'name': 'Castellano'},
      {'code': 'va', 'name': 'Valencià'},
      {'code': 'ca', 'name': 'Català'},
      {'code': 'en', 'name': 'English'},
      {'code': 'fr', 'name': 'Français'},
      {'code': 'de', 'name': 'Deutsch'},
    ],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    // Con las versiones que el motor ofrece de verdad, y con su nombre:
    // sin ellas, cualquier pantalla que las liste se prueba contra una
    // lista vacía, que es el único caso que no ocurre nunca.
    //
    // Y salen de aquí y no del compilador de mentira porque desde que hay
    // plantillas quien decide con qué se compila algo es el catálogo: las dos
    // listas tienen que decir lo mismo o la pantalla ofrece una cosa y el
    // motor compila otra.
    'profiles':
        profiles ??
        const [
          {
            'id': 'slides',
            'label': 'Diapositivas',
            'family': 'slides',
            'documentClass': 'beamer',
          },
          {
            'id': 'book',
            'label': 'Libro',
            'family': 'notes',
            'documentClass': 'book',
          },
          {
            'id': 'notes',
            'label': 'Apuntes',
            'family': 'notes',
            'documentClass': 'article',
          },
          // La versión del profesor, que es la que prueba que lo que se ofrece no
          // viene marcado por defecto. Las mismas que ofrece [FakeCompiler]: desde
          // que las salidas salen del catálogo, las dos listas tienen que decir lo
          // mismo o la pantalla ofrece una cosa y el motor compila otra.
          {
            'id': 'notes-teacher',
            'label': 'Apuntes (profesor)',
            'family': 'notes',
            'documentClass': 'article',
            'reveals': 'teacher',
          },
        ],
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': units},
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'courses': courses ?? [courseJson()],
    'shared': shared,
  },
  repo: repo,
);

/// A gateway that records what it was asked to do.
class FakeGateway extends ContentGateway {
  FakeGateway({this.writable = true, this.failWith, Map<String, String>? files})
    : files =
          files ??
          {
            '$unitPath/es.tex': 'El contenido original en castellano.',
            '$unitPath/unit.yaml': unitYaml,
            'courses/am-iii/2025-2026/year.yaml': yearYaml,
          };

  final bool writable;
  final ContentException? failWith;
  final Map<String, String> files;

  final List<({String path, String text, String message, String sha})> commits =
      [];

  @override
  GatewayKind get kind => GatewayKind.clone;

  @override
  bool get canWrite => writable;

  @override
  String describe() => 'gateway de prueba';

  @override
  Future<ContentFile> read(String path) async {
    final text = files[path];
    if (text == null) {
      throw ContentException('no existe $path', kind: ContentFailure.missing);
    }
    return ContentFile(path: path, text: text, sha: 'sha-$path');
  }

  @override
  Future<String> save({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    if (failWith != null) throw failWith!;
    commits.add((path: path, text: text, message: message, sha: sha));
    files[path] = text;
    return 'nuevo-sha';
  }

  /// Por defecto confirma, que es lo que hace la aplicación de salida.
  @override
  bool get commitsOnSave => commitsWhenSaving;

  bool commitsWhenSaving = true;
}

/// Las mismas tres, como las trae el índice.
///
/// Dos formas de lo mismo porque hay dos capas: el catálogo dice qué salidas
/// hay --y es quien manda desde que existen las plantillas-- y el compilador
/// las recibe ya elegidas.
const problemProfilesJson = [
  {
    'id': 'problems',
    'label': 'Hoja de problemas',
    'family': 'problems',
    'documentClass': 'article',
    'reveals': 'statements',
  },
  {
    'id': 'problems-answers',
    'label': 'Hoja de problemas (con resultados)',
    'family': 'problems',
    'documentClass': 'article',
    'reveals': 'answers',
  },
  {
    'id': 'problems-teacher',
    'label': 'Hoja de problemas (profesor)',
    'family': 'problems',
    'documentClass': 'article',
    'reveals': 'teacher',
  },
];

/// Las tres versiones de cualquier cosa con ejercicios dentro, tal como las
/// lista el motor: enunciados, enunciados con el resultado, y la del
/// profesor con la solución paso a paso.
const problemProfiles = [
  BuildableProfile(
    id: 'problems',
    label: 'Hoja de problemas',
    family: 'problems',
  ),
  BuildableProfile(
    id: 'problems-answers',
    label: 'Hoja de problemas (con resultados)',
    family: 'problems',
    reveals: 'answers',
  ),
  BuildableProfile(
    id: 'problems-teacher',
    label: 'Hoja de problemas (profesor)',
    family: 'problems',
    reveals: 'teacher',
  ),
];

/// A compiler that answers without launching anything.
class FakeCompiler implements Compiler {
  FakeCompiler({
    this.ready = true,
    this.problem,
    this.profiles = const [
      BuildableProfile(id: 'slides', label: 'Diapositivas', family: 'slides'),
      BuildableProfile(id: 'book', label: 'Libro', family: 'notes'),
      BuildableProfile(id: 'notes', label: 'Apuntes', family: 'notes'),
      BuildableProfile(
        id: 'notes-teacher',
        label: 'Apuntes (profesor)',
        family: 'notes',
        reveals: 'teacher',
      ),
    ],
    this.failWith,
    this.outputs,
    this.onRun,
  });

  final bool ready;
  final String? problem;
  final List<BuildableProfile> profiles;
  final Object? failWith;
  final List<CompileOutput>? outputs;

  /// What it was asked for, so a test can check it was asked for what was
  /// chosen and not something else.
  final List<({List<String> profiles, List<String> languages})> calls = [];

  final List<String> opened = [];
  final List<String> revealed = [];

  /// Lo que el motor deja en el disco.
  ///
  /// Un motor de verdad **cambia ficheros**, y lo que la aplicación hace con
  /// esos cambios --cerrarlos en un commit-- es justo lo que hay que probar.
  /// Sin esto, un test del commit no probaría nada: `git commit` sobre un
  /// árbol intacto no es un commit.
  final Future<void> Function(List<String> arguments)? onRun;

  @override
  Future<CompilerStatus> status() async =>
      CompilerStatus(ready: ready, enginePath: '/motor', problem: problem);

  @override
  Future<List<BuildableProfile>> profilesFor(String unitPath) async => profiles;

  /// Lo que el motor diría que hay compilado. Por defecto, nada: es el
  /// estado de una unidad recién abierta.
  List<ExistingOutput> existing = const [];

  /// Las rutas que se preguntó si estaban viejas, y la respuesta.
  final Map<String, bool> staleness = {};

  @override
  Future<List<ExistingOutput>> outputsFor(String unitPath) async => existing;

  /// Si el índice está viejo, y por qué.
  ({bool stale, String? reason}) staleIndex = (stale: false, reason: null);

  int reindexCalls = 0;

  @override
  Future<({bool stale, String? reason})> indexStale() async => staleIndex;

  /// Las plantillas que declara una carpeta.
  ///
  /// Vacía por defecto: la carpeta del programa es de quien la use, y una
  /// pantalla que se prueba no tiene ninguna guardada ahí. Los tests que van
  /// de eso la ponen.
  List<OutputTemplate> storedTemplates = const [];

  @override
  Future<List<OutputTemplate>> templatesIn(String directory) async =>
      storedTemplates;

  @override
  Future<String> reindex() async {
    reindexCalls += 1;
    commands.add(const ['index']);
    if (failWith != null) throw failWith!;
    // Regenerar deja de estar viejo, como el de verdad.
    staleIndex = (stale: false, reason: null);
    return 'generated';
  }

  /// Lo que la biblioteca cree que hay compilado.
  Map<String, List<ExistingOutput>> built = const {};

  int builtCalls = 0;

  @override
  Future<Map<String, List<ExistingOutput>>> builtOutputs() async {
    builtCalls += 1;
    if (failWith != null) throw failWith!;
    return built;
  }

  @override
  Future<bool> isStale({required String pdf, required String unitPath}) async =>
      staleness[pdf] ?? false;

  /// Lo que el motor «escribió» mientras compilaba.
  ///
  /// Una lista y no un texto: es lo que la consola recibe línea a línea, y un
  /// test de la consola tiene que poder decir qué líneas llegaron y en qué
  /// orden.
  List<String> output = const ['=== fake', 'compilando', '--- ok'];

  /// Las líneas que se entregaron, para comprobar que se entregaron.
  final List<String> streamed = [];

  void _stream(void Function(String line)? onOutput) {
    if (onOutput == null) return;
    for (final line in output) {
      streamed.add(line);
      onOutput(line);
    }
  }

  @override
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    calls.add((profiles: profiles, languages: languages));
    _stream(onOutput);
    if (failWith != null) throw failWith!;
    return outputs ??
        [
          for (final id in profiles)
            for (final language in languages)
              CompileOutput(
                profile: id,
                language: language,
                ok: true,
                pdf: '/salida/$id-$language.pdf',
                pages: id == 'slides' ? 5 : 1,
                seconds: 3.4,
              ),
        ];
  }

  /// Las órdenes que se le pidió lanzar al motor, y qué contestó.
  final List<List<String>> commands = [];
  final Map<String, String> answers = {};

  @override
  Future<String> run(
    List<String> arguments, {
    bool allowFailure = false,
    void Function(String line)? onOutput,
  }) async {
    commands.add(arguments);
    _stream(onOutput);
    if (failWith != null) throw failWith!;
    // Todo menos una previsualización, como el motor: `remove` sin
    // `--apply` cuenta lo que se llevaría y no toca nada, y que un test
    // pueda coger lo contrario es la razón de esta condición.
    final preview =
        arguments.first == 'remove' && !arguments.contains('--apply');
    if (onRun != null && !preview) await onRun!(arguments);
    // Se busca por la primera coincidencia de las claves puestas: los tests
    // dicen «lo que conteste a `remove course`» y no la línea entera.
    for (final entry in answers.entries) {
      if (arguments.join(' ').contains(entry.key)) return entry.value;
    }
    return '';
  }

  /// Las versiones que un documento admite, y lo que se compiló de él.
  List<BuildableProfile> documentProfileList = const [
    BuildableProfile(
      id: 'slides',
      label: 'Diapositivas',
      family: 'slides',
      byDefault: true,
    ),
    BuildableProfile(id: 'book', label: 'Libro', family: 'notes'),
    BuildableProfile(id: 'notes', label: 'Apuntes', family: 'notes'),
  ];

  final List<({String document, List<String> profiles, List<String> languages})>
  documentCalls = [];

  /// Lo borrado, para que un test pueda mirarlo.
  final List<String> deleted = [];

  @override
  Future<int> deleteOutputs(List<String> pdfs) async {
    deleted.addAll(pdfs);
    // Como el de verdad: lo borrado deja de estar en «ya compiladas».
    existing = [
      for (final output in existing)
        if (!pdfs.contains(output.pdf)) output,
    ];
    return pdfs.length;
  }

  @override
  Future<List<BuildableProfile>> documentProfiles(String document) async =>
      documentProfileList;

  /// Lo que hay compilado de cada documento, para las pantallas que ofrecen
  /// abrir el PDF sin compilar.
  Map<String, List<ExistingOutput>> documentOutputList = const {};

  @override
  Future<Map<String, List<ExistingOutput>>> documentOutputs(
    String where,
  ) async => documentOutputList;

  /// Lo que se pidió exportar, para poder comprobarlo.
  final List<
    ({String where, String to, List<String> languages, List<String> documents})
  >
  exports = [];

  ExportResult exportResult = const ExportResult(
    copied: [],
    missing: [],
    to: '/tmp/export',
  );

  @override
  Future<ExportResult> exportCourse({
    required String where,
    required String to,
    List<String> languages = const [],
    List<String> documents = const [],
  }) async {
    exports.add((
      where: where,
      to: to,
      languages: languages,
      documents: documents,
    ));
    return exportResult;
  }

  @override
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    documentCalls.add((
      document: document,
      profiles: profiles,
      languages: languages,
    ));
    _stream(onOutput);
    if (failWith != null) throw failWith!;
    return outputs ??
        [
          for (final id in profiles)
            for (final language in languages)
              CompileOutput(
                profile: id,
                language: language,
                ok: true,
                pdf: '/salida/$document-$id-$language.pdf',
                pages: id == 'slides' ? 24 : 12,
                seconds: 9.1,
              ),
        ];
  }

  @override
  Future<void> open(String pdf) async => opened.add(pdf);

  @override
  Future<void> reveal(String pdf) async => revealed.add(pdf);
}

/// Un clon que no toca el disco, para los tests de pantalla.
///
/// Existe por una razón muy concreta: `testWidgets` corre con un reloj
/// falso, y esperar un `Process.run` de verdad ahí dentro **cuelga el test**.
/// Que un commit sea un commit se prueba contra git de verdad en
/// `course_admin_test.dart` y `local_clone_test.dart`; lo que se prueba
/// desde la pantalla es otra cosa --qué se le pide y qué se enseña-- y para
/// eso basta con recordar la petición.
class FakeClone implements LocalClone {
  FakeClone({
    this.changed = true,
    this.behind = 0,
    this.ahead = 0,
    this.dirty = const [],
    this.failFetch = false,
  });

  /// Commits que hay en el remoto y no aquí.
  final int behind;

  /// Y los que hay aquí y no en el remoto, con los ficheros escritos y sin
  /// confirmar: es lo que hace que un clon tenga algo que enviar.
  final int ahead;
  final List<String> dirty;

  /// Sin red, sin token o sin remoto: preguntar falla y lo local sigue
  /// valiendo.
  final bool failFetch;

  int pulls = 0;

  /// Si el motor cambió algo. False es el caso de borrar lo que ya no
  /// estaba: el motor termina bien, no hay commit, y la pantalla lo dice.
  final bool changed;

  final List<({List<String> paths, String message, String author, bool push})>
  commits = [];

  @override
  String get directory => '/clon';

  /// El historial que este clon dice tener, por ruta.
  final Map<String, List<FileCommit>> log = {};

  /// Lo que cada commit hizo, por `sha`.
  final Map<String, FileDiff> diffs = {};

  /// El contenido del fichero en cada commit, por `sha`. Es lo que se
  /// enseña cuando el commit no cambió el contenido y por tanto no hay diff.
  final Map<String, String> contents = {};

  /// Lo que se preguntó, para comprobar que se preguntó por lo que tocaba.
  final List<String> historyAsked = [];
  final List<String> diffAsked = [];

  /// Las líneas de contexto que se pidieron en cada `diffOf`.
  final List<int> contextAsked = [];

  @override
  Future<List<FileCommit>> history(String path, {int limit = 60}) async {
    historyAsked.add(path);
    return (log[path] ?? const []).take(limit).toList();
  }

  @override
  Future<FileDiff> diffOf({
    required String sha,
    required String path,
    int context = 3,
  }) async {
    diffAsked.add('$sha:$path');
    contextAsked.add(context);
    return diffs[sha] ?? const FileDiff(hunks: []);
  }

  @override
  Future<String?> fileAt({required String sha, required String path}) async =>
      contents[sha];

  @override
  Future<bool> commitPaths({
    required List<String> paths,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('[main abc1234] $message');
    commits.add((
      paths: paths,
      message: message,
      author: '$authorName <$authorEmail>',
      push: push,
    ));
    return changed;
  }

  @override
  Future<({String name, String email})?> configuredAuthor() async =>
      (name: 'Javier', email: 'javier@uv.es');

  @override
  Future<String?> remoteUrl() async => 'https://github.com/x/y.git';

  @override
  Future<CloneStatus> status() async => CloneStatus(
    directory: '/clon',
    branch: 'main',
    head: 'abc1234',
    ahead: ahead,
    behind: behind,
    dirtyPaths: dirty,
  );

  @override
  Future<bool> looksRight({
    required String owner,
    required String repo,
  }) async => true;

  @override
  Future<({String text, String sha})> readFile(String path) async =>
      (text: '', sha: 'x');

  @override
  Future<String> commitFile({
    required String path,
    required String text,
    required String expectedSha,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
  }) async {
    fileCommits.add((path: path, message: message, pushed: push));
    return 'x';
  }

  /// Lo que se ha guardado **sin confirmar**, para poder mirarlo en un test.
  final List<({String path, String text})> writes = [];

  /// Y los commits de un fichero suelto, con si se enviaron. Aparte de
  /// [commits], que son los de una operación sobre varias rutas.
  final List<({String path, String message, bool pushed})> fileCommits = [];

  @override
  Future<String> writeFile({
    required String path,
    required String text,
    required String expectedSha,
  }) async {
    writes.add((path: path, text: text));
    return 'x';
  }

  @override
  Future<void> setAuthor({required String name, required String email}) async {}

  int fetches = 0;

  @override
  Future<void> fetch({required String token}) async {
    fetches += 1;
    if (failFetch) throw const CloneException('sin red');
  }

  @override
  Future<void> pull({
    required String token,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('Already up to date.');
    pulls += 1;
  }

  @override
  Future<void> push({
    required String token,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('Everything up-to-date');
  }

  // -- Congelaciones -------------------------------------------------------
  //
  // Lo mismo que arriba: lo que se prueba desde una pantalla es qué se le
  // pide a git y qué se enseña con la respuesta. Que un worktree sea un
  // worktree se prueba contra git de verdad en `freeze_git_test.dart`.

  /// El commit en el que dice estar, y los que dice tener.
  String at = 'abc1234abc1234abc1234abc1234abc1234abc12';
  Set<String> commitsHere = {};
  bool shallow = false;

  /// Lo que se ha pedido traer, comparar, restaurar y abrir.
  final List<String> fetched = [];
  final List<String> opened = [];
  final List<String> removedTrees = [];
  final List<({String from, String to, List<String> paths})> compared = [];
  final List<({String sha, List<String> paths})> restored = [];

  /// Lo que este clon dice que cambió entre dos commits.
  List<TreeChange> changes = const [];

  /// Y el diff de cada fichero, por ruta.
  final Map<String, FileDiff> between = {};

  @override
  Future<String> head() async => at;

  @override
  Future<bool> hasCommit(String sha) async => commitsHere.contains(sha);

  @override
  Future<bool> isShallow() async => shallow;

  @override
  Future<void> fetchCommit(
    String sha, {
    required String token,
    void Function(FetchDepth step) onStep = _noStep,
  }) async {
    fetched.add(sha);
    onStep(FetchDepth.justTheCommit);
    commitsHere.add(sha);
  }

  static void _noStep(FetchDepth step) {}

  @override
  Future<Worktree> worktreeAt(String sha) async {
    opened.add(sha);
    return Worktree(
      directory: '/clon/.git/didacta-worktrees/$sha',
      commit: sha,
    );
  }

  @override
  Future<void> removeWorktree(String sha) async => removedTrees.add(sha);

  @override
  Future<List<Worktree>> worktrees() async => [
    for (final sha in opened)
      Worktree(directory: '/clon/.git/didacta-worktrees/$sha', commit: sha),
  ];

  @override
  Future<int> clearWorktrees() async {
    final count = opened.length;
    removedTrees.addAll(opened);
    opened.clear();
    return count;
  }

  @override
  Future<List<TreeChange>> changesBetween({
    required String from,
    required String to,
    List<String> paths = const [],
  }) async {
    compared.add((from: from, to: to, paths: paths));
    return changes;
  }

  @override
  Future<FileDiff> diffBetween({
    required String from,
    required String to,
    required String path,
    int context = 3,
  }) async => between[path] ?? const FileDiff(hunks: []);

  @override
  Future<List<String>> pathsAt({
    required String sha,
    String under = '',
  }) async => const [];

  @override
  Future<List<TreeChange>> previewRestore({
    required String sha,
    required List<String> paths,
  }) async => changes;

  @override
  Future<List<TreeChange>> restoreFrom({
    required String sha,
    required List<String> paths,
  }) async {
    restored.add((sha: sha, paths: paths));
    return changes;
  }
}

/// A session wired to a fake gateway, with no Firebase anywhere.
class FakeSession extends Session {
  /// El indentador propio y nada más: `latexindent` es un proceso de verdad
  /// y el reloj de una prueba de widgets es falso, así que esperarlo sería
  /// esperar para siempre.
  @override
  Future<String> tidyLatex(String text) async => indentLatex(text);

  FakeSession({
    required this.gatewayOverride,
    required Catalogue catalogue,
    this.compilerOverride,
    this.adminOverride,
    this.cloneOverride,
    this.toolchainOverride,
    this.onReload,
    this.reloadsForReal = false,
    Preferences? preferencesOverride,
    TranslationSecrets? translationSecretsOverride,
  }) : super(
         catalogueSource: StaticCatalogueSource(catalogue),
         tokenStore: StubStore(),
         preferences: preferencesOverride,
         // En memoria por defecto: un test que monta una pantalla no puede
         // ponerse a leer el llavero del sistema.
         translationSecrets:
             translationSecretsOverride ?? MemoryTranslationSecrets(),
       );

  /// Sin red y sin preguntar: quien monta una pantalla ya ha entrado.
  @override
  Future<GitHubUser> whoIs(String token) async => testUser;

  final ContentGateway gatewayOverride;

  /// Null means "nothing to compile with", which is a state the screen has to
  /// handle: the web, and a desktop with no engine configured.
  final Compiler? compilerOverride;

  /// Null es la web: sin clon y sin motor no se pueden administrar
  /// asignaturas, y la pantalla tiene que decirlo en lugar de ofrecer
  /// botones que no funcionan.
  final CourseAdmin? adminOverride;

  /// El clon, sin git detrás.
  final FakeClone? cloneOverride;

  /// Las herramientas de la máquina, sin máquina.
  ///
  /// Con todo puesto por defecto y no vacío: casi ninguna pantalla que se
  /// prueba va de esto, y lo que tienen que enseñar es la aplicación
  /// funcionando. Los tests de la lista de herramientas son los que piden
  /// una a la que le falta algo, y lo dicen.
  final Toolchain? toolchainOverride;

  @override
  Toolchain toolchain() =>
      toolchainOverride ?? FakeToolchain(present: ToolId.values.toSet());

  @override
  LocalClone cloneAt(String directory) =>
      cloneOverride ?? super.cloneAt(directory);

  /// El clon, sin necesitar un espacio de trabajo ni tocar el disco.
  ///
  /// Sin esto, una pantalla que pide el clon obliga al test a montar un
  /// repositorio de verdad: `useClone` acaba buscando el motor en el disco, y
  /// un `Process.run` dentro de un test de widgets --donde el reloj es falso--
  /// no termina nunca.
  @override
  LocalClone? cloneFor(String? repo) => cloneOverride ?? super.cloneFor(repo);

  /// Recargar el catálogo va a la red, que en un test no está. Cuenta las
  /// veces: crear una asignatura y no recargar es el fallo de que la
  /// pantalla no enseñe lo que acaba de crear.
  final void Function()? onReload;

  /// Si recarga **de verdad** en lugar de solo contar.
  ///
  /// Casi ningún test quiere lo primero: una pantalla se prueba contra un
  /// catálogo que no se mueve. Lo quiere el test de la recarga, porque lo que
  /// hay que fijar ahí es justamente lo que hace `reloadCatalogue` -- pedirle
  /// al motor que ponga el índice al día antes de leerlo.
  final bool reloadsForReal;

  int reloads = 0;

  @override
  Future<void> reloadCatalogue() async {
    reloads += 1;
    onReload?.call();
    if (reloadsForReal) await super.reloadCatalogue();
  }

  @override
  CourseAdmin? admin({String? repo}) => adminOverride;

  @override
  ContentGateway get gateway => gatewayOverride;

  /// La misma para todos los repositorios.
  ///
  /// Un test que monta una pantalla con documentos de dos repositorios no
  /// está probando el reparto de pasarelas --eso es `multi_repo_test`, contra
  /// git de verdad-- sino lo que la pantalla enseña. Sin esto, pedir la de un
  /// repositorio que no está en el espacio de trabajo devuelve una pasarela
  /// sin configurar y la pantalla se queda en el error de carga.
  /// Salvo mirando una versión congelada, que es de solo lectura y va por la
  /// suya: esa negativa es lo que se está probando y sustituirla la borraría.
  @override
  ContentGateway gatewayFor(String? repo) =>
      frozen == null ? gatewayOverride : super.gatewayFor(repo);

  @override
  Compiler? compiler({String? repo}) => compilerOverride;

  @override
  bool get canCompile => true;
}

/// Nothing in these tests reaches Firebase or a keychain.
///
/// Possible because `Session` takes an [AuthSession] and a [SecretStore]
/// rather than the concrete Firebase and keychain classes -- which is the
/// point of those interfaces existing.
/// El llavero, en memoria.
///
/// Con un token dentro por defecto, y eso es deliberado: **sin sesión Didacta
/// no se abre**, así que una pantalla que se prueba es siempre una pantalla de
/// alguien que entró. Los tests de la puerta son los que piden un llavero
/// vacío, y lo dicen: `StubStore(token: null)`.
class StubStore implements SecretStore {
  StubStore({this.token = 'gho_de_prueba'});

  String? token;

  @override
  bool get canStoreSafely => true;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Quién contesta GitHub en un test.
const GitHubUser testUser = GitHubUser(
  login: 'profe',
  name: 'Profe de Prueba',
  email: 'profe@uv.es',
);

/// Una sesión de verdad que no pregunta a GitHub quién eres.
///
/// Para los tests que montan la aplicación entera: todo lo demás de `Session`
/// es el de producción, y lo único que se sustituye es la única parte que
/// necesita internet.
class LocalSession extends Session {
  LocalSession({
    required super.catalogueSource,
    required super.tokenStore,
    super.preferences,
    this.who = testUser,
  });

  /// Null es «GitHub no contesta», para probar el arranque sin red.
  final GitHubUser? who;

  /// A qué repositorios llega esta cuenta.
  ///
  /// Null --el valor por defecto-- es «a todos»: casi ningún test va de
  /// permisos, y los que sí lo dicen poniendo la lista.
  Set<String>? reaches;

  /// Lo que se preguntó a GitHub, para comprobar que se preguntó.
  final List<String> asked = [];

  @override
  Future<GitHubUser> whoIs(String token) async {
    final found = who;
    if (found == null) throw const SocketException('sin red');
    return found;
  }

  @override
  Future<GitHubRepo?> accessTo(String owner, String name) async {
    asked.add('$owner/$name');
    final allowed = reaches;
    if (allowed != null && !allowed.contains('$owner/$name')) return null;
    return GitHubRepo(
      owner: owner,
      name: name,
      defaultBranch: 'main',
      private: true,
      canWrite: true,
    );
  }
}

/// Las herramientas de la máquina, sin máquina.
///
/// Existe porque comprobar de verdad lanza `git --version` y compañía, e
/// instalar de verdad descarga un instalador de CTAN: las dos cosas están
/// fuera del alcance de un test de widgets, donde el reloj es falso y un
/// proceso de verdad no termina nunca.
///
/// Lo que sí reproduce son los tres finales que la interfaz tiene que saber
/// contar: instalar y que aparezca, instalar y que falle, e **instalar sin
/// error y que siga sin aparecer**, que es el caso real de un instalador que
/// deja el programa en un sitio que no es ninguno de los de siempre.
class FakeToolchain implements Toolchain {
  FakeToolchain({
    this.host = Host.macos,
    Set<ToolId> present = const {},
    this.failure,
    this.appears = true,
    this.available = const {'brew'},
  }) : _present = {...present};

  @override
  final Host host;

  final Set<ToolId> _present;

  /// Qué hay instalado ahora mismo. Cambia cuando una instalación sale bien.
  Set<ToolId> get present => _present;

  /// Con qué falla [install], si tiene que fallar.
  final ToolInstallException? failure;

  /// Si lo instalado aparece después. Falso es el instalador que dice que sí
  /// y deja el programa donde Didacta no mira.
  final bool appears;

  /// Qué gestores de paquetes tiene esta máquina de mentira.
  final Set<String> available;

  /// Los planes que se han llegado a ejecutar, en orden.
  final List<InstallPlan> installed = [];

  /// A qué herramienta pertenece cada instalación pedida.
  final List<ToolId> asked = [];

  @override
  Future<ToolState> inspect(ToolId id) async {
    final tool = toolById(id);
    if (_present.contains(id)) {
      return ToolState(
        tool: tool,
        path: '/de/mentira/${tool.executables.first}',
        version: '1.2.3',
        searched: const ['/de/mentira'],
      );
    }
    return ToolState(tool: tool, searched: const ['/de/mentira']);
  }

  @override
  Future<List<ToolState>> inspectAll() async => [
    for (final tool in didactaTools) await inspect(tool.id),
  ];

  @override
  Future<InstallPlan> choose(List<InstallPlan> candidates) async {
    for (final plan in candidates) {
      final needs = plan.needs;
      if (needs == null || available.contains(needs)) return plan;
    }
    return candidates.last;
  }

  @override
  Future<void> install(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async {
    installed.add(plan);
    onOutput?.call('instalando…');
    final thrown = failure;
    if (thrown != null) throw thrown;
    if (!appears) return;
    // Qué herramienta era se deduce del plan, que es lo único que llega
    // aquí: cada uno aparece en la lista de una sola.
    for (final tool in didactaTools) {
      if (plansFor(tool.id, host).any((other) => other.label == plan.label)) {
        _present.add(tool.id);
      }
    }
  }
}
