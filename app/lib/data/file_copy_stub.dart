/// La respuesta de la web: aquí no hay disco donde dejar una copia.
library;

import '../l10n/tr.dart';

bool get supported => false;

Future<void> copyFile(String from, String to) async =>
    throw UnsupportedError(tr('Aquí no se pueden guardar ficheros.'));
