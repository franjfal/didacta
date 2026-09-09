/// The web's answer to a local clone: there isn't one.
///
/// A browser has no filesystem and no way to run git, and pretending
/// otherwise would put a folder picker in Ajustes that could never work. The
/// web path is the Worker, which is a different and complete answer.
library;

import 'local_clone.dart';

bool get supported => false;

Future<bool> gitAvailable() async => false;

LocalClone makeClone({required String directory}) => throw const CloneException(
  'Un navegador no puede tener un clon del repositorio: no hay sistema '
  'de ficheros ni forma de ejecutar git. En web el acceso va por la API.',
);

Future<LocalClone> cloneInto({
  required String directory,
  required String owner,
  required String repo,
  required String branch,
  required String token,
  void Function(String line)? onProgress,
}) async => makeClone(directory: directory);
