/// Abrir una dirección en el navegador del sistema.
///
/// Existe para un paso concreto del *device flow*: el código hay que
/// escribirlo en github.com, y hasta ahora la aplicación se limitaba a enseñar
/// la dirección y ofrecer un botón de copiar. Abrirla es la diferencia entre
/// «copia esto, abre el navegador, pega aquello» y «autoriza», que es lo único
/// que de verdad tiene que hacer una persona.
///
/// Con el `open` del sistema y no con una dependencia más: la aplicación ya
/// lanza procesos --git, el motor, el visor de PDF-- así que lanzar uno más no
/// añade nada que no estuviera, y sí lo añadiría un paquete.
library;

import 'browser_stub.dart' if (dart.library.io) 'browser_io.dart' as platform;

/// Abre [url] donde el sistema abra las direcciones.
///
/// Devuelve si se pudo. No lanza: que no se abra el navegador no puede
/// llevarse por delante el flujo que lo pedía, y quien llama tiene siempre el
/// camino a mano --la dirección en pantalla, y el botón de copiarla--.
Future<bool> openLink(String url) => platform.openLink(url);
