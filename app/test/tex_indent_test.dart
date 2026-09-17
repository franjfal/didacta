/// El indentador: que ponga el fichero en su sitio sin cambiar lo que dice.
///
/// La segunda mitad es la que importa y la que se prueba con más saña. Un
/// beautifier que «solo» se come un espacio dentro de un `verbatim` ha
/// cambiado el PDF, y nadie lo va a ver hasta tenerlo impreso delante de una
/// clase.
@TestOn('vm')
library;

import 'package:didacta_app/model/tex_indent.dart';
import 'package:flutter_test/flutter_test.dart';

/// El texto sin espacios: lo único que el indentador no puede tocar.
String bare(String text) => text.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('mete dentro lo que está dentro', () {
    const source = '''
\\begin{itemize}
\\item Uno
\\item Dos
\\end{itemize}
''';
    expect(indentLatex(source), '''
\\begin{itemize}
  \\item Uno
  \\item Dos
\\end{itemize}
''');
  });

  test('los niveles se acumulan y el `end` vuelve a su `begin`', () {
    const source = '''
\\begin{theorem}
\\begin{enumerate}
\\item Uno
\\end{enumerate}
Fin.
\\end{theorem}
''';
    expect(indentLatex(source), '''
\\begin{theorem}
  \\begin{enumerate}
    \\item Uno
  \\end{enumerate}
  Fin.
\\end{theorem}
''');
  });

  test('deshace la sangría que sobra, no solo la que falta', () {
    // El caso de un fichero editado a mano durante años: cada uno sangró a su
    // manera y hay cuatro criterios en el mismo documento.
    const source = '''
\\begin{itemize}
        \\item Muy dentro
\\item Nada dentro
\\end{itemize}
''';
    expect(indentLatex(source), '''
\\begin{itemize}
  \\item Muy dentro
  \\item Nada dentro
\\end{itemize}
''');
  });

  test('dentro de un verbatim no toca ni un espacio', () {
    // Aquí el espacio **es** el contenido. Sangrarlo cambia lo que sale
    // impreso, y es exactamente el motivo de que esta lista exista.
    const source = '''
\\begin{lstlisting}
def f(x):
    return x + 1
\\end{lstlisting}
''';
    expect(indentLatex(source), source);
  });

  test('un verbatim dentro de un entorno conserva su interior', () {
    const source = '''
\\begin{frame}
\\begin{verbatim}
   tres espacios
\\end{verbatim}
\\end{frame}
''';
    final result = indentLatex(source);
    expect(result, contains('   tres espacios'));
    // Y el `\\begin` sí se coloca: lo intocable es lo de dentro.
    expect(result, contains('\\begin{verbatim}\n'));
  });

  test('`document` y `frame` no empujan todo a la derecha', () {
    const source = '''
\\begin{frame}
\\begin{itemize}
\\item Uno
\\end{itemize}
\\end{frame}
''';
    expect(indentLatex(source), '''
\\begin{frame}
\\begin{itemize}
  \\item Uno
\\end{itemize}
\\end{frame}
''');
  });

  test('un `\\\\begin` en mitad de un párrafo se queda donde está', () {
    // Alguien lo escribió pegado por algo. Moverlo es reescribir su texto, y
    // contar ese nivel dejaría el resto del fichero corrido.
    const source = 'El conjunto \\begin{math}A\\end{math} es abierto.\n';
    expect(indentLatex(source), source);
  });

  test('un `%` no engaña al contador', () {
    const source = '''
% \\begin{itemize}
\\item Suelto
''';
    expect(indentLatex(source), source);
  });

  test('una línea en blanco no se llena de espacios', () {
    // Una línea «vacía» con dos espacios dentro sigue separando párrafos,
    // pero ensucia el diff de cada commit para siempre.
    final result = indentLatex(
      '\\begin{itemize}\n\n\\item Uno\n\\end{itemize}\n',
    );
    expect(result, isNot(contains(' \n')));
  });

  test('tres líneas en blanco seguidas se quedan en una', () {
    final result = indentLatex('Uno.\n\n\n\n\nDos.\n');
    expect(result, 'Uno.\n\nDos.\n');
  });

  test('un `\\\\end` de más no descuadra el resto', () {
    // Material migrado lo tiene. Lo que no puede pasar es que la profundidad
    // se vaya a negativo y el fichero salga con sangría de la nada.
    final result = indentLatex('\\end{itemize}\n\\item Uno\n');
    expect(result, '\\end{itemize}\n\\item Uno\n');
  });

  test('sangrar no cambia ni una letra del contenido', () {
    // La invariante entera, sobre algo que se parece a material de verdad.
    const source = '''
\\DidactaSection{es=Espacios normados}
\\begin{definition}
Un espacio normado es un par \$(X,\\|\\cdot\\|)\$ donde
\\begin{enumerate}
\\item \$\\|x\\| \\geq 0\$;
      \\item \$\\|\\lambda x\\| = |\\lambda| \\|x\\|\$.
\\end{enumerate}
\\end{definition}

\\begin{verbatim}
   intocable
\\end{verbatim}
''';
    expect(bare(indentLatex(source)), bare(source));
  });

  test('pasarlo dos veces da lo mismo que pasarlo una', () {
    // Si no, cada guardado movería el fichero y todos los commits tendrían
    // ruido.
    const source = '''
\\begin{itemize}
    \\item Uno
\\item Dos
\\end{itemize}
''';
    final once = indentLatex(source);
    expect(indentLatex(once), once);
  });

  test('el ancho se puede cambiar', () {
    expect(
      indentLatex('\\begin{itemize}\n\\item Uno\n\\end{itemize}\n', width: 4),
      '\\begin{itemize}\n    \\item Uno\n\\end{itemize}\n',
    );
  });

  test('un fichero vacío sigue vacío', () {
    expect(indentLatex(''), '');
    expect(indentLatex('\n'), '\n');
  });
}
