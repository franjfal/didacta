/// Los borradores de la vista del fuente.
///
/// Lo que se prueba es lo que pierde trabajo si falla: qué se considera
/// tocado, qué se considera conflicto —incluido el caso de un fichero que no
/// existía y ha aparecido— y que el mensaje del commit diga qué se tocó.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/source_drafts.dart';

SourceDraft draft(
  String path, {
  String loaded = 'Original.\n',
  String sha = 'sha-1',
  bool exists = true,
  String? text,
}) => SourceDraft(
  path: path,
  loaded: loaded,
  sha: sha,
  exists: exists,
  text: text,
);

void main() {
  test('tocado es haber cambiado el texto, no haberlo abierto', () {
    final drafts = SourceDrafts()..put(draft('content/a/es.tex'));
    expect(drafts.isDirty, isFalse);

    drafts.of('content/a/es.tex')!.text = 'Otra cosa.\n';
    expect(drafts.isDirty, isTrue);
    expect(drafts.dirty.single.path, 'content/a/es.tex');
  });

  test('los tocados salen en orden de ruta', () {
    final drafts = SourceDrafts()
      ..put(draft('content/b/es.tex', text: 'x'))
      ..put(draft('content/a/va.tex', text: 'x'));
    expect(
      [for (final each in drafts.dirty) each.path],
      ['content/a/va.tex', 'content/b/es.tex'],
    );
  });

  test('un fichero que cambió en el repositorio es un conflicto', () {
    final drafts = SourceDrafts()
      ..put(draft('content/a/es.tex', text: 'mío'))
      ..put(draft('content/b/es.tex', sha: 'sha-b', text: 'mío'));

    expect(
      drafts.conflicts({
        'content/a/es.tex': 'otro',
        'content/b/es.tex': 'sha-b',
      }),
      ['content/a/es.tex'],
    );
  });

  test('un fichero que no existía y ahora sí también lo es', () {
    // Empezar una traducción que alguien empezó a la vez no puede acabar
    // pisándola.
    final drafts = SourceDrafts()
      ..put(
        draft(
          'content/a/va.tex',
          loaded: '',
          sha: '',
          exists: false,
          text: 'nuevo',
        ),
      );
    expect(drafts.conflicts({'content/a/va.tex': 'sha-nuevo'}), [
      'content/a/va.tex',
    ]);
    // Y si sigue sin existir, crearlo no pisa nada.
    expect(drafts.conflicts(const {}), isEmpty);
  });

  test('lo que no se ha tocado no entra en el conflicto', () {
    final drafts = SourceDrafts()..put(draft('content/a/es.tex'));
    expect(drafts.conflicts({'content/a/es.tex': 'otro'}), isEmpty);
  });

  group('el mensaje del commit', () {
    test('un fichero dice cuál y en qué idioma', () {
      final drafts = SourceDrafts()
        ..put(draft('content/analysis/normed/definition/va.tex', text: 'x'));
      expect(
        drafts.suggestedMessage('Tema 1'),
        'Editar content/analysis/normed/definition (va)',
      );
    });

    test('varios dicen cuántas unidades y de qué documento', () {
      final drafts = SourceDrafts()
        ..put(draft('content/a/es.tex', text: 'x'))
        ..put(draft('content/b/es.tex', text: 'x'));
      expect(drafts.suggestedMessage('Tema 1'), 'Editar 2 unidades de Tema 1');
    });

    test('sin nada tocado no hay mensaje', () {
      expect(SourceDrafts().suggestedMessage('Tema 1'), isEmpty);
    });
  });
}
