/// En web no hay sistema que actualizar: la página se recarga sola.
library;

import '../model/update_manifest.dart';

UpdatePlatform? currentPlatform() => null;

String currentArchitecture() => 'web';
