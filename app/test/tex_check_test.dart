/// Lo que se avisa antes de compilar, y lo que no.
///
/// La mitad de estas pruebas son de lo que **no** se avisa: un aviso que salta
/// con un fichero que compila enseña a no leer los avisos, y entonces tampoco
/// se lee el que importa.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_check.dart';

List<String> said(String text, {String? language}) => [
  for (final warning in checkTex(text, language: language))
    '${warning.line}:${warning.column} ${warning.message}',
];

void main() {
  mathTests();

  group('lo que compila no se avisa', () {
    test('un fichero corriente', () {
      expect(
        said(r'''
\begin{frame}
\didactatitle{Normas}
Sea $x \in X$ y \( \|x\| \geq 0 \).
\[ \|x + y\| \leq \|x\| + \|y\| \]
$$ a^{2} $$
\end{frame}
'''),
        isEmpty,
      );
    });

    test('lo escapado y lo comentado no cuenta', () {
      expect(
        said(r'''
Cuesta 5 \$ y un 10 \%.
El conjunto \{1, 2\}.
% un $ suelto y una { en un comentario
'''),
        isEmpty,
      );
    });

    test('ni lo que hay en un entorno literal o en \\verb', () {
      expect(
        said(r'''
\begin{verbatim}
if (a { $
\end{verbatim}
Se escribe \verb|$x{| y ya.
'''),
        isEmpty,
      );
    });

    test('una línea con solo un comentario no acaba el párrafo', () {
      expect(
        said(r'''
Sea $x
% nada
= 1$.
'''),
        isEmpty,
      );
    });

    test('\\sen existe en todos los idiomas', () {
      expect(said(r'$\sen x$', language: 'va'), isEmpty);
    });
  });

  group('lo que va a fallar', () {
    test('una llave sin cerrar, en la línea donde se abre', () {
      expect(said('Uno\n\\textbf{dos\ntres\n'), [
        '2:8 Una llave «{» que no se cierra.',
      ]);
    });

    test('una llave que cierra de más', () {
      expect(said('Uno}\n'), ['1:4 Una llave «}» que no abre nada.']);
    });

    test(r'un $ que no se cierra antes del párrafo', () {
      expect(said('Sea \$x \\in X.\n\nOtro párrafo.\n'), [
        '1:5 La fórmula que abre «\$» no se cierra antes del final del '
            'párrafo.',
      ]);
    });

    test(r'un $ que no se cierra antes del final', () {
      expect(said(r'Sea $x.'), [r'1:5 La fórmula que abre «$» no se cierra.']);
    });

    test(r'\[ sin \]', () {
      expect(said('\\[ x = 1\n'), [
        r'1:1 La fórmula que abre «\[» no se cierra.',
      ]);
    });

    test(r'\) sin \(', () {
      expect(said('x \\)\n'), [
        r'1:3 «\)» cierra una fórmula que no se ha abierto.',
      ]);
    });

    test('un entorno sin cerrar', () {
      expect(said('\\begin{frame}\nUno\n'), [
        '1:1 «frame» se abre y no se cierra.',
      ]);
    });

    test('una orden que en este idioma no existe', () {
      expect(said(r'co\lgem{}lecció', language: 'es'), [
        r'1:3 «\lgem» es del catalán y valenciano: en este idioma no existe.',
      ]);
      expect(said(r'co\lgem{}lecció', language: 'va'), isEmpty);
      expect(said(r'\og Bonjour \fg{}', language: 'es'), hasLength(2));
    });

    test('van en el orden del texto', () {
      final warnings = checkTex('}\n\\begin{frame}\n{\n');
      final lines = [for (final warning in warnings) warning.line];
      expect(lines, [...lines]..sort());
      expect(warnings, hasLength(3));
    });
  });
}

void mathTests() {
  bool at(String marked) {
    final offset = marked.indexOf('|');
    return inMathAt(marked.replaceFirst('|', ''), offset);
  }

  group('dentro de una fórmula', () {
    test('en el texto, no', () {
      expect(at('Sea | un número.'), isFalse);
      expect(at(r'Sea $x$ y | otro.'), isFalse);
    });

    test(r'entre $ y $, sí', () {
      expect(at(r'Sea $x | y$.'), isTrue);
      expect(at(r'Sea $$x | y$$.'), isTrue);
      expect(at(r'Sea \(x | \).'), isTrue);
      expect(at('\\[\n x = | \n\\]'), isTrue);
    });

    test('en un entorno de fórmulas, sí', () {
      expect(at('\\begin{align}\n x &= | \n\\end{align}'), isTrue);
      expect(at('\\begin{align}\n x \n\\end{align}\n|'), isFalse);
    });

    test(r'en un \text de una fórmula, no; y un $ ahí abre otra', () {
      expect(at(r'$x \text{si | y} $'), isFalse);
      expect(at(r'$x \text{si $|$} $'), isTrue);
      expect(at(r'$x \text{si} | $'), isTrue);
    });

    test(r'lo escapado y lo comentado no abre nada', () {
      expect(at(r'Cuesta 5 \$ y | nada.'), isFalse);
      expect(at('% \$ en un comentario\n|'), isFalse);
    });

    test('un párrafo nuevo cierra lo que quedara abierto', () {
      expect(at('Sea \$x\n\n|'), isFalse);
    });
  });
}
