/// En la web no hay carpetas que abrir ni que tirar.
library;

import '../l10n/tr.dart';

bool get supported => false;

String get openLabel => tr('Abrir la carpeta');

String get revealIn => tr('en su carpeta');

String get home => '';

Future<bool> openFolder(String folder) async => false;

Future<bool> trashFolder(String folder) async => false;
