/// Varios repositorios a la vez: el espacio de trabajo y la mezcla.
///
/// Lo que se prueba es lo que decide qué ve cada persona: que una asignatura
/// descrita en dos repositorios se ve entera, que cada documento se queda
/// sabiendo de dónde sale --porque es contra esa raíz contra la que compila--,
/// que quien solo tiene uno ve el suyo sin que falle nada, y que dos unidades
/// con la misma ruta en repositorios distintos son dos unidades.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/workspace.dart';

import 'fixture.dart';

Catalogue catalogueOf(
  String repo, {
  required List<Map<String, dynamic>> units,
  List<Map<String, dynamic>>? courses,
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': repo,
    'languages': const ['es', 'va'],
    'defaultLanguage': 'es',
    'contentHash': 'hash-$repo',
    'profiles': const <Map<String, dynamic>>[],
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': units},
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'courses': courses ?? const [],
  },
  repo: repo,
);

Map<String, dynamic> courseJsonWith({
  required String id,
  required String year,
  required List<String> documents,
}) => {
  'id': id,
  'title': {'es': 'Análisis'},
  'language': 'es',
  'years': {
    year: {
      'year': year,
      'language': 'es',
      'documents': [
        for (final document in documents)
          {
            'id': document,
            'kind': 'theory',
            'language': 'es',
            'title': {'es': document},
            'profiles': const <String>[],
            'unitRefs': const <String>[],
          },
      ],
    },
  },
};

void main() {
  group('el espacio de trabajo', () {
    test('va y vuelve de su forma guardada', () {
      const repo = ContentRepo(
        owner: 'franjfal',
        name: 'didacta_db',
        directory: '/Users/x/Didacta/didacta_db',
        colour: 0xFF346E34,
      );
      final back = Workspace.fromJson(const Workspace([repo]).toJson());
      expect(back.repos.single.id, 'franjfal/didacta_db');
      expect(back.repos.single.directory, '/Users/x/Didacta/didacta_db');
      expect(back.repos.single.colour, 0xFF346E34);
    });

    test('reparte un color distinto a cada uno', () {
      var workspace = const Workspace.empty();
      final colours = <int>{};
      for (var i = 0; i < 4; i += 1) {
        final colour = workspace.nextColour();
        colours.add(colour);
        workspace = workspace.with_(
          ContentRepo(
            owner: 'x',
            name: 'r$i',
            directory: '/tmp/r$i',
            colour: colour,
          ),
        );
      }
      expect(colours.length, 4);
    });

    test('se puede cambiar el color de uno sin tocar los demás', () {
      final workspace = const Workspace([
        ContentRepo(owner: 'x', name: 'a', directory: '/a', colour: 1),
        ContentRepo(owner: 'x', name: 'b', directory: '/b', colour: 2),
      ]).recoloured('x/a', 9);
      expect(workspace.byId('x/a')!.colour, 9);
      expect(workspace.byId('x/b')!.colour, 2);
    });
  });

  group('de qué repositorio es un clon', () {
    test('de una URL de https', () {
      final found = repoFromRemote(
        'https://github.com/franjfal/didacta_db.git',
      );
      expect(found!.owner, 'franjfal');
      expect(found.name, 'didacta_db');
    });

    test('de una de ssh, que lleva dos puntos donde iría una barra', () {
      final found = repoFromRemote('git@github.com:franjfal/didacta_db.git');
      expect(found!.owner, 'franjfal');
      expect(found.name, 'didacta_db');
    });

    test('de una ruta del disco', () {
      final found = repoFromRemote('/Users/javier/remotos/x/uno.git');
      expect(found!.owner, 'x');
      expect(found.name, 'uno');
    });

    test('de nada, nada', () {
      expect(repoFromRemote(null), isNull);
      expect(repoFromRemote('   '), isNull);
    });
  });

  group('mezclar repositorios', () {
    test('una asignatura en dos repositorios se ve entera', () {
      final merged = Catalogue.merge([
        catalogueOf(
          'x/uno',
          units: [unitJson()],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2025-2026',
              documents: ['tema-1'],
            ),
          ],
        ),
        catalogueOf(
          'x/dos',
          units: [unitJson(path: 'content/otra/cosa')],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2025-2026',
              documents: ['tema-2'],
            ),
          ],
        ),
      ]);

      final course = merged.courses.single;
      final year = course.years['2025-2026']!;
      expect(
        [for (final document in year.documents) document.id],
        ['tema-1', 'tema-2'],
      );
      // Y cada tema sigue sabiendo de dónde sale: es contra esa raíz contra
      // la que compila y donde están sus unidades.
      expect(year.documents.first.repo, 'x/uno');
      expect(year.documents.last.repo, 'x/dos');
      expect(course.repos, {'x/uno', 'x/dos'});
    });

    test('dos rutas iguales en repositorios distintos son dos unidades', () {
      final merged = Catalogue.merge([
        catalogueOf('x/uno', units: [unitJson()]),
        catalogueOf('x/dos', units: [unitJson()]),
      ]);
      expect(merged.units.length, 2);
      expect(merged.unitByPath(unitPath, repo: 'x/dos')!.repo, 'x/dos');
    });

    test('un año que solo está en un repositorio se ve igual', () {
      // Quien no tenga el otro ve lo suyo, y nada falla por eso.
      final merged = Catalogue.merge([
        catalogueOf(
          'x/uno',
          units: const [],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2024-2025',
              documents: ['viejo'],
            ),
          ],
        ),
        catalogueOf(
          'x/dos',
          units: const [],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2025-2026',
              documents: ['nuevo'],
            ),
          ],
        ),
      ]);
      expect(merged.courses.single.sortedYears, ['2025-2026', '2024-2025']);
    });

    test('un documento con el mismo id en los dos se cuenta como problema', () {
      final merged = Catalogue.merge([
        catalogueOf(
          'x/uno',
          units: const [],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2025-2026',
              documents: ['tema-1'],
            ),
          ],
        ),
        catalogueOf(
          'x/dos',
          units: const [],
          courses: [
            courseJsonWith(
              id: 'am-iii',
              year: '2025-2026',
              documents: ['tema-1'],
            ),
          ],
        ),
      ]);
      // Son dos documentos distintos que dicen ser el mismo: se queda el
      // primero y se dice, en lugar de elegir en silencio.
      expect(merged.courses.single.years['2025-2026']!.documents.length, 1);
      expect(merged.errors.single, contains('tema-1'));
    });

    test('uno solo se lee tal cual', () {
      final one = catalogueOf('x/uno', units: [unitJson()]);
      expect(identical(Catalogue.merge([one]), one), isTrue);
    });
  });
}
