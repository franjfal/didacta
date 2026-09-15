/// El mensaje que se propone al enviar.
///
/// Se prueba porque es lo que queda escrito en el historial de otra gente: un
/// mensaje que no dice qué se tocó convierte el historial en una lista de
/// «cambios» que nadie puede leer después.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/commit_message.dart';

void main() {
  test('sin nada tocado no hay mensaje', () {
    expect(proposedCommitMessage(const []), isEmpty);
  });

  test('un fichero dice la unidad y el idioma', () {
    expect(
      proposedCommitMessage(const [
        'content/analysis/normed/definition/va.tex',
      ]),
      'Editar content/analysis/normed/definition (va)',
    );
  });

  test('dos idiomas de la misma unidad siguen siendo una unidad', () {
    expect(
      proposedCommitMessage(const [
        'content/analysis/normed/definition/es.tex',
        'content/analysis/normed/definition/va.tex',
      ]),
      'Editar content/analysis/normed/definition',
    );
  });

  test('varias de la misma zona lo dicen', () {
    expect(
      proposedCommitMessage(const [
        'content/analysis/normed/definition/es.tex',
        'content/analysis/normed/banach/es.tex',
      ]),
      'Editar 2 cosas de content/analysis',
    );
  });

  test('cosas de sitios distintos se cuentan', () {
    expect(
      proposedCommitMessage(const [
        'content/analysis/normed/definition/es.tex',
        'courses/am-iii/2025-2026/year.yaml',
      ]),
      'Editar 2 ficheros',
    );
  });
}
