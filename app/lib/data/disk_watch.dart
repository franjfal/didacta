/// Enterarse de que el disco ha cambiado mientras la aplicación está abierta.
///
/// Hace falta porque el índice se puede regenerar por fuera: desde el
/// terminal, desde otra ventana, o por otra persona en el mismo clon. La
/// comprobación del arranque no cubre eso --lee el índice una vez y ya está--
/// y el resultado es una biblioteca que enseña lo de hace media hora sin dar
/// ninguna pista de que ya no es verdad.
///
/// Dos señales, porque ninguna de las dos basta sola:
///
/// * **el vigilante del sistema de ficheros**, que avisa en cuanto
///   `generated/` cambia. Es inmediato y no cuesta nada, pero se pierde
///   eventos --un `mv` atómico, un volumen de red, un clon que se sustituye
///   entero-- y no hay forma de saber cuándo;
/// * **la fecha del índice al volver a la ventana**, que es dos `stat` y coge
///   todo lo que el vigilante se haya perdido. Volver a la aplicación después
///   de tocar algo fuera es exactamente cuando hay que mirar.
library;

import 'disk_watch_stub.dart'
    if (dart.library.io) 'disk_watch_io.dart'
    as platform;

/// Avisa cuando algo cambia dentro de `generated/` del clon.
///
/// Un flujo sin valor: lo único que dice es «vuelve a mirar». Qué cambió lo
/// contesta releer el índice, que es barato y no puede equivocarse.
Stream<void> watchIndex(String directory) => platform.watchIndex(directory);

/// Cuándo se escribió el índice por última vez, o null si no está.
Future<DateTime?> indexModified(String directory) =>
    platform.indexModified(directory);
