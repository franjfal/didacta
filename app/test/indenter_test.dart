/// Elegir indentador: el de CTAN si funciona, el nuestro si no.
///
/// Este test corre contra el `latexindent` que haya --o no haya-- en la
/// máquina, y por eso no comprueba cuál de los dos contestó: comprueba lo
/// único que importa siempre, que sale un fichero sangrado y que no se ha
/// perdido nada por el camino.
@TestOn('vm')
library;

import 'package:didacta_app/data/indenter.dart';
import 'package:flutter_test/flutter_test.dart';

String bare(String text) => text.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('sangra, con la herramienta que sea', () async {
    const source = '''
\\begin{itemize}
\\item Uno
\\item Dos
\\end{itemize}
''';
    final result = await beautifyLatex(source);
    expect(result, contains('  \\item Uno'));
    expect(bare(result), bare(source));
  });

  test('con `latexindent` roto o ausente, sigue saliendo el fichero', () async {
    // El caso de una máquina recién montada: MacTeX trae el script y no los
    // módulos de Perl. Lo que no puede pasar es que guardar falle por eso.
    final result = await beautifyLatex(
      '\\begin{enumerate}\n\\item Uno\n\\end{enumerate}\n',
      texPath: '/no/existe/este/sitio',
    );
    expect(result, '\\begin{enumerate}\n  \\item Uno\n\\end{enumerate}\n');
  });

  test('preguntar si está no lanza nada', () async {
    expect(await systemIndenterWorks(texPath: '/no/existe'), isFalse);
  });
}
