/// Deshacer el escapado HTML de lo que devuelve un traductor.
///
/// Existe por un `.tex` real: `l'operació` se guardó como `l&#39;operació`, y
/// eso no compila --en LaTeX `&` separa columnas de tabla--. Se pide la
/// traducción en HTML porque es la única forma de que los proveedores
/// respeten las etiquetas que protegen el LaTeX, y en HTML lo que vuelve
/// viene escapado.
@TestOn('vm')
library;

import 'package:didacta_app/data/translator_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el apóstrofo, que es el que rompía el fichero', () {
    // En valenciano y en catalán está en una palabra de cada cinco.
    expect(unescapeHtml('l&#39;operació'), "l'operació");
    expect(unescapeHtml('l&apos;operació'), "l'operació");
    expect(unescapeHtml('l&#x27;operació'), "l'operació");
  });

  test('las cinco de siempre', () {
    expect(
      unescapeHtml('a &amp; b &lt; c &gt; d &quot;e&quot;'),
      'a & b < c > d "e"',
    );
  });

  test('de una pasada: `&amp;lt;` es el texto «&lt;», no un menor que', () {
    // Encadenando sustituciones, la segunda vería el `&lt;` que acaba de
    // crear la primera y lo convertiría en `<`, que es texto que nadie
    // escribió.
    expect(unescapeHtml('&amp;lt;'), '&lt;');
  });

  test('el espacio duro vuelve como espacio duro', () {
    expect(unescapeHtml('a&nbsp;b'), 'a b');
  });

  test('una entidad que no conocemos se queda como está', () {
    // Convertirla en el carácter equivocado es peor que dejarla: dejada, se
    // ve y se arregla; cambiada, se queda.
    expect(unescapeHtml('a &zzzz; b'), 'a &zzzz; b');
  });

  test('un `&` suelto no se toca', () {
    expect(unescapeHtml(r'\begin{tabular} a & b'), r'\begin{tabular} a & b');
  });

  test('las etiquetas que protegen el LaTeX sobreviven', () {
    // Son etiquetas literales, no entidades: si esto las tocara, el LaTeX no
    // volvería a su sitio al deshacer la protección.
    expect(
      unescapeHtml('El conjunt <x id="0"/> és obert'),
      'El conjunt <x id="0"/> és obert',
    );
  });

  test('un texto sin nada que deshacer sale tal cual', () {
    expect(
      unescapeHtml('Les longituds dels costats'),
      'Les longituds dels costats',
    );
  });
}
