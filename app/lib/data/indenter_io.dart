/// Sangrar donde se puede lanzar un proceso: primero `latexindent`.
library;

import 'dart:async';
import 'dart:io';

import '../model/tex_indent.dart';
import 'compiler_io.dart' show findTool, texAwarePath;

/// Cuánto se le espera a `latexindent` antes de dar por hecho que no viene.
///
/// Esto corre al guardar, delante de alguien que acaba de pulsar Cmd+S. Tres
/// segundos es mucho más de lo que tarda con un fichero de clase y bastante
/// menos de lo que se nota como un cuelgue.
const Duration _patience = Duration(seconds: 3);

Future<String> beautifyLatex(String text, {String? texPath}) async {
  final theirs = await _systemIndent(text, texPath: texPath);
  return theirs ?? indentLatex(text);
}

Future<bool> systemIndenterWorks({String? texPath}) async {
  // Con algo mínimo pero real: un entorno con una línea dentro. Un fichero
  // vacío lo «sangra» hasta un `latexindent` al que le faltan la mitad de los
  // módulos, porque falla después de imprimir nada.
  final probe = await _systemIndent(
    '\\begin{itemize}\n\\item Uno\n\\end{itemize}\n',
    texPath: texPath,
  );
  return probe != null;
}

/// El fichero pasado por `latexindent`, o `null` si no se puede confiar.
///
/// `null` en todos los casos malos, y son varios: no está instalado, está
/// pero le faltan los módulos de Perl, tarda demasiado, o devuelve algo que
/// no es el mismo texto. No se distingue entre ellos a propósito --quien
/// guarda un fichero no tiene nada que hacer con esa diferencia-- y la
/// respuesta es la misma: usar el nuestro.
Future<String?> _systemIndent(String text, {String? texPath}) async {
  final tool = await findTool('latexindent', configured: texPath);
  if (tool == null) return null;

  final scratch = await Directory.systemTemp.createTemp('didacta-indent');
  try {
    final input = File('${scratch.path}/unit.tex');
    await input.writeAsString(text);

    final result = await Process.run(
      tool,
      [
        // Sin avisos por pantalla y sin fichero de log en el directorio de
        // trabajo: `-c` manda toda su chatarra al temporal, que se borra.
        '-s',
        '-c', scratch.path,
        input.path,
      ],
      environment: {'PATH': texAwarePath(configured: texPath)},
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    ).timeout(_patience, onTimeout: () => ProcessResult(0, 1, '', 'tardó'));

    if (result.exitCode != 0) return null;
    final output = result.stdout as String;
    if (output.trim().isEmpty) return null;
    // Y la comprobación que de verdad protege: sangrar cambia el espacio en
    // blanco y **nada más**. Si lo que vuelve no es el mismo texto letra por
    // letra quitando espacios, se ha llevado algo por delante --un fichero de
    // configuración del proyecto con `modifyLineBreaks`, una versión que hace
    // otra cosa-- y eso no se guarda encima del trabajo de nadie.
    if (_bare(output) != _bare(text)) return null;
    return output;
  } on ProcessException {
    return null;
  } finally {
    // Sin `await`: el fichero ya está leído y esperar a que el sistema borre
    // un temporal no es algo por lo que deba pararse un guardado.
    unawaited(
      scratch.delete(recursive: true).catchError((Object _) => scratch),
    );
  }
}

/// El texto sin nada de espacio en blanco, para compararlo consigo mismo.
String _bare(String text) => text.replaceAll(RegExp(r'\s+'), '');
