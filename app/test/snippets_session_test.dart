/// Guardar snippets: qué se escribe en cada repositorio.
///
/// La lógica de qué ofrece la barra está probada aparte; aquí se prueba lo
/// que cae en el `snippets.yaml` de dos repositorios de verdad distintos
/// --una pasarela cada uno--, que es donde un error se lleva el trabajo de
/// otra persona: un repositorio sin fichero que al añadir uno propio pierde
/// los de serie, un «quitar» que escribe un fichero donde no lo había, un
/// igualar que pisa al que no discrepaba.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/latex_snippets.dart';
import 'package:didacta_app/model/snippets_file.dart';
import 'package:didacta_app/model/tex_wrap.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

/// Una sesión con dos repositorios, cada uno con su pasarela.
class TwoRepos extends FakeSession {
  TwoRepos(this.gateways, Catalogue catalogue)
    : super(gatewayOverride: gateways.values.first, catalogue: catalogue);

  final Map<String, FakeGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) => gateways[repo]!;

  @override
  List<String> get snippetRepos => gateways.keys.toList();
}

Catalogue catalogueOf(Map<String, List<SnippetDeclaration>?> snippets) =>
    Catalogue(
      name: 't',
      languages: const ['es'],
      defaultLanguage: 'es',
      contentHash: '',
      units: const [],
      courses: const [],
      profiles: const [],
      errors: const [],
      snippets: snippets,
    );

const resumen = LatexSnippet(
  id: 'resumen',
  label: 'Resumen',
  group: 'Teoría',
  environment: 'resumen',
  definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaThm}',
  sample: 'Lo esencial.',
);

void main() {
  late FakeGateway teoria;
  late FakeGateway problemas;
  late TwoRepos session;

  Future<void> start(Map<String, List<SnippetDeclaration>?> declared) async {
    final catalogue = catalogueOf(declared);
    session = TwoRepos({'teoria': teoria, 'problemas': problemas}, catalogue);
    await session.primeForTest(catalogue);
  }

  setUp(() {
    teoria = FakeGateway(files: {});
    problemas = FakeGateway(files: {});
  });

  test('añadir uno propio a un repositorio sin fichero conserva los de '
      'serie', () async {
    await start({'teoria': null, 'problemas': null});
    final written = await session.saveSnippet(resumen, repos: {'teoria'});
    expect(written, 1);

    final text = teoria.files[Session.snippetsPath]!;
    final ids = SnippetsFile(text).ids;
    expect(ids, containsAll([for (final w in didactaWrappers) w.id]));
    expect(ids, contains('resumen'));
    expect(text, contains(r'\DidactaNewTheorem{resumen}'));
    // Y el otro repositorio ni se toca: no tenía fichero y sigue sin él.
    expect(problemas.files.containsKey(Session.snippetsPath), isFalse);
  });

  test('guardarlo en los dos lo escribe igual en los dos', () async {
    await start({'teoria': null, 'problemas': null});
    await session.saveSnippet(resumen, repos: {'teoria', 'problemas'});
    String entry(FakeGateway gateway) {
      final text = gateway.files[Session.snippetsPath]!;
      return text.substring(text.indexOf('- id: resumen'));
    }

    expect(entry(teoria), entry(problemas));
  });

  test('quitarlo de uno lo quita solo de ese', () async {
    teoria = FakeGateway(
      files: {
        Session.snippetsPath: 'snippets:\n  - id: theorem\n  - id: resumen\n',
      },
    );
    problemas = FakeGateway(
      files: {Session.snippetsPath: 'snippets:\n  - id: resumen\n'},
    );
    await start({
      'teoria': const [
        SnippetDeclaration(id: 'theorem'),
        SnippetDeclaration(id: 'resumen', environment: 'resumen'),
      ],
      'problemas': const [
        SnippetDeclaration(id: 'resumen', environment: 'resumen'),
      ],
    });
    await session.saveSnippet(resumen, repos: {'teoria'});
    expect(SnippetsFile(problemas.files[Session.snippetsPath]!).ids, isEmpty);
    expect(SnippetsFile(teoria.files[Session.snippetsPath]!).ids, [
      'theorem',
      'resumen',
    ]);
  });

  test('quitar uno propio no escribe un fichero donde no lo había', () async {
    teoria = FakeGateway(
      files: {Session.snippetsPath: 'snippets:\n  - id: resumen\n'},
    );
    await start({
      'teoria': const [
        SnippetDeclaration(id: 'resumen', environment: 'resumen'),
      ],
      'problemas': null,
    });
    await session.removeSnippet(resumen);
    expect(problemas.files.containsKey(Session.snippetsPath), isFalse);
    expect(teoria.files[Session.snippetsPath], contains('snippets: []'));
  });

  test('quitar uno de serie de un repositorio sin fichero lo escribe con el '
      'resto', () async {
    await start({'teoria': null, 'problemas': null});
    final theorem = session
        .snippetsIn('teoria')
        .firstWhere((s) => s.id == 'theorem');
    await session.saveSnippet(theorem, repos: {'teoria'});
    expect(teoria.files.containsKey(Session.snippetsPath), isFalse);
    final ids = SnippetsFile(problemas.files[Session.snippetsPath]!).ids;
    expect(ids, isNot(contains('theorem')));
    expect(ids.length, didactaWrappers.length - 1);
  });

  test('ordenar escribe solo donde el orden cambia', () async {
    await start({
      'teoria': const [
        SnippetDeclaration(id: 'theorem'),
        SnippetDeclaration(id: 'proof'),
      ],
      'problemas': const [SnippetDeclaration(id: 'exercise')],
    });
    teoria.files[Session.snippetsPath] =
        'snippets:\n  - id: theorem\n  - id: proof\n';
    problemas.files[Session.snippetsPath] = 'snippets:\n  - id: exercise\n';
    final written = await session.reorderSnippets([
      'exercise',
      'proof',
      'theorem',
    ]);
    expect(written, 1);
    expect(SnippetsFile(teoria.files[Session.snippetsPath]!).ids, [
      'proof',
      'theorem',
    ]);
    expect(problemas.commits, isEmpty);
  });

  test(
    'igualar copia lo de un repositorio en los demás que lo tienen',
    () async {
      const theirs = SnippetDeclaration(
        id: 'resumen',
        environment: 'resumen',
        label: 'Resumen',
        definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaDefn}',
      );
      teoria.files[Session.snippetsPath] = 'snippets:\n  - id: resumen\n';
      problemas.files[Session.snippetsPath] = 'snippets:\n  - id: resumen\n';
      await start({
        'teoria': [resumen.toDeclaration()],
        'problemas': const [theirs],
      });
      expect(session.snippetConflicts.single.id, 'resumen');
      await session.useSnippetFrom(id: 'resumen', repo: 'teoria');
      expect(problemas.files[Session.snippetsPath], contains('didactaThm'));
      expect(teoria.commits, isEmpty);
    },
  );

  test('en un repositorio de solo lectura no se escribe', () async {
    problemas = FakeGateway(writable: false, files: {});
    await start({'teoria': null, 'problemas': null});
    final written = await session.saveSnippet(
      resumen,
      repos: {'teoria', 'problemas'},
    );
    expect(written, 1);
    expect(problemas.files, isEmpty);
  });
}
