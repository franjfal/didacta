/// Los certificados raíz con los que Didacta se fía de un servidor.
///
/// En Windows, Dart no le pregunta al sistema si un certificado vale: copia
/// al arrancar los certificados raíz que hay en el almacén de Windows y
/// comprueba contra esa copia. Pero Windows no los tiene todos de entrada:
/// los baja la primera vez que algún programa suyo los necesita. En un
/// ordenador donde nadie ha abierto todavía GitHub con Edge, la raíz del
/// certificado de GitHub no está, y entrar fallaba con
/// `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`
/// (issue #1).
///
/// Por eso Didacta lleva su propio conjunto de raíces, el de Mozilla que
/// publica curl (`assets/certificados/cacert.pem`), y en Windows lo suma a
/// las del sistema. Sumar y no sustituir: las raíces que pone el servicio
/// de informática de una universidad para su proxy solo están en el
/// almacén de Windows. En macOS y en Linux no hace falta, porque allí sí se
/// pregunta al sistema o se lee su conjunto completo.
///
/// Para ponerlo al día, se baja otra vez y se comprueba con su suma:
///
///     curl -o app/assets/certificados/cacert.pem https://curl.se/ca/cacert.pem
///     curl https://curl.se/ca/cacert.pem.sha256
library;

import 'trusted_roots_stub.dart'
    if (dart.library.io) 'trusted_roots_io.dart'
    as platform;

/// Dónde está el conjunto de raíces dentro de la aplicación.
const String trustedRootsAsset = 'assets/certificados/cacert.pem';

/// Hace que todas las conexiones de la aplicación se fíen también de las
/// raíces de Mozilla, en el sistema que lo necesita. Se llama una vez, al
/// arrancar; si algo falla, se queda con las raíces del sistema.
Future<void> trustBundledRoots() => platform.trustBundledRoots();
