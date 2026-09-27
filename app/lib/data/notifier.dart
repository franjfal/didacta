/// Los avisos del sistema: el centro de notificaciones del Mac, las de
/// Windows y las de Linux.
///
/// Una clase y no una función suelta para que las pruebas pongan la suya: un
/// test que compila no puede ir dejando notificaciones en el ordenador de
/// quien lo ejecuta.
library;

import 'package:flutter/widgets.dart';

import 'notifier_stub.dart' if (dart.library.io) 'notifier_io.dart' as platform;

class SystemNotifier {
  const SystemNotifier();

  /// Si aquí se pueden enseñar. En la web, no.
  bool get supported => platform.supported;

  /// Si Didacta es la ventana de delante.
  ///
  /// Un aviso solo tiene sentido para quien se ha ido a otra: con Didacta
  /// delante, lo que diría ya está en la pantalla.
  bool get appInFront =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Enseña un aviso. Devuelve si se pudo.
  ///
  /// No lanza nunca: un aviso que no sale no puede estropear la compilación
  /// que acaba de terminar bien.
  Future<bool> show({required String title, required String body}) =>
      platform.show(title: title, body: body);
}
