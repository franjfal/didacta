/// El explorador de archivos, con las órdenes de `model/launch.dart`.
library;

import 'dart:io';

import '../model/launch.dart';
import '../model/toolchain.dart';

bool get supported => true;

String get openLabel => switch (_host) {
  Host.macos => 'Abrir en el Finder',
  Host.windows => 'Abrir en el Explorador',
  Host.linux => 'Abrir la carpeta',
};

String get home =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

Future<bool> openFolder(String folder) async {
  if (!await Directory(folder).exists()) return false;
  final command = folderLaunch(folder: folder, host: _host);
  try {
    final result = await Process.run(command.executable, command.arguments);
    return !exitCodeMeansFailure(_host) || result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<bool> trashFolder(String folder) async {
  final directory = Directory(folder);
  if (!await directory.exists()) return true;
  for (final command in trashFolderLaunches(folder: folder, host: _host)) {
    try {
      await Process.run(command.executable, command.arguments);
    } on ProcessException {
      // Esa orden no está en esta máquina: la siguiente.
      continue;
    }
    // Lo que cuenta es que ya no esté, no lo que diga la orden: `trash` y
    // PowerShell no se ponen de acuerdo en qué código devuelve qué.
    if (!await directory.exists()) return true;
  }
  return false;
}

Host get _host => switch (true) {
  _ when Platform.isMacOS => Host.macos,
  _ when Platform.isWindows => Host.windows,
  _ => Host.linux,
};
