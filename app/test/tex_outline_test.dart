/// El árbol del texto: lo que pinta la vista y lo que avisa.
///
/// Se prueba aquí porque es donde se puede: un color equivocado se ve, pero
/// una diapositiva contada de más, un fichero atribuido al de al lado o un
/// `\begin` sin cerrar que nadie denuncia son fallos silenciosos, y el
/// tercero es el que acaba en un PDF de una página que parece correcto.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_outline.dart';

TexSource unit(String id, String text) =>
    TexSource(id: id, label: id, text: text);

void main() {
  group('un fichero', () {
    test('los entornos salen con su clase y su profundidad', () {
      const text = '''
\\begin{frame}
\\begin{exercise}
Enunciado.
\\begin{solution}
La cuenta.
\\end{solution}
\\end{exercise}
\\end{frame}
''';
      final outline = TexOutline.ofText(text);

      expect(
        [for (final block in outline.blocks) (block.name, block.depth)],
        [('frame', 0), ('exercise', 1), ('solution', 2)],
      );
      expect(outline.blocks.first.kind, TexBlockKind.slide);
      expect(outline.blocks[1].kind, TexBlockKind.exercise);
      expect(outline.blocks.last.kind, TexBlockKind.reveal);
      expect(outline.issues, isEmpty);
    });

    test('un nombre heredado es el mismo entorno', () {
      // `ej` y `ndefn` son lo que escriben los ficheros migrados.
      const text =
          '\\begin{ej}\nUno.\n\\end{ej}\n'
          '\\begin{ndefn}\nDos.\n\\end{ndefn}\n';
      final outline = TexOutline.ofText(text);
      expect(
        [for (final block in outline.blocks) block.kind],
        [TexBlockKind.exercise, TexBlockKind.theorem],
      );
    });

    test('un comentario no abre nada', () {
      const text = '% \\begin{frame}\nProsa.\n';
      final outline = TexOutline.ofText(text);
      expect(outline.blocks, isEmpty);
      expect(outline.issues, isEmpty);
    });

    test('el documento no cuenta como sangría', () {
      const text =
          '\\begin{document}\n\\begin{frame}\nA\n\\end{frame}\n\\end{document}\n';
      final outline = TexOutline.ofText(text);
      final frame = outline.blocks.firstWhere((each) => each.name == 'frame');
      // Envolver el documento entero no es una columna de sangría: es el
      // documento.
      expect(frame.depth, 0);
    });
  });

  group('qué se proyecta', () {
    const text = '''
Prosa de antes.

\\begin{frame}
En la diapositiva.
\\end{frame}

Prosa de después.
''';

    test('lo de dentro de una diapositiva sí, lo de fuera no', () {
      final outline = TexOutline.ofText(text);
      final lines = text.split('\n');
      expect(outline.projectedAt(lines.indexOf('Prosa de antes.')), isFalse);
      expect(outline.projectedAt(lines.indexOf('En la diapositiva.')), isTrue);
      expect(outline.projectedAt(lines.indexOf('Prosa de después.')), isFalse);
    });

    test('las diapositivas se cuentan', () {
      expect(TexOutline.ofText(text).slideCount, 1);
    });
  });

  group('varios ficheros', () {
    test('cada trozo recuerda de dónde salió', () {
      final outline = TexOutline.of([
        unit('courses/am-iii/2025-2026/hoja-1.tex', '\\begin{frame}\n'),
        unit('problems/analysis/normed/axiomas', 'Enunciado.\n'),
        unit('problems/analysis/normed/bolas', '\\end{frame}\n'),
      ]);

      expect(outline.slices.length, 3);
      expect(
        outline.sliceAt(outline.text.indexOf('Enunciado'))!.source.id,
        'problems/analysis/normed/axiomas',
      );
      // Una diapositiva abierta en la composición y cerrada tres ficheros
      // más allá sigue siendo una diapositiva.
      expect(outline.slideCount, 1);
      expect(outline.issues, isEmpty);
    });

    test('la línea de una unidad se cuenta desde su propio fichero', () {
      final outline = TexOutline.of([
        unit('hoja-1.tex', 'Uno.\nDos.\n'),
        unit('problems/rota', 'Tres.\n\\begin{frame}\nCuatro.\n'),
      ]);

      final issue = outline.issues.single;
      expect(issue.kind, TexIssueKind.unclosed);
      expect(issue.sourceId, 'problems/rota');
      // Segunda línea de *su* fichero, no la cuarta del texto pegado: es lo
      // que hay que decirle a quien lo va a arreglar.
      expect(issue.lineInSource, 2);
      expect(issue.line, 3);
    });
  });

  group('lo que está mal se dice y no bloquea', () {
    test('un entorno sin cerrar se cierra al final y se denuncia', () {
      const text = '\\begin{frame}\nSin cerrar.\n';
      final outline = TexOutline.ofText(text);

      expect(outline.issues.single.kind, TexIssueKind.unclosed);
      expect(outline.issues.single.message, '«frame» se abre y no se cierra');
      // Y el bloque existe igual: la vista tiene que poder pintarlo, que
      // para eso se mira.
      expect(outline.blocks.single.name, 'frame');
      expect(outline.blocks.single.closed, isFalse);
      expect(outline.blocks.single.end, text.length);
    });

    test('un cierre suelto se denuncia y se sigue leyendo', () {
      const text =
          'Antes.\n\\end{frame}\n\\begin{exercise}\nA\n\\end{exercise}\n';
      final outline = TexOutline.ofText(text);

      expect(outline.issues.single.kind, TexIssueKind.unopened);
      expect(outline.blocks.single.name, 'exercise');
    });

    test('dos entornos cruzados se denuncian', () {
      const text = '\\begin{frame}\n\\begin{exercise}\nA\n\\end{frame}\n';
      final outline = TexOutline.ofText(text);

      final kinds = [for (final issue in outline.issues) issue.kind];
      expect(kinds, contains(TexIssueKind.crossed));
      expect(outline.issues.map((each) => each.name), contains('exercise'));
    });
  });

  group('la sangría', () {
    const text = '''
\\begin{frame}
\\begin{exercise}
Dentro de los dos.
\\end{exercise}

Entre dos ejercicios.

\\end{frame}
''';

    test('cuenta los entornos que contienen la línea por dentro', () {
      final outline = TexOutline.ofText(text);
      final lines = text.split('\n');
      expect(outline.indentAt(lines.indexOf('Dentro de los dos.')), 2);
      expect(outline.indentAt(lines.indexOf('Entre dos ejercicios.')), 1);
    });

    test('la línea del \\begin y la del \\end van al nivel de fuera', () {
      final outline = TexOutline.ofText(text);
      final lines = text.split('\n');
      // Son el borde del bloque, no parte de él: como la llave de apertura de
      // una función en un editor de código.
      expect(outline.indentAt(lines.indexOf('\\begin{exercise}')), 1);
      expect(outline.indentAt(lines.indexOf('\\end{exercise}')), 1);
      expect(outline.indentAt(lines.indexOf('\\begin{frame}')), 0);
    });

    test('las columnas de una línea van de fuera adentro', () {
      final outline = TexOutline.ofText(text);
      final guides = outline.guidesAt(
        text.split('\n').indexOf('Dentro de los dos.'),
      );
      expect([for (final block in guides) block.name], ['frame', 'exercise']);
    });

    test('la más honda del fichero es la que aparta el texto en el editor', () {
      final outline = TexOutline.ofText(text);
      expect(outline.maxIndentIn(outline.slices.single), 2);
    });

    test('la sangría cuenta lo que se abrió en el fichero anterior', () {
      // Y esta es la razón por la que no se puede guardar: leída sola, esta
      // unidad no tiene sangría; leída con su tema, cuelga de la diapositiva
      // que abrió la anterior.
      final outline = TexOutline.of([
        const TexSource(id: 'a', label: 'a', text: '\\begin{frame}\n'),
        const TexSource(id: 'b', label: 'b', text: 'Dentro.\n\\end{frame}\n'),
      ]);
      final line = outline.lineOf(outline.text.indexOf('Dentro.'));
      expect(outline.indentAt(line), 1);
      expect(TexOutline.ofText('Dentro.\n').indentAt(0), 0);
    });
  });
}
