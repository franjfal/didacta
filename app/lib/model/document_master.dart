/// El `.tex` de un documento nuevo, el que lee `pdflatex`.
///
/// Un documento es dos cosas: su entrada en `year.yaml` --qué lleva y en qué
/// orden-- y un master al lado, `<id>.tex`, que es lo que se compila. El motor
/// escribe la composición dentro del master cada vez que compila, pero no lo
/// crea: sin él, el documento sale en la lista y no se puede compilar
/// (`skipping: no <id>.tex`). Crear un documento desde la aplicación escribía
/// solo lo primero, así que ninguno de los creados aquí compilaba.
///
/// Esto es lo segundo, lo más corto que funciona: el preámbulo de siempre, los
/// datos del curso como respaldo --el motor pone los de verdad en el idioma
/// que se compile-- y un cuerpo vacío que el motor llena.
library;

/// Los caracteres que LaTeX no deja pasar tal cual en un título.
String latexEscape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    out.write(switch (char) {
      r'\' => r'\textbackslash{}',
      '{' || '}' || '#' || r'$' || '%' || '&' || '_' => '\\$char',
      '~' => r'\textasciitilde{}',
      '^' => r'\textasciicircum{}',
      _ => char,
    });
  }
  return out.toString();
}

/// El master de un documento nuevo.
///
/// Con índice solo en los que lo necesitan: un tema lo lleva, un examen o una
/// hoja de una página no.
String documentMaster({
  required String id,
  required String kind,
  required String title,
  required String courseTitle,
  String? teacher,
}) {
  final contents = switch (kind) {
    'theory' || 'seminar' => '\\DidactaContents\n',
    _ => '',
  };
  final teacherLine = teacher == null || teacher.trim().isEmpty
      ? ''
      : '  teacher = {${latexEscape(teacher.trim())}},\n';
  return '''% Un documento de Didacta: ${title.replaceAll('\n', ' ')}.
%
% Lo que lleva y en qué orden está en year.yaml. El motor lo escribe aquí
% debajo cada vez que compila, así que no hace falta tocar este fichero:
%
%   didacta build $id
%
% Los datos del curso de aquí son un respaldo, para que compilarlo a mano en
% un editor también dé un documento con título. Los que pone el motor mandan.

\\input{didacta-bootstrap}
\\usepackage{didacta}

\\DidactaCourse{
  title   = {${latexEscape(courseTitle)}},
$teacherLine}
\\DidactaDocument{${latexEscape(title)}}

\\begin{document}
\\DidactaTitlePage
$contents
\\end{document}
''';
}
