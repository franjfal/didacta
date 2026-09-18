/// Las plantillas de compilación: decidir qué PDF sale de cada cosa.
///
/// Las quince salidas de Didacta estaban escritas en su propio LaTeX, así que
/// cambiar el margen de los apuntes era editar el programa. Una plantilla es
/// lo mismo --clase de documento, opciones, ejes-- declarado en el
/// repositorio, con un preámbulo propio al lado.
///
/// Lo que fija este fichero son las tres reglas de las que depende que esto no
/// pueda romper nada:
///
/// * un repositorio que no declara ninguna compila con las de serie;
/// * una lista vacía --en un bloque, en una lección, en un documento-- quiere
///   decir «lo que toque», nunca «nada»: si significara «nada», declarar un
///   bloque dejaría su material sin salidas y el botón de compilar no haría
///   nada sin decir por qué;
/// * apagar una plantilla la deja declarada, con su preámbulo, y fuera de lo
///   que se compila.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/model/taxonomy_file.dart';
import 'package:didacta_app/model/templates_file.dart';

import 'fixture.dart';

const String templatesYaml = '''
# Las plantillas de compilación de este repositorio.
#
# El id no se toca nunca: es lo que guardan los bloques.

templates:
  - id: slides
    title:
      es: Diapositivas
      # TODO: en
    class: beamer
    options: "10pt,notheorems"
    axes: {medium: slides, pauses: "on"}

  - id: notes
    title:
      es: Apuntes
    class: article
    options: "12pt,oneside"
    axes: {medium: document, detail: full}
''';

Map<String, dynamic> templateJson(
  String id, {
  String title = '',
  String documentClass = 'article',
  String options = '',
  bool active = true,
  String label = '',
}) => {
  'id': id,
  if (title.isNotEmpty) 'title': {'es': title},
  'label': label,
  'family': 'notes',
  'reveals': 'statements',
  'documentClass': documentClass,
  'classOptions': options,
  'axes': const <String, String>{},
  'active': active,
  'hasPreamble': false,
};

Map<String, dynamic> blockJson(
  String id, {
  String title = 'Teoría',
  List<String> templates = const [],
}) => {
  'id': id,
  'title': {'es': title},
  'templates': templates,
};

Map<String, dynamic> lesson(
  String block, {
  String path = 'content/a/b/c',
  List<String> templates = const [],
}) => {
  'id': path.replaceAll('/', '.'),
  'path': path,
  'area': 'content',
  'kind': 'theory',
  'block': block,
  'templates': templates,
  'category': 'a',
  'topic': 'b',
  'title': const {'es': 'Una lección'},
  'reference': 'es',
  'languages': const {
    'es': {'status': 'source'},
  },
  'usedBy': const <Map<String, String>>[],
};

Map<String, dynamic> courseWith(List<Map<String, dynamic>> documents) => {
  'id': 'am-iii',
  'title': const {'es': 'Análisis Matemático III'},
  'language': 'es',
  'years': {
    '2025-2026': {
      'year': '2025-2026',
      'language': 'es',
      'documents': documents,
    },
  },
};

Map<String, dynamic> documentJson({
  String id = 'tema-1',
  List<String> references = const ['a/b/c'],
  List<String> profiles = const [],
}) => {
  'id': id,
  'kind': 'theory',
  'language': 'es',
  'title': {'es': 'Tema 1'},
  'profiles': profiles,
  'unitRefs': references,
};

Catalogue repoWith({
  required String repo,
  List<Map<String, dynamic>> templates = const [],
  List<Map<String, dynamic>> blocks = const [],
  List<Map<String, dynamic>> units = const [],
  List<Map<String, dynamic>> courses = const [],
  List<Map<String, dynamic>> profiles = const [],
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': const ['es', 'va', 'en'],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    'taxonomy': {'blocks': blocks},
    'templates': templates,
    'profiles': profiles,
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': units},
  courses: {'schemaVersion': supportedSchemaVersion, 'courses': courses},
  repo: repo,
);

void main() {
  group('editar templates.yaml', () {
    test('lee lo declarado, en el orden del fichero', () {
      final file = TemplatesFile(templatesYaml);
      expect(file.ids, ['slides', 'notes']);
      expect(file.titlesOf('slides'), {'es': 'Diapositivas'});
      expect(file.fieldOf('slides', 'class'), 'beamer');
      expect(file.fieldOf('notes', 'options'), '12pt,oneside');
    });

    test('renombrar deja lo demás donde estaba', () {
      final file = TemplatesFile(templatesYaml)
        ..setTitles('notes', {'es': 'Apuntes largos', 'en': ''});
      expect(file.titlesOf('notes'), {'es': 'Apuntes largos'});
      expect(file.fieldOf('notes', 'class'), 'article');
      expect(file.text, contains('# TODO: en'));
      expect(file.text, contains('El id no se toca nunca'));
    });

    test('una plantilla sin nombre se enseña por lo que hace', () {
      // Y por eso quitarle el nombre no se niega, a diferencia de un bloque:
      // «Diapositivas (sin pausas)» es un nombre de verdad, y lo deduce el
      // motor de los ejes.
      final file = TemplatesFile(templatesYaml)
        ..setTitles('slides', {'es': ''});
      expect(file.titlesOf('slides'), isEmpty);
      expect(file.ids, ['slides', 'notes']);
      expect(file.fieldOf('slides', 'class'), 'beamer');
    });

    test('apagar escribe la línea, y encender la quita', () {
      // Encendida es lo normal, y lo normal no se declara: un `active: true`
      // en cada plantilla sería ruido en quince declaraciones.
      final file = TemplatesFile(templatesYaml)..setActive('slides', false);
      expect(file.fieldOf('slides', 'active'), 'false');
      file.setActive('slides', true);
      expect(file.fieldOf('slides', 'active'), isNull);
      expect(file.ids, ['slides', 'notes']);
    });

    test('cambiar la clase y los ejes', () {
      final file = TemplatesFile(templatesYaml)
        ..setField('notes', 'class', 'book')
        ..setAxes('notes', {'medium': 'document', 'pauses': 'off'});
      expect(file.fieldOf('notes', 'class'), 'book');
      // `on` y `off` entre comillas: en YAML son booleanos.
      expect(file.text, contains('axes: {medium: document, pauses: "off"}'));
    });

    test('declarar una nueva', () {
      final file = TemplatesFile(templatesYaml)
        ..add(
          id: 'apuntes-a5',
          titles: {'es': 'De bolsillo'},
          documentClass: 'article',
          classOptions: '10pt,a5paper',
          axes: {'medium': 'document'},
          languages: ['es', 'va'],
        );
      expect(file.ids, ['slides', 'notes', 'apuntes-a5']);
      expect(file.fieldOf('apuntes-a5', 'options'), '10pt,a5paper');
      expect(file.text, contains('# TODO: va'));
    });

    test('y sin clase de documento se niega', () {
      // Una plantilla sin clase no se puede compilar, y dejar que se declare
      // mueve el fallo a la primera vez que alguien pulse compilar.
      expect(
        () => TemplatesFile(
          templatesYaml,
        ).add(id: 'rota', titles: {'es': 'Rota'}, documentClass: '  '),
        throwsA(isA<TemplatesException>()),
      );
    });

    test('quitar una no toca a las demás', () {
      final file = TemplatesFile(templatesYaml)..remove('slides');
      expect(file.ids, ['notes']);
      expect(file.fieldOf('notes', 'class'), 'article');
    });

    test('la última deja una lista vacía, no una clave colgando', () {
      final file = TemplatesFile(templatesYaml)
        ..remove('slides')
        ..remove('notes');
      expect(file.ids, isEmpty);
      expect(file.text, contains('templates: []'));
    });

    test('y en un fichero recién creado se puede declarar', () {
      final file = TemplatesFile(emptyTemplatesYaml)
        ..add(id: 'mias', titles: {}, documentClass: 'article');
      expect(file.ids, ['mias']);
    });
  });

  group('con qué se compila cada cosa', () {
    test('sin ninguna declarada, con las que trae el programa', () {
      // La caída que hace que un repositorio que todavía no declara ninguna
      // compile exactamente como antes.
      final catalogue = repoWith(
        repo: 'x/teoria',
        profiles: [
          {
            'id': 'slides',
            'label': 'Diapositivas',
            'family': 'slides',
            'documentClass': 'beamer',
          },
          {
            'id': 'notes',
            'label': 'Apuntes',
            'family': 'notes',
            'documentClass': 'article',
          },
        ],
      );
      expect(catalogue.templates, isEmpty);
      expect(catalogue.templatesInUse.map((t) => t.id), ['slides', 'notes']);
      expect(catalogue.templatesInUse.first.declared, isFalse);
      expect(catalogue.templatesInUse.first.title('es'), 'Diapositivas');
    });

    test('un bloque sin lista compila con todas las activas', () {
      // Vacía es «las que toquen» y no «ninguna»: declarar un bloque no puede
      // dejar su material sin salidas.
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('slides'), templateJson('notes')],
        blocks: [blockJson('teoria')],
      );
      expect(catalogue.templatesOfBlock('teoria'), ['slides', 'notes']);
    });

    test('y con lista, la suya', () {
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('slides'), templateJson('notes')],
        blocks: [
          blockJson('teoria', templates: ['notes']),
        ],
      );
      expect(catalogue.templatesOfBlock('teoria'), ['notes']);
    });

    test('una apagada no se compila aunque un bloque la nombre', () {
      // Es exactamente lo que significa apagarla, y el caso que se da: se
      // apaga la versión del profesor y todo lo que la nombraba deja de
      // sacarla, sin tener que repasar veinte bloques.
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [
          templateJson('slides'),
          templateJson('notes', active: false),
        ],
        blocks: [
          blockJson('teoria', templates: ['slides', 'notes']),
        ],
      );
      expect(catalogue.activeTemplates.map((t) => t.id), ['slides']);
      expect(catalogue.templatesOfBlock('teoria'), ['slides']);
    });

    test('una lección se aparta de su bloque cuando lo dice', () {
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('slides'), templateJson('notes')],
        blocks: [
          blockJson('teoria', templates: ['slides', 'notes']),
        ],
        units: [
          lesson('teoria'),
          lesson('teoria', path: 'content/a/b/d', templates: ['notes']),
        ],
      );
      expect(catalogue.templatesFor(catalogue.units.first), [
        'slides',
        'notes',
      ]);
      expect(catalogue.templatesFor(catalogue.units.last), ['notes']);
    });

    test('un documento hereda de los bloques de lo que compone', () {
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [
          templateJson('slides'),
          templateJson('notes'),
          templateJson('hoja'),
        ],
        blocks: [
          blockJson('teoria', templates: ['slides', 'notes']),
          blockJson('problemas', title: 'Problemas', templates: ['hoja']),
        ],
        units: [
          lesson('teoria'),
          lesson('problemas', path: 'content/a/b/d'),
        ],
        courses: [
          courseWith([
            documentJson(references: ['a/b/c', 'a/b/d']),
          ]),
        ],
      );
      final document =
          catalogue.courses.first.years.values.first.documents.first;
      // Los dos bloques, y en el orden de las plantillas para que dos
      // documentos del mismo curso no ofrezcan lo mismo en orden distinto.
      expect(catalogue.templatesForDocument(document), [
        'slides',
        'notes',
        'hoja',
      ]);
    });

    test('y se aparta cuando lo declara', () {
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('slides'), templateJson('notes')],
        blocks: [
          blockJson('teoria', templates: ['slides', 'notes']),
        ],
        units: [lesson('teoria')],
        courses: [
          courseWith([
            documentJson(profiles: ['notes']),
          ]),
        ],
      );
      final document =
          catalogue.courses.first.years.values.first.documents.first;
      expect(catalogue.templatesForDocument(document), ['notes']);
    });

    test('un documento sin lecciones todavía compila igual', () {
      // Es el que se acaba de crear, y quedarse sin nada que compilar sería
      // lo peor que puede pasarle a lo que se está montando.
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('slides'), templateJson('notes')],
        blocks: [blockJson('teoria')],
        courses: [
          courseWith([documentJson(references: const [])]),
        ],
      );
      final document =
          catalogue.courses.first.years.values.first.documents.first;
      expect(catalogue.templatesForDocument(document), hasLength(2));
    });
  });

  group('entre repositorios', () {
    test('las plantillas de los dos se juntan por id', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', templates: [templateJson('slides')]),
        repoWith(repo: 'x/problemas', templates: [templateJson('hoja')]),
      ]);
      expect(catalogue.templates.map((t) => t.id), ['slides', 'hoja']);
    });

    test('la misma con clases distintas es una discrepancia', () {
      // Dos PDF distintos con el mismo nombre según en qué orden se abrieron
      // los repositorios.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          templates: [templateJson('notes', documentClass: 'article')],
        ),
        repoWith(
          repo: 'x/problemas',
          templates: [templateJson('notes', documentClass: 'book')],
        ),
      ]);
      final conflict = catalogue.templateConflicts.single;
      expect(conflict.about, ConflictAbout.template);
      expect(conflict.field, 'clase');
      // La clase no se iguala a distancia: se dice, y se arregla editándola.
      expect(conflict.fixable, isFalse);
      expect(catalogue.metadataConflicts, isNotEmpty);
    });

    test('y con nombres distintos se puede igualar desde la pantalla', () {
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          templates: [templateJson('notes', title: 'Apuntes')],
        ),
        repoWith(
          repo: 'x/problemas',
          templates: [templateJson('notes', title: 'Prosa')],
        ),
      ]);
      final conflict = catalogue.templateConflicts.single;
      expect(conflict.field, 'título (es)');
      expect(conflict.fixable, isTrue);
    });

    test('una plantilla que nadie declara se señala', () {
      // El caso de verdad: el bloque compila en una plantilla que declaraba
      // un repositorio que ahora no está abierto.
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: [templateJson('notes')],
        blocks: [
          blockJson('teoria', templates: ['notes', 'apuntes-a5']),
        ],
      );
      expect(catalogue.undeclaredTemplates, ['apuntes-a5']);
      // Y no se compila con ella, que es lo que evita pedirle a LaTeX un
      // perfil que no existe.
      expect(catalogue.templatesOfBlock('teoria'), ['notes']);
    });

    test('sin declarar ninguna no hay nada que señalar', () {
      // Las quince de serie no las declara nadie y no son un problema.
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [
          blockJson('teoria', templates: ['notes']),
        ],
      );
      expect(catalogue.undeclaredTemplates, isEmpty);
    });

    test('apagar un repositorio se lleva lo que solo declaraba él', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', templates: [templateJson('slides')]),
        repoWith(repo: 'x/problemas', templates: [templateJson('hoja')]),
      ]).without({'x/problemas'});
      expect(catalogue.templates.map((t) => t.id), ['slides']);
    });
  });

  group('escribir la elección', () {
    test('un bloque guarda con qué se compila', () {
      const yaml = '''
blocks:
  - id: teoria
    title:
      es: Teoría
''';
      final file = TaxonomyFile(yaml)
        ..setBlockTemplates('teoria', ['slides', 'notes']);
      expect(file.text, contains('templates: [slides, notes]'));
      // Y quitarla lo devuelve a «todas las activas».
      file.setBlockTemplates('teoria', const []);
      expect(file.text, isNot(contains('templates:')));
      expect(file.blockIds, ['teoria']);
    });

    test('un documento también, y sustituye al nombre viejo', () {
      // `profiles:` es como se llamaba y está escrito en cientos de entradas:
      // se lee, pero al escribir queda una sola clave.
      const yaml = '''
course: am-iii
year: 2025-2026
language: es

documents:
  - id: tema-1
    kind: theory
    profiles: [handout, slides]
    title:
      es: Tema 1
''';
      final file = CompositionFile(yaml)
        ..setDocumentTemplates('tema-1', ['notes']);
      expect(file.text, contains('templates: [notes]'));
      expect(file.text, isNot(contains('profiles:')));
      expect(file.text, contains('es: Tema 1'));

      file.setDocumentTemplates('tema-1', const []);
      expect(file.text, isNot(contains('templates:')));
    });
  });

  group('la sesión escribe donde toca', () {
    Future<(FakeSession, FakeGateway)> sessionWith({
      Map<String, String> files = const {},
      List<Map<String, dynamic>> templates = const [],
      List<Map<String, dynamic>> blocks = const [],
      List<Map<String, dynamic>> units = const [],
    }) async {
      final gateway = FakeGateway(files: {...files});
      final catalogue = repoWith(
        repo: 'x/teoria',
        templates: templates,
        blocks: blocks,
        units: units,
      );
      final session = FakeSession(
        gatewayOverride: gateway,
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.useClonesForTest(['/tmp/didacta-0']);
      return (session, gateway);
    }

    test('declarar escribe la plantilla y su preámbulo', () async {
      final (session, gateway) = await sessionWith();
      await session.declareTemplate(
        repo: session.workspace.repos.first.id,
        id: 'apuntes-a5',
        titles: {'es': 'De bolsillo'},
        documentClass: 'article',
        classOptions: '10pt,a5paper',
        axes: {'medium': 'document'},
        preamble: '\\usepackage{lmodern}\n',
      );

      expect(TemplatesFile(gateway.files['templates.yaml']!).ids, [
        'apuntes-a5',
      ]);
      expect(gateway.files['templates/apuntes-a5.tex'], contains('lmodern'));
      // El fichero se crea con sus comentarios, que son la única explicación
      // de por qué apagar una no es borrarla.
      expect(gateway.files['templates.yaml'], contains('active: false'));
    });

    test('apagar una escribe en el repositorio que la declara', () async {
      final (session, gateway) = await sessionWith(
        files: {'templates.yaml': templatesYaml},
        templates: [templateJson('slides'), templateJson('notes')],
      );
      final written = await session.setTemplateActive(
        id: 'slides',
        active: false,
      );
      expect(written, 1);
      expect(
        TemplatesFile(
          gateway.files['templates.yaml']!,
        ).fieldOf('slides', 'active'),
        'false',
      );
    });

    test('la cabecera se lee y se escribe como el LaTeX que es', () async {
      final (session, gateway) = await sessionWith(
        files: {'templates.yaml': templatesYaml},
        templates: [templateJson('notes')],
      );
      expect(
        await session.templatePreamble(repo: 'x/teoria', id: 'notes'),
        isEmpty,
      );
      await session.setTemplatePreamble(
        repo: 'x/teoria',
        id: 'notes',
        text: '\\geometry{margin=3cm}\n',
      );
      expect(gateway.files['templates/notes.tex'], contains('margin=3cm'));
      expect(
        await session.templatePreamble(repo: 'x/teoria', id: 'notes'),
        contains('margin=3cm'),
      );
    });

    test('una lección guarda las suyas en su unit.yaml', () async {
      final (session, gateway) = await sessionWith(
        files: {
          'content/a/b/c/unit.yaml': 'id: a.b.c\nkind: theory\nblock: teoria\n',
        },
        templates: [templateJson('notes')],
        units: [lesson('teoria')],
      );
      await session.setUnitTemplates(
        repo: 'x/teoria',
        path: 'content/a/b/c',
        templates: ['notes'],
      );
      expect(
        gateway.files['content/a/b/c/unit.yaml'],
        contains('templates: [notes]'),
      );

      // Y vaciarla la devuelve a lo que diga su bloque.
      await session.setUnitTemplates(
        repo: 'x/teoria',
        path: 'content/a/b/c',
        templates: const [],
      );
      expect(
        gateway.files['content/a/b/c/unit.yaml'],
        isNot(contains('templates:')),
      );
    });
  });
}
