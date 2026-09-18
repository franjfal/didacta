/// Copiar un fichero en una plataforma con disco.
library;

import 'dart:io';

bool get supported => true;

Future<void> copyFile(String from, String to) async {
  await File(from).copy(to);
}
