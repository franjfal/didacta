/// La barra del editor, por su lógica.
///
/// Lo que se prueba aquí es lo que corrompe un fichero si falla: contar mal
/// una llave, no ver un comentario, o envolver un trozo que no era el
/// marcado. Todo eso es invisible en la interfaz hasta que alguien compila.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_wrap.dart';

TexWrapper wrapper(String id) =>
    didactaWrappers.firstWhere((each) => each.id == id);

void main() {
  group('envolver', () {
    test('una frase suelta usa la macro', () {
      const text = 'Antes. Esto es un apunte. Después.';
      final result = toggleWrap(text, 7, 25, wrapper('onlynotes'));
      expect(result.text, 'Antes. \\onlynotes{Esto es un apunte.} Después.');
      // Lo que queda marcado es el cuerpo, que es lo que permite volver a
      // pulsar para deshacerlo.
      expect(
        result.text.substring(result.start, result.end),
        'Esto es un apunte.',
      );
    });

    test('una selección con línea en blanco usa el entorno', () {
      const text = 'Un párrafo.\n\nY otro más.';
      final result = toggleWrap(text, 0, text.length, wrapper('onlyslides'));
      expect(
        result.text,
        '\\begin{slidesonly}\nUn párrafo.\n\nY otro más.\n\\end{slidesonly}',
      );
    });

    test('un cuerpo con un entorno dentro usa el entorno', () {
      const text = 'Texto con \\begin{parts}\\item a\\end{parts} dentro.';
      final result = toggleWrap(text, 0, text.length, wrapper('onlyteacher'));
      expect(result.text, startsWith('\\begin{teacheronly}\n'));
    });

    test('lo que solo es bloque nunca sale como macro', () {
      const text = 'La respuesta.';
      final result = toggleWrap(text, 0, text.length, wrapper('answer'));
      expect(result.text, '\\begin{answer}\nLa respuesta.\n\\end{answer}');
    });

    test('sin selección se envuelve el párrafo del cursor', () {
      const text = 'Primero.\n\nSegundo párrafo.\n\nTercero.';
      final result = toggleWrap(text, 15, 15, wrapper('onlyslides'));
      expect(
        result.text,
        'Primero.\n\n\\onlyslides{Segundo párrafo.}\n\nTercero.',
      );
    });

    test('los blancos de los extremos se quedan fuera', () {
      const text = 'Uno.\n\nDos.\n\nTres.';
      // La selección se pasa de frenada y se lleva el salto de línea.
      final result = toggleWrap(text, 6, 11, wrapper('onlynotes'));
      expect(result.text, 'Uno.\n\n\\onlynotes{Dos.}\n\nTres.');
    });

    test('una selección larga con línea en blanco pasa a entorno', () {
      const text = 'Uno.\n\nDos.\n\nTres.';
      final result = toggleWrap(text, 0, 10, wrapper('onlynotes'));
      expect(
        result.text,
        '\\begin{notesonly}\nUno.\n\nDos.\n\\end{notesonly}\n\nTres.',
      );
    });
  });

  group('desenvolver', () {
    test('el mismo botón lo quita', () {
      const text = 'Antes. Esto es un apunte. Después.';
      final wrapped = toggleWrap(text, 7, 24, wrapper('onlynotes'));
      final undone = toggleWrap(
        wrapped.text,
        wrapped.start,
        wrapped.end,
        wrapper('onlynotes'),
      );
      expect(undone.text, text);
    });

    test('ida y vuelta de un entorno deja el texto como estaba', () {
      const text = 'Un párrafo.\n\nY otro más.';
      final wrapped = toggleWrap(text, 0, text.length, wrapper('onlyslides'));
      final undone = toggleWrap(
        wrapped.text,
        wrapped.start,
        wrapped.end,
        wrapper('onlyslides'),
      );
      expect(undone.text, text);
    });

    test('basta con el cursor dentro', () {
      const text = 'a \\onlyteacher{una nota} b';
      final result = toggleWrap(text, 18, 18, wrapper('onlyteacher'));
      expect(result.text, 'a una nota b');
    });

    test('reconoce el nombre heredado', () {
      // 772 ficheros migrados abren así.
      const text = '\\onlybook{La prosa larga.}';
      final result = toggleWrap(text, 12, 12, wrapper('onlynotes'));
      expect(result.text, 'La prosa larga.');
    });

    test('reconoce el entorno heredado de un ejercicio', () {
      const text = '\\begin{ej}[Norma]\nEnunciado.\n\\end{ej}';
      final result = toggleWrap(text, 20, 20, wrapper('exercise'));
      expect(result.text, 'Enunciado.');
    });

    test('quita el más interno cuando hay dos anidados', () {
      const text =
          '\\begin{teacheronly}\nA\n\\onlyteacher{dentro}\nB\n\\end{teacheronly}';
      final result = toggleWrap(text, 36, 36, wrapper('onlyteacher'));
      expect(
        result.text,
        '\\begin{teacheronly}\nA\ndentro\nB\n\\end{teacheronly}',
      );
    });
  });

  group('leer el texto', () {
    test('un comentario no cuenta como entorno', () {
      const text = '% \\begin{answer}\nEsto no está dentro de nada.\n';
      final result = toggleWrap(text, 20, 20, wrapper('answer'));
      // No desenvuelve nada: envuelve el párrafo.
      expect(result.text, contains('\\begin{answer}\nEsto no está'));
    });

    test('las llaves anidadas se cuentan', () {
      const text = 'x \\onlynotes{con \\hl{algo} dentro} y';
      final result = toggleWrap(text, 20, 20, wrapper('onlynotes'));
      expect(result.text, 'x con \\hl{algo} dentro y');
    });

    test('una llave escapada no cuenta', () {
      const text = r'x \onlynotes{una \{ llave} y';
      final result = toggleWrap(text, 20, 20, wrapper('onlynotes'));
      expect(result.text, r'x una \{ llave y');
    });

    test('un nombre más largo no es el mismo macro', () {
      const text = '\\onlyslidesbis{algo}';
      final result = toggleWrap(text, 16, 16, wrapper('onlyslides'));
      expect(result.text, '\\onlyslides{\\onlyslidesbis{algo}}');
    });
  });

  group('dónde está el cursor', () {
    test('los envoltorios se listan de fuera adentro', () {
      const text =
          '\\begin{exercise}\nEnunciado.\n\\begin{solution}\nLa cuenta.\n'
          '\\end{solution}\n\\end{exercise}';
      final found = wrappersAt(text, text.indexOf('La cuenta'));
      expect([for (final each in found) each.id], ['exercise', 'solution']);
    });

    test('fuera de todo no hay ninguno', () {
      const text = 'Texto suelto.';
      expect(wrappersAt(text, 5), isEmpty);
    });
  });

  test('insertar una pausa sustituye lo marcado', () {
    const text = 'Antes XXX después.';
    final result = insertSnippet(text, 6, 9, '\\dpause');
    expect(result.text, 'Antes \\dpause después.');
    expect(result.start, result.end);
  });
}
