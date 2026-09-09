/// The catalogue, gateway and session the widget tests run against.
///
/// Shared rather than copied into each test file, because the point of these
/// fixtures is that every screen is exercised against *the same* awkward
/// data: a unit with two missing translations, a composition with a broken
/// reference, a document with no profiles. Data that is too tidy proves
/// nothing.
library;

import 'package:didacta_app/data/auth.dart';
import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';

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
}) =>
    {
      'id': path.split('/').skip(1).join('.'),
      'path': path,
      'area': area,
      'kind': kind,
      'category': category,
      'topic': topic,
      'tags': const ['norma', 'banach'],
      'title': title,
      'reference': 'es',
      'languages': languages ??
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
        kind: 'exercise',
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
              'profiles': const ['handout', 'slides'],
              'unitRefs': const [
                'analysis/normed/definition',
                'analysis/normed/banach',
                // Deliberately broken: a composition that silently skips what
                // is missing looks complete and compiles short.
                'analysis/normed/no-existe',
              ],
            },
            {
              'id': 'hoja-1',
              'kind': 'problems',
              'language': 'es',
              'title': const {'es': 'Hoja 1'},
              'profiles': const <String>[],
              'unitRefs': const ['analysis/normed/exercises'],
            },
          ],
        },
      },
    };

Catalogue catalogueWith(
  List<Map<String, dynamic>> units, {
  List<Map<String, dynamic>>? courses,
}) =>
    Catalogue.fromIndex(
      manifest: {
        'schemaVersion': supportedSchemaVersion,
        'name': 'Prueba',
        'languages': const ['es', 'va', 'en'],
        'defaultLanguage': 'es',
        'contentHash': 'abc',
        'profiles': const [],
        'errors': const <String>[],
      },
      units: {'schemaVersion': supportedSchemaVersion, 'units': units},
      courses: {
        'schemaVersion': supportedSchemaVersion,
        'courses': courses ?? [courseJson()],
      },
    );

/// A gateway that records what it was asked to do.
class FakeGateway extends ContentGateway {
  FakeGateway({
    this.writable = true,
    this.failWith,
    Map<String, String>? files,
  }) : files = files ??
            {
              '$unitPath/es.tex': 'El contenido original en castellano.',
              '$unitPath/unit.yaml': unitYaml,
            };

  final bool writable;
  final ContentException? failWith;
  final Map<String, String> files;

  final List<({String path, String text, String message, String sha})> commits =
      [];

  @override
  GatewayKind get kind => GatewayKind.direct;

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
  Future<String> commit({
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
}

/// A session wired to a fake gateway, with no Firebase anywhere.
class FakeSession extends Session {
  FakeSession({required this.gatewayOverride, required Catalogue catalogue})
      : super(
          catalogueSource: StaticCatalogueSource(catalogue),
          auth: StubAuth(),
          tokenStore: StubStore(),
          apiBase: '',
          contentOwner: 'franjfal',
          contentRepo: 'didacta_db',
          contentBranch: 'main',
        );

  final ContentGateway gatewayOverride;

  @override
  ContentGateway get gateway => gatewayOverride;
}

/// Nothing in these tests reaches Firebase or a keychain.
///
/// Possible because `Session` takes an [AuthSession] and a [SecretStore]
/// rather than the concrete Firebase and keychain classes -- which is the
/// point of those interfaces existing.
class StubAuth implements AuthSession {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  SignedInUser? get user =>
      const SignedInUser(email: 'javier@uv.es', emailVerified: true);

  @override
  bool get signedIn => true;

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signInWithPassword(String email, String password) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> createAccount(String email, String password) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> resendVerification() async {}
}

class StubStore implements SecretStore {
  @override
  bool get canStoreSafely => true;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}
}
