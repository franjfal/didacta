/// La respuesta de la web: aquí no hay disco donde dejar una copia.
library;

bool get supported => false;

Future<void> copyFile(String from, String to) async =>
    throw UnsupportedError('Aquí no se pueden guardar ficheros.');
