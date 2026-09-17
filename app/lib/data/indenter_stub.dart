/// Sangrar en la web: con lo nuestro, que es todo lo que hay.
///
/// Un navegador no lanza procesos, así que `latexindent` no entra en la
/// conversación. El indentador propio sí funciona --es Dart puro-- y por eso
/// existe: la web guarda ficheros igual de bien puestos que el escritorio.
library;

import '../model/tex_indent.dart';

Future<String> beautifyLatex(String text, {String? texPath}) async =>
    indentLatex(text);

Future<bool> systemIndenterWorks({String? texPath}) async => false;
