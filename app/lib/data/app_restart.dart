/// Cerrar Didacta y volver a abrirla.
///
/// Lo usa «Restablecer». Después de borrar los ajustes, lo que la aplicación
/// tiene en memoria --la sesión, la lista de repositorios, dónde se clonan--
/// sigue siendo lo de antes, y ponerlo todo a cero a mano sería dejarse algo:
/// una carpeta de clones vacía, por ejemplo, haría clonar en la raíz del
/// disco. Arrancar de nuevo lo lee todo otra vez desde cero, que es
/// exactamente lo que se ha pedido.
library;

import 'app_restart_stub.dart'
    if (dart.library.io) 'app_restart_io.dart'
    as platform;

/// Cierra Didacta y la vuelve a abrir. No vuelve.
Future<void> restartApp() => platform.restartApp();
