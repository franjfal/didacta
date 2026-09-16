/// Un documento recién creado, antes de que el índice lo recoja.
///
/// El catálogo se genera aparte, así que hay unos segundos --entre crear el
/// documento y guardar y reindexar-- en los que existe en `year.yaml` y no en
/// `generated/`. Lo que se sabe de él en ese rato lo dice el fichero, que
/// acaba de escribirlo: de qué tipo es, cómo se llama y a qué tema pertenece.
///
/// Sin esto salía como una línea con el identificador, al final de la
/// pantalla y fuera de su tema, y un documento recién creado parecía un error
/// en lugar del mismo documento esperando.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/composition_file.dart';

const String year = '''
course: am-i
year: 2026-2027
language: es

documents:
  - id: tema-1-teoria
    kind: theory
    title:
      es: La teoría del tema 1
      # TODO: va
    themes: [tema-1, apendices]
    structure: []

  - id: faq
    kind: handout
    title:
      es: Preguntas frecuentes
    structure: []
''';

void main() {
  test('lee el tipo, el título y los temas de cada documento', () {
    final drafts = CompositionFile(year).documentDrafts();
    expect(drafts.map((d) => d.id), ['tema-1-teoria', 'faq']);

    final first = drafts.first;
    expect(first.kind, 'theory');
    expect(first.title('es'), 'La teoría del tema 1');
    expect(first.themes, ['tema-1', 'apendices']);
  });

  test('un documento sin temas no tiene ninguno', () {
    final faq = CompositionFile(year).documentDrafts().last;
    expect(faq.themes, isEmpty);
    expect(faq.kind, 'handout');
  });

  test('los TODO del título no se toman por un idioma', () {
    // `# TODO: va` está dentro del bloque de `title:` y dice qué falta por
    // traducir. Leerlo como una traducción daría un título «TODO».
    final first = CompositionFile(year).documentDrafts().first;
    expect(first.titles.keys, ['es']);
  });

  test('sin título se cae al identificador, que siempre hay', () {
    const sinTitulo = '''
course: am-i
year: 2026-2027

documents:
  - id: suelto
    kind: theory
    structure: []
''';
    final draft = CompositionFile(sinTitulo).documentDrafts().single;
    expect(draft.title('es'), 'suelto');
  });

  test('un documento recién añadido se lee entero', () {
    // El caso exacto: se crea desde la pantalla, dentro de un tema, y hay que
    // poder dibujarlo con su forma antes de guardar.
    final file = CompositionFile(year);
    file.addDocument(
      id: 'tema-1-problemas',
      kind: 'problems',
      title: const {'es': 'Problemas del tema 1'},
      themes: const ['tema-1'],
    );

    final draft = CompositionFile(
      file.text,
    ).documentDrafts().firstWhere((d) => d.id == 'tema-1-problemas');
    expect(draft.kind, 'problems');
    expect(draft.title('es'), 'Problemas del tema 1');
    expect(draft.themes, ['tema-1']);
  });

  test('un documento añadido sin tema no nombra ninguno', () {
    final file = CompositionFile(year);
    file.addDocument(
      id: 'notacion',
      kind: 'handout',
      title: const {'es': 'Notación'},
    );
    final draft = CompositionFile(
      file.text,
    ).documentDrafts().firstWhere((d) => d.id == 'notacion');
    expect(draft.themes, isEmpty);
  });
}
