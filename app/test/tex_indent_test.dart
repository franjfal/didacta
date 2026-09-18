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

  test('`document` no empuja todo a la derecha', () {
    // Envuelve el fichero entero: no hay nada fuera con lo que contrastar.
    // `frame` sí sangra, porque una unidad tiene varias diapositivas y sin
    // sangrar no se ve dónde acaba una y empieza la siguiente.
    const source = '''
\\begin{document}
\\begin{frame}
\\begin{itemize}
\\item Uno
\\end{itemize}
\\end{frame}
\\end{document}
''';
    expect(indentLatex(source), '''
\\begin{document}
\\begin{frame}
  \\begin{itemize}
    \\item Uno
  \\end{itemize}
\\end{frame}
\\end{document}
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

  group('partir líneas', () {
    test('un entorno pegado a su contenido se separa', () {
      // Lo que devuelve un traductor: el párrafo entero en una línea.
      expect(
        indentLatex(
          '\\begin{definition} Un espacio normado es un par.\n'
          '\\end{definition}\n',
        ),
        '\\begin{definition}\n'
        '  Un espacio normado es un par.\n'
        '\\end{definition}\n',
      );
    });

    test('el título del entorno se queda con su `\\begin`', () {
      // `[Negació dels nombres enters]` es argumento de `definition`, no la
      // primera frase del texto: partir por medio lo dejaría huérfano.
      expect(
        indentLatex(
          '\\begin{definition} [Del seno] Las longitudes.\n'
          '\\end{definition}\n',
        ),
        '\\begin{definition} [Del seno]\n'
        '  Las longitudes.\n'
        '\\end{definition}\n',
      );
    });

    test('los argumentos con llaves también', () {
      expect(
        indentLatex(
          '\\begin{empheq} [box=\\tcbhighmath ]{equation*} xy:=x\n'
          '\\end{empheq}\n',
        ),
        '\\begin{empheq} [box=\\tcbhighmath ]{equation*}\n'
        '  xy:=x\n'
        '\\end{empheq}\n',
      );
    });

    test('lo que sigue a un `\\end` se baja de línea', () {
      // `\end{definition}\dpause`, sin un espacio en medio: aquí el salto se
      // **mete**, no sustituye nada, y por eso solo se hace con entornos que
      // Didacta conoce.
      expect(
        indentLatex('\\begin{definition}\nUno.\n\\end{definition}\\dpause\n'),
        '\\begin{definition}\n  Uno.\n\\end{definition}\n\\dpause\n',
      );
    });

    test('un entorno que Didacta no conoce se deja como está', () {
      // Podría ser de los que van dentro de una frase. Sangrar sí se le hace
      // --mover el margen izquierdo no cambia nada-- pero no se le parte
      // ninguna línea.
      expect(
        indentLatex('\\begin{miCaja} Uno. \\end{miCaja}pegado\n'),
        '\\begin{miCaja} Uno. \\end{miCaja}pegado\n',
      );
    });

    test('y uno de dentro de una frase se queda dentro de la frase', () {
      // `el conjunto \\begin{math}A\\end{math} es abierto` partido en tres
      // líneas no se lee mejor: se lee partido.
      const source = 'El conjunto \\begin{math}A\\end{math} es abierto.\n';
      expect(indentLatex(source), source);
    });

    test('una lista en una sola línea se despliega', () {
      expect(
        indentLatex('\\begin{itemize} \\item Uno \\item Dos \\end{itemize}\n'),
        '\\begin{itemize}\n  \\item Uno\n  \\item Dos\n\\end{itemize}\n',
      );
    });

    test('dentro de un verbatim no se parte nada', () {
      // Aquí el texto es lo que se imprime.
      const source =
          '\\begin{lstlisting}\n\\begin{x} pegado \\end{x}\n\\end{lstlisting}\n';
      expect(indentLatex(source), source);
    });

    test('un entorno comentado sigue comentado', () {
      // Partir dentro de un comentario sacaría media línea tachada a la luz
      // como código, que compila o no según el día.
      const source = '% \\begin{itemize} esto está tachado\nUno.\n';
      expect(indentLatex(source), source);
    });

    test('no se crean líneas en blanco', () {
      // Una línea en blanco es un punto y aparte en LaTeX, no un adorno.
      final result = indentLatex(
        'Uno.\n   \\begin{itemize}\n\\item A\n'
        '\\end{itemize}\n',
      );
      expect(result, isNot(contains('\n\n')));
    });

    test('lo que ya está bien no se toca', () {
      const source =
          '\\begin{itemize}\n  \\item Uno\n  \\item Dos\n\\end{itemize}\n';
      expect(indentLatex(source), source);
    });

    test('partir no cambia ni una letra', () {
      const source =
          '\\begin{definition} [Del seno] Si \$(a-b)\$ es entero.\n'
          '\\begin{empheq} [box=\\tcbhighmath ]{equation*} xy:=x+(-y)\n'
          '\\end{empheq}\n'
          '\\end{definition}\\dpause\n';
      expect(bare(indentLatex(source)), bare(source));
    });

    test('y pasarlo dos veces sigue dando lo mismo', () {
      const source =
          '\\begin{proposition}[Dicotomia] Donat \$x\$ aleshores:\n'
          '\\begin{itemize} \\item Uno,\\dpause \\item Dos.\n'
          '\\end{itemize}\n'
          '\\end{proposition}\\dpause\n';
      final once = indentLatex(source);
      expect(indentLatex(once), once);
    });
  });

  group('juntar y cortar párrafos', () {
    test('un párrafo en una sola línea se corta', () {
      final result = indentLatex(
        'Los siguientes resultados relacionan los lados de un triángulo '
        'cualquiera con sus ángulos, y en todos ellos son las longitudes.\n',
        columns: 60,
      );
      for (final line in result.trimRight().split('\n')) {
        expect(line.length, lessThanOrEqualTo(60), reason: line);
      }
      expect(result.trimRight().split('\n').length, greaterThan(1));
    });

    test('junta antes de cortar, así que no depende de cómo estaba', () {
      // Es lo que hace que pasarlo dos veces dé lo mismo, y que un párrafo
      // cortado a lo loco quede bien y no peor.
      const a = 'Uno dos tres cuatro cinco seis siete ocho nueve diez once.\n';
      const b =
          'Uno dos\ntres cuatro cinco\nseis siete ocho nueve diez once.\n';
      expect(indentLatex(a, columns: 40), indentLatex(b, columns: 40));
    });

    test('una línea en blanco separa dos párrafos y no se junta', () {
      // En LaTeX es un punto y aparte: juntarlos sería fundir dos párrafos.
      final result = indentLatex('Uno corto.\n\nDos corto.\n', columns: 60);
      expect(result, 'Uno corto.\n\nDos corto.\n');
    });

    test('una orden sola se queda sola', () {
      // `\vspace{-2mm}` en mitad de una frase no se ve, y quien la puso
      // aparte la puso aparte porque hace algo aparte.
      expect(
        indentLatex('Texto corto.\n\\vspace{-2mm}\nMás texto.\n', columns: 60),
        'Texto corto.\n\\vspace{-2mm}\nMás texto.\n',
      );
    });

    test('pero una que empieza la frase fluye con ella', () {
      final result = indentLatex(
        '\\textbf{Nota:} esto sigue siendo un párrafo con texto detrás que da '
        'de sobra para pasar de sesenta columnas.\n',
        columns: 60,
      );
      expect(result.split('\n').length, greaterThan(2));
      expect(result, startsWith('\\textbf{Nota:} esto'));
    });

    test('no corta por dentro de una fórmula', () {
      // El salto sería un espacio y compilaría, pero una fórmula partida en
      // dos líneas no se lee.
      final result = indentLatex(
        'Palabra palabra palabra palabra \$a+b+c+d+e+f+g+h+i+j+k\$ final.\n',
        columns: 40,
      );
      for (final line in result.split('\n')) {
        expect('\$'.allMatches(line).length.isEven, isTrue, reason: line);
      }
    });

    test('ni por dentro de unas llaves', () {
      // `\textit{ negació}` partido deja la orden a un lado y su argumento al
      // otro, que es lo que se venía a arreglar.
      final result = indentLatex(
        'Palabra palabra palabra \\textit{argumento bastante largo} final.\n',
        columns: 40,
      );
      expect(result, isNot(contains('\\textit{\n')));
      expect(result, isNot(contains('\\textit{argumento\n')));
    });

    test('ni justo detrás del nombre de una orden', () {
      final result = indentLatex(
        'Palabra palabra palabra palabra \\dpause texto de detrás.\n',
        columns: 40,
      );
      expect(result, isNot(contains('\\dpause\n')));
    });

    test('una línea con comentario no se toca', () {
      // Juntarla con la siguiente metería la siguiente dentro del comentario.
      const source =
          'Texto que es bastante largo para pasar del límite. % una nota\n'
          'La línea de abajo.\n';
      expect(indentLatex(source, columns: 40), source);
    });

    test('pero un `\\%` es un tanto por ciento y fluye', () {
      final result = indentLatex(
        'El noventa \\% de las veces esto es prosa larga que hay que cortar.\n',
        columns: 40,
      );
      expect(result.split('\n').length, greaterThan(2));
    });

    test('una línea acabada en `\\\\` es un corte del autor', () {
      const source = 'Primera fila de la tabla \\\\\nSegunda fila.\n';
      expect(indentLatex(source, columns: 40), source);
    });

    test('dentro de un verbatim no se junta ni se corta', () {
      const source =
          '\\begin{verbatim}\nuna linea muy larga que pasa de las cuarenta '
          'columnas sin ninguna duda\notra\n\\end{verbatim}\n';
      expect(indentLatex(source, columns: 40), source);
    });

    test('cada `\\item` es su propio párrafo', () {
      final result = indentLatex(
        '\\begin{itemize}\n\\item Uno.\n\\item Dos.\n\\end{itemize}\n',
        columns: 60,
      );
      expect(
        result,
        '\\begin{itemize}\n  \\item Uno.\n  \\item Dos.\n\\end{itemize}\n',
      );
    });

    test('una palabra sola más larga que el límite no se parte', () {
      // Una URL, una fórmula. Mejor larga que partida por el peor sitio.
      final long = 'a' * 100;
      expect(indentLatex('$long\n', columns: 40), '$long\n');
    });

    test('la sangría cuenta para el límite', () {
      final result = indentLatex(
        '\\begin{definition}\nTexto bastante largo que hay que cortar en '
        'trozos porque no cabe de ninguna manera.\n\\end{definition}\n',
        columns: 50,
      );
      for (final line in result.trimRight().split('\n')) {
        expect(line.length, lessThanOrEqualTo(50), reason: line);
      }
      expect(result, contains('\n  Texto'));
    });

    test('juntar y cortar no cambia ni una letra', () {
      const source =
          '\\begin{definition} [Del seno] Si \$(a-b)\$ es entero, definimos '
          'la negación como el número entero, y en particular esto es una '
          'frase larga.\n'
          '\\end{definition}\\dpause\n';
      expect(bare(indentLatex(source)), bare(source));
    });

    test('y pasarlo dos veces sigue dando lo mismo', () {
      const source =
          '\\begin{frame}\n\\didactatitle{Un título}\n\\vspace{-2mm}\n'
          '\\begin{proposition}[Dicotomia] Donat \$x\$ aleshores exactament '
          'una de les afirmacions següents és certa i no hi ha cap més.\n'
          '\\begin{itemize} \\item Uno,\\dpause \\item Dos.\n'
          '\\end{itemize}\n\\end{proposition}\\dpause\n\\end{frame}\n';
      final once = indentLatex(source);
      expect(indentLatex(once), once);
    });
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
