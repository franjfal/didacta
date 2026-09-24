/// En la web no hay carpetas que abrir ni que tirar.
library;

bool get supported => false;

String get openLabel => 'Abrir la carpeta';

String get home => '';

Future<bool> openFolder(String folder) async => false;

Future<bool> trashFolder(String folder) async => false;
