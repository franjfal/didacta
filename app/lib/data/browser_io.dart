/// Abrir una dirección con la orden que cada sistema tiene para eso.
library;

import 'dart:io';

Future<bool> openLink(String url) async {
  // Solo http(s). Es lo único que esto abre, y comprobarlo es lo que impide
  // que una dirección que viniera de otro sitio --un `file://`, un esquema
  // que registró otra aplicación-- acabe ejecutando algo por ser abierta.
  final parsed = Uri.tryParse(url);
  if (parsed == null || (parsed.scheme != 'https' && parsed.scheme != 'http')) {
    return false;
  }

  final (String command, List<String> arguments) = switch (true) {
    _ when Platform.isMacOS => ('open', [url]),
    _ when Platform.isWindows => ('cmd', ['/c', 'start', '', url]),
    _ => ('xdg-open', [url]),
  };

  try {
    final result = await Process.run(command, arguments);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
