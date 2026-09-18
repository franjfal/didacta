/// Los bloques: dividir una asignatura sin poder romper nada.
///
/// Teoría y problemas estaban escritos en el código, así que no se podían ni
/// renombrar ni añadir. Ahora se declaran en `taxonomy.yaml` con id y nombre
/// por idioma, y siguen el mismo patrón que los temas y las titulaciones:
/// **la unidad nombra el bloque y el bloque lo declara quien lo tenga**.
///
/// De ahí la propiedad que lo hace aceptable: una unidad que nombra un bloque
/// que no declara ningún repositorio abierto se ve entera --sale en la
/// biblioteca, se edita, se compila-- solo que el bloque se enseña por su id.
/// Nadie se queda sin ver su material por no tener un repositorio.
///
/// Este fichero prueba el lado de escribir. Editar `taxonomy.yaml` por líneas
/// y no volviendo a serializarlo no es una manía: el fichero lleva veinte
/// líneas de comentarios explicando qué es un id, y un volcado de YAML se los
/// lleva por delante.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/taxonomy_file.dart';

import 'fixture.dart';

const String taxonomyYaml = '''
# La clasificación con la que se etiqueta una unidad.
#
# El id no se toca nunca: si hace falta otro, es otro bloque.

blocks:
  - id: theory
    title:
      es: Teoría
      va: Teoria
      # TODO: en
  - id: problems
    title:
      es: Problemas

# Las categorías y sus temas.
categories:
  - id: analisis
    title:
      es: Análisis
    topics:
      - id: la-recta-real
        title:
          es: La recta real
''';

/// Sin bloques declarados: el caso de cualquier repositorio de antes de que
/// se pudieran declarar, que es el que no puede romperse.
const String onlyCategoriesYaml = '''
# La clasificación con la que se etiqueta una unidad.

# Las categorías, con sus temas dentro.
categories:
  - id: analisis
    title:
      es: Análisis
''';

void main() {
  group('leer lo declarado', () {
    test('los ids salen en el orden del fichero', () {
      // Y ese orden importa: es el orden en que se dan las partes de una
      // asignatura. Alfabético pondría los problemas antes que la teoría.
      expect(TaxonomyFile(taxonomyYaml).blockIds, ['theory', 'problems']);
    });

    test('el nombre de un bloque, por idioma', () {
      final titles = TaxonomyFile(taxonomyYaml).titlesOfBlock('theory');
      expect(titles, {'es': 'Teoría', 'va': 'Teoria'});
    });

    test('un fichero que solo declara categorías no declara bloques', () {
      expect(TaxonomyFile(onlyCategoriesYaml).blockIds, isEmpty);
    });

    test('y uno vacío tampoco se queja', () {
      expect(TaxonomyFile('').blockIds, isEmpty);
    });
  });

  group('renombrar', () {
    test('cambia el nombre y deja lo demás donde estaba', () {
      final file = TaxonomyFile(taxonomyYaml)
        ..setBlockTitles('theory', {'es': 'Apuntes', 'va': 'Apunts', 'en': ''});
      expect(file.titlesOfBlock('theory'), {'es': 'Apuntes', 'va': 'Apunts'});
      // El id no se toca: es lo que guarda cada unit.yaml.
      expect(file.blockIds, ['theory', 'problems']);
      // Ni las categorías, que son de otro dueño.
      expect(file.text, contains('id: la-recta-real'));
      // Ni los comentarios de arriba, que son la única explicación de por qué
      // esto no rompe nada.
      expect(file.text, contains('El id no se toca nunca'));
    });

    test('un idioma en blanco queda pendiente, no vacío', () {
      // Un nombre vacío saldría en la lista y dentro del PDF. Un `# TODO: en`
      // es lo que cuenta la pantalla de traducciones.
      final file = TaxonomyFile(taxonomyYaml)
        ..setBlockTitles('problems', {'es': 'Problemas', 'en': ''});
      expect(file.text, contains('# TODO: en'));
      expect(file.titlesOfBlock('problems'), {'es': 'Problemas'});
    });

    test('sin nombre en ningún idioma se niega', () {
      expect(
        () => TaxonomyFile(taxonomyYaml).setBlockTitles('theory', {'es': ''}),
        throwsA(isA<TaxonomyException>()),
      );
    });

    test('y renombrar uno que no se declara aquí, también', () {
      expect(
        () => TaxonomyFile(
          taxonomyYaml,
        ).setBlockTitles('practicas', {'es': 'Prácticas'}),
        throwsA(isA<TaxonomyException>()),
      );
    });
  });

  group('declarar uno nuevo', () {
    test('se añade al final de la lista', () {
      final file = TaxonomyFile(taxonomyYaml)
        ..addBlock(
          id: 'practicas',
          titles: {'es': 'Prácticas de ordenador'},
          languages: ['es', 'va', 'en'],
        );
      expect(file.blockIds, ['theory', 'problems', 'practicas']);
      expect(file.titlesOfBlock('practicas'), {'es': 'Prácticas de ordenador'});
      // Los idiomas que faltan se escriben comentados, que es la lista de lo
      // que queda por traducir.
      expect(file.text, contains('# TODO: va'));
    });

    test('en un fichero sin bloques entra delante de las categorías', () {
      // No es cosmética: quien abre `taxonomy.yaml` a mano se encuentra
      // primero las cuatro líneas de los bloques y después las mil de las
      // categorías. Al revés no las encontraría nunca.
      final file = TaxonomyFile(onlyCategoriesYaml)
        ..addBlock(id: 'theory', titles: {'es': 'Teoría'}, languages: ['es']);
      expect(file.blockIds, ['theory']);
      expect(
        file.text.indexOf('blocks:'),
        lessThan(file.text.indexOf('categories:')),
      );
      // Y el comentario de las categorías sigue pegado a las categorías.
      expect(
        file.text.indexOf('# Las categorías, con sus temas dentro.'),
        lessThan(file.text.indexOf('categories:')),
      );
      expect(file.text, contains('id: analisis'));
    });

    test('en un fichero recién creado también', () {
      final file = TaxonomyFile(emptyTaxonomyYaml)
        ..addBlock(
          id: 'theory',
          titles: {'es': 'Teoría'},
          languages: ['es', 'va'],
        );
      expect(file.blockIds, ['theory']);
      expect(file.text, isNot(contains('blocks: []')));
    });

    test('repetir un id se niega', () {
      // Dos bloques con el mismo id son uno solo con dos nombres, y entonces
      // el que se enseña depende de cuál se leyó antes.
      expect(
        () => TaxonomyFile(taxonomyYaml).addBlock(
          id: 'theory',
          titles: {'es': 'Otra teoría'},
          languages: ['es'],
        ),
        throwsA(isA<TaxonomyException>()),
      );
    });
  });

  group('dejar de declarar', () {
    test('quita el bloque y no toca a los demás', () {
      final file = TaxonomyFile(taxonomyYaml)..removeBlock('theory');
      expect(file.blockIds, ['problems']);
      expect(file.titlesOfBlock('problems'), {'es': 'Problemas'});
      expect(file.text, contains('id: la-recta-real'));
    });

    test('el último deja una lista vacía, no una clave colgando', () {
      // `blocks:` sin valor se lee como null y no como lista vacía, que es un
      // error de lectura del repositorio entero.
      final file = TaxonomyFile(taxonomyYaml)
        ..removeBlock('theory')
        ..removeBlock('problems');
      expect(file.blockIds, isEmpty);
      expect(file.text, contains('blocks: []'));
      expect(file.text, contains('categories:'));
    });

    test('quitar uno que no está se niega', () {
      expect(
        () => TaxonomyFile(taxonomyYaml).removeBlock('practicas'),
        throwsA(isA<TaxonomyException>()),
      );
    });
  });

  group('juntar lo que declara cada repositorio', () {
    test('un bloque declarado en dos sale una vez', () {
      // Es el caso normal, no el raro: la teoría y los problemas están
      // repartidos en dos repositorios y los dos necesitan los dos bloques.
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', blocks: [blockJson('theory')]),
        repoWith(repo: 'x/problemas', blocks: [blockJson('theory')]),
      ]);
      expect(catalogue.blocks.single.id, 'theory');
      expect(catalogue.blocks.single.sources.keys, hasLength(2));
    });

    test('y salen en el orden en que se declaran, no alfabético', () {
      // Es el orden en que se dan: primero la teoría y luego los problemas.
      // Alfabético lo cambiaría, y volvería a cambiarlo al traducir.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          blocks: [
            blockJson('theory'),
            blockJson('problems', title: 'Problemas'),
          ],
        ),
      ]);
      expect(catalogue.blocks.map((b) => b.id), ['theory', 'problems']);
    });

    test('apagar un repositorio quita lo que solo declaraba él', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', blocks: [blockJson('theory')]),
        repoWith(
          repo: 'x/problemas',
          blocks: [blockJson('practicas', title: 'Prácticas')],
        ),
      ]).without({'x/problemas'});
      expect(catalogue.blocks.map((b) => b.id), ['theory']);
    });
  });

  group('cuando no dicen lo mismo', () {
    test('dos nombres distintos son una discrepancia', () {
      // Si no, el bloque se enseña con un nombre u otro según en qué orden se
      // abrieron los repositorios.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          blocks: [blockJson('theory', title: 'Teoría')],
        ),
        repoWith(
          repo: 'x/problemas',
          blocks: [blockJson('theory', title: 'Apuntes')],
        ),
      ]);

      final conflict = catalogue.blockConflicts.single;
      expect(conflict.course, 'theory');
      expect(conflict.about, ConflictAbout.block);
      expect(conflict.field, 'título (es)');
      expect(conflict.language, 'es');
      expect(conflict.fixable, isTrue);
    });

    test('decir lo mismo no lo es', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', blocks: [blockJson('theory')]),
        repoWith(repo: 'x/problemas', blocks: [blockJson('theory')]),
      ]);
      expect(catalogue.blockConflicts, isEmpty);
    });

    test('salen con las demás, que se miran a la vez', () {
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          blocks: [blockJson('theory', title: 'Uno')],
        ),
        repoWith(
          repo: 'x/problemas',
          blocks: [blockJson('theory', title: 'Otro')],
        ),
      ]);
      expect(catalogue.metadataConflicts, isNotEmpty);
    });
  });

  group('sin poder esconder material', () {
    test('una lección que nombra un bloque que nadie declara se ve igual', () {
      final catalogue = repoWith(
        repo: 'x/teoria',
        units: [lessonIn('practicas')],
      );
      expect(catalogue.units, hasLength(1));
      expect(catalogue.undeclaredBlocks, ['practicas']);
    });

    test('y sale en la lista de bloques, detrás de los declarados', () {
      // Esconderla escondería sus lecciones: un filtro que no ofrece un
      // bloque es un filtro desde el que no se llega a su material.
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [blockJson('theory')],
        units: [
          lessonIn('theory'),
          lessonIn('practicas', path: 'content/a/b/d'),
        ],
      );
      expect(catalogue.blocksInUse.map((b) => b.id), ['theory', 'practicas']);
      expect(catalogue.blocksInUse.last.declared, isFalse);
      // Por su id, que es feo y es cierto: inventarle un nombre escondería
      // justo lo que hay que arreglar.
      expect(catalogue.blocksInUse.last.title('es'), 'practicas');
    });

    test('los dos de siempre se enseñan por su nombre aunque nadie los '
        'declare', () {
      // Es lo que hace que un repositorio de antes de que los bloques se
      // declararan se vea exactamente igual que antes.
      final catalogue = repoWith(
        repo: 'x/teoria',
        units: [
          lessonIn('theory'),
          lessonIn('problems', path: 'content/a/b/d'),
        ],
      );
      expect(catalogue.blocksInUse.map((b) => b.title('es')), [
        'Teoría',
        'Problemas',
      ]);
    });

    test('los dos de siempre no cuentan como sin declarar', () {
      // Un repositorio de antes de que esto se pudiera declarar tiene teoría
      // y problemas y no tiene `blocks:`. Señalarle las dos mil lecciones
      // como «sin bloque» sería llenar la pantalla de un problema que no
      // existe, y es lo que haría que nadie se fiara de la migración.
      final catalogue = repoWith(
        repo: 'x/teoria',
        units: [
          lessonIn('theory'),
          lessonIn('problems', path: 'content/a/b/d'),
        ],
      );
      expect(catalogue.undeclaredBlocks, isEmpty);
    });

    test('en cuanto se declara uno, dejan de ser implícitos', () {
      // Es el caso de quitar un bloque y dejar atrás sus lecciones: ahí
      // `theory` sin declarar sí es exactamente lo que parece.
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [blockJson('problems', title: 'Problemas')],
        units: [
          lessonIn('theory'),
          lessonIn('problems', path: 'content/a/b/d'),
        ],
      );
      expect(catalogue.undeclaredBlocks, ['theory']);
      // Y se siguen ofreciendo los dos, que es lo que evita que las lecciones
      // huérfanas desaparezcan de la biblioteca.
      expect(catalogue.blocksInUse.map((b) => b.id), ['problems', 'theory']);
    });

    test('un bloque declarado y vacío sigue ofreciéndose', () {
      // Es el que se acaba de crear. Esconderlo deja sin sitio por donde
      // meterle la primera lección.
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [blockJson('practicas', title: 'Prácticas')],
      );
      expect(catalogue.blocksInUse.map((b) => b.id), ['practicas']);
      expect(catalogue.unitsInBlock('practicas'), isEmpty);
    });
  });

  group('escribir en el repositorio', () {
    /// Una sesión de un repositorio, con su `taxonomy.yaml` y sus lecciones.
    Future<(FakeSession, FakeGateway)> oneRepo({
      String? taxonomy = taxonomyYaml,
      List<Map<String, dynamic>> blocks = const [],
      List<Map<String, dynamic>> units = const [],
    }) async {
      final gateway = FakeGateway(
        files: {
          'taxonomy.yaml': ?taxonomy,
          'content/a/b/c/unit.yaml': 'id: a.b.c\nkind: theory\nblock: theory\n',
          'content/a/b/d/unit.yaml': 'id: a.b.d\nkind: theory\nblock: theory\n',
        },
      );
      final catalogue = repoWith(
        repo: 'x/teoria',
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

    test('declarar escribe el bloque en `taxonomy.yaml`', () async {
      final (session, gateway) = await oneRepo();
      await session.declareBlock(
        repo: session.workspace.repos.first.id,
        id: 'practicas',
        titles: {'es': 'Prácticas de ordenador'},
      );

      final written = gateway.files['taxonomy.yaml']!;
      expect(TaxonomyFile(written).blockIds, [
        'theory',
        'problems',
        'practicas',
      ]);
      // Y sin tocar las categorías ni los comentarios, que es de lo que va
      // escribir por líneas en vez de volver a serializar.
      expect(written, contains('id: la-recta-real'));
      expect(written, contains('El id no se toca nunca'));
      expect(gateway.commits.single.message, contains('practicas'));
    });

    test('y crea el fichero, con sus comentarios, si no había', () async {
      // Un `taxonomy.yaml` vacío recién creado no explica nada, y lo que hay
      // que explicar es justamente por qué un bloque que nadie declara no
      // esconde material.
      final (session, gateway) = await oneRepo(taxonomy: null);
      await session.declareBlock(
        repo: session.workspace.repos.first.id,
        id: 'teoria',
        titles: {'es': 'Teoría'},
      );

      final written = gateway.files['taxonomy.yaml']!;
      expect(TaxonomyFile(written).blockIds, ['teoria']);
      expect(written, contains('lo **declara** quien lo tenga'));
    });

    test('renombrar escribe en todos los que lo declaran', () async {
      // Si se cambiara en uno solo, la discrepancia aparece al momento: la
      // misma lección se vería bajo un nombre u otro según la máquina.
      final first = FakeGateway(files: {'taxonomy.yaml': taxonomyYaml});
      final second = FakeGateway(files: {'taxonomy.yaml': taxonomyYaml});
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', blocks: [blockJson('theory')]),
        repoWith(repo: 'x/problemas', blocks: [blockJson('theory')]),
      ]);
      final session = TwoRepoSession(
        gateways: {'x/teoria': first, 'x/problemas': second},
        gatewayOverride: first,
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      final written = await session.setBlockTitles(
        id: 'theory',
        titles: {'es': 'Apuntes', 'va': 'Apunts'},
      );
      expect(written, 2);
      for (final gateway in [first, second]) {
        expect(
          TaxonomyFile(gateway.files['taxonomy.yaml']!).titlesOfBlock('theory'),
          {'es': 'Apuntes', 'va': 'Apunts'},
        );
      }
    });

    test('quitar mueve sus lecciones antes de dejar de declararlo', () async {
      // En ese orden: al revés, entre una cosa y otra el repositorio queda un
      // momento con lecciones huérfanas, y si algo falla se queda así.
      final gateway = BatchGateway(
        files: {
          'taxonomy.yaml': taxonomyYaml,
          'content/a/b/c/unit.yaml': 'id: a.b.c\nkind: theory\nblock: theory\n',
          'content/a/b/d/unit.yaml': 'id: a.b.d\nkind: theory\nblock: theory\n',
        },
      );
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [
          blockJson('theory'),
          blockJson('problems', title: 'P'),
        ],
        units: [
          lessonIn('theory'),
          lessonIn('theory', path: 'content/a/b/d'),
        ],
      );
      final session = FakeSession(
        gatewayOverride: gateway,
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.useClonesForTest(['/tmp/didacta-0']);

      final moved = await session.removeBlock(id: 'theory', moveTo: 'problems');

      expect(moved, 2);
      expect(TaxonomyFile(gateway.files['taxonomy.yaml']!).blockIds, [
        'problems',
      ]);
      expect(
        gateway.files['content/a/b/c/unit.yaml'],
        contains('block: problems'),
      );
      expect(
        gateway.files['content/a/b/d/unit.yaml'],
        contains('block: problems'),
      );
      // Las dos lecciones, en un solo guardado: es un cambio, no dos.
      expect(gateway.batches.single, hasLength(2));
    });

    test('y sin decir a dónde, las deja huérfanas a la vista', () async {
      // Es una salida legítima --puede que el bloque bueno esté en un
      // repositorio que ahora no está abierto-- pero tiene que verse.
      final gateway = FakeGateway(
        files: {
          'taxonomy.yaml': taxonomyYaml,
          'content/a/b/c/unit.yaml': 'id: a.b.c\nkind: theory\nblock: theory\n',
        },
      );
      final catalogue = repoWith(
        repo: 'x/teoria',
        blocks: [
          blockJson('theory'),
          blockJson('problems', title: 'P'),
        ],
        units: [lessonIn('theory')],
      );
      final session = FakeSession(
        gatewayOverride: gateway,
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.useClonesForTest(['/tmp/didacta-0']);

      final moved = await session.removeBlock(id: 'theory');
      expect(moved, 0);
      expect(
        gateway.files['content/a/b/c/unit.yaml'],
        contains('block: theory'),
      );
      expect(TaxonomyFile(gateway.files['taxonomy.yaml']!).blockIds, [
        'problems',
      ]);
    });

    test('cambiar el bloque de una lección toca solo su unit.yaml', () async {
      final (session, gateway) = await oneRepo(units: [lessonIn('theory')]);
      await session.setUnitBlock(
        repo: 'x/teoria',
        path: 'content/a/b/c',
        block: 'problems',
      );
      expect(
        gateway.files['content/a/b/c/unit.yaml'],
        contains('block: problems'),
      );
      expect(
        gateway.files['content/a/b/d/unit.yaml'],
        contains('block: theory'),
      );
      expect(gateway.commits.single.path, 'content/a/b/c/unit.yaml');
    });
  });
}

/// Un repositorio suelto, con los bloques que declare y las lecciones que
/// los nombren.
Catalogue repoWith({
  required String repo,
  List<Map<String, dynamic>> blocks = const [],
  List<Map<String, dynamic>> units = const [],
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': const ['es', 'va', 'en'],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    'profiles': const <Map<String, dynamic>>[],
    'taxonomy': {'blocks': blocks},
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': units},
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'courses': const <Map<String, dynamic>>[],
  },
  repo: repo,
);

Map<String, dynamic> blockJson(String id, {String title = 'Teoría'}) => {
  'id': id,
  'title': {'es': title},
};

Map<String, dynamic> lessonIn(String block, {String path = 'content/a/b/c'}) =>
    {
      'id': path.replaceAll('/', '.'),
      'path': path,
      'area': 'content',
      'kind': 'theory',
      'block': block,
      'category': 'a',
      'topic': 'b',
      'title': const {'es': 'Una lección'},
      'reference': 'es',
      'languages': const {
        'es': {'status': 'source'},
      },
      'usedBy': const <Map<String, String>>[],
    };

// ---------------------------------------------------------------------------
// Escribir: lo que la sesión hace con `taxonomy.yaml` y con los `unit.yaml`
// ---------------------------------------------------------------------------

/// Una pasarela que además sabe si le pidieron guardar de golpe.
///
/// Importa: mover noventa lecciones de bloque es **un** cambio, y si la sesión
/// llamara a `save` noventa veces dejaría noventa commits diciendo lo mismo.
/// Con la pasarela de verdad eso es un solo commit, y lo único que se puede
/// comprobar aquí es que se pide así.
class BatchGateway extends FakeGateway {
  BatchGateway({super.files});

  final List<List<String>> batches = [];

  @override
  Future<void> saveAll({
    required List<({String path, String text, String sha})> files,
    required String message,
  }) async {
    batches.add([for (final file in files) file.path]);
    await super.saveAll(files: files, message: message);
  }
}

/// Una sesión con una pasarela por repositorio.
///
/// [FakeSession] da la misma a todos, que para una pantalla vale; para esto
/// no, porque lo que se prueba es justamente que se escribe en los dos.
class TwoRepoSession extends FakeSession {
  TwoRepoSession({
    required this.gateways,
    required super.catalogue,
    required super.gatewayOverride,
  });

  final Map<String, ContentGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) =>
      gateways[repo] ?? super.gatewayFor(repo);
}
