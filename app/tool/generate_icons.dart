/// Genera los iconos de la aplicación a partir de `lib/ui/brand.dart`.
///
///     cd app && flutter test tool/generate_icons.dart
///
/// Se ejecuta con el arnés de tests porque necesita un motor de Flutter para
/// rasterizar, y usa **el mismo rasterizador que la aplicación**: lo que
/// aparece en el Dock es exactamente lo que se pinta en el carril, del mismo
/// código.
///
/// Por qué esto y no un PNG dibujado a mano, o un SVG con una herramienta que
/// lo convierta:
///
/// * **regenerarlo solo necesita Flutter**, que ya hace falta para compilar la
///   aplicación. Ninguna dependencia nueva, ninguna herramienta que haya que
///   instalar, y funciona en cualquier máquina que pueda construir Didacta;
/// * **el diseño se lee en un diff.** Las proporciones son constantes con
///   nombre en `brand.dart`; cambiar el icono es cambiar un número y volver a
///   ejecutar esto, no abrir un editor de imágenes;
/// * **una sola marca.** Un icono dibujado aparte se separa de la interfaz en
///   el primer retoque.
///
/// Los PNG resultantes **se versionan**, así que compilar no depende de haber
/// ejecutado esto. Lo único que puede pisarlos es `flutter create`, que
/// restaura los iconos por defecto de Flutter; para eso está
/// `test/icons_test.dart`, que falla si los iconos dejan de ser los nuestros.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/ui/brand.dart';

/// Los tamaños que pide el conjunto de iconos de macOS.
///
/// Los nombres los fija la plantilla de Flutter en `Contents.json`, y ese
/// fichero mapea cada tamaño a su escala 1x y 2x: `app_icon_32.png` es a la
/// vez el 32 a 1x y el 16 a 2x.
const List<int> macSizes = [16, 32, 64, 128, 256, 512, 1024];

const String macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

/// Los tamaños que lleva dentro un `.ico` de Windows.
///
/// Uno por sitio donde Windows enseña un icono: 16 en la barra de título, 32
/// en el explorador, 48 en el escritorio, 256 en la vista de iconos grandes.
/// Un `.ico` con uno solo se reescala a los demás, y reescalar un 256 a 16
/// da una mancha.
const List<int> windowsSizes = [16, 24, 32, 48, 64, 128, 256];

const String windowsIcon = 'windows/runner/resources/app_icon.ico';

/// El de Linux, para el AppImage y para el escritorio.
const String linuxDir = '../packaging/linux';

void main() {
  test('los iconos de la aplicación', () async {
    // La raíz del proyecto: `flutter test` corre desde `app/`.
    final root = Directory.current.path;

    for (final size in macSizes) {
      final bytes = await _render(
        size,
        // macOS quiere el cuadrado redondeado sin llegar al borde: 824 de
        // 1024, o sea un 9,8% por lado. El sistema pone la sombra.
        padding: 0.0977,
      );
      await _write('$root/$macDir/app_icon_$size.png', bytes);
    }

    // La web. `favicon.png` lo usa el navegador en la pestaña; los `Icon-*`
    // son del manifiesto, para cuando alguien la instala.
    await _write(
      '$root/web/favicon.png',
      // A 16 px el margen de macOS se come la mitad del dibujo, y una
      // pestaña no necesita hueco para una sombra que no hay.
      await _render(16, padding: 0.02),
    );
    for (final size in [192, 512]) {
      await _write(
        '$root/web/icons/Icon-$size.png',
        await _render(size, padding: 0.04),
      );
    }

    // Los «maskable» los recorta el sistema con la forma que quiera --un
    // círculo en Android--, así que van a sangre y con la marca dentro del
    // 80% central, que es lo único que la especificación garantiza visible.
    for (final size in [192, 512]) {
      await _write(
        '$root/web/icons/Icon-maskable-$size.png',
        // Sin margen --el verde llega al borde-- y con la marca metida hacia
        // dentro: es lo que la especificación garantiza visible después del
        // recorte.
        await _render(size, padding: 0, rounded: false, markInset: 0.20),
      );
    }

    // Windows. Un `.ico` es un contenedor de PNG con una tabla delante, así
    // que se escribe a mano: traer una dependencia de imágenes para componer
    // seis cabeceras de 16 bytes sería pagar mucho por poco.
    final windows = <int, Uint8List>{};
    for (final size in windowsSizes) {
      // Menos margen que en macOS: aquí no hay cuadrado redondeado del
      // sistema ni sombra, y el margen de macOS deja el dibujo pequeño.
      final bytes = await _render(size, padding: 0.04);
      windows[size] = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    }
    await File('$root/$windowsIcon').writeAsBytes(_ico(windows), flush: true);
    stdout.writeln('  ${_ico(windows).length ~/ 1024} kB  $root/$windowsIcon');

    // Linux: PNG sueltos, que es lo que quieren el `.desktop` y el AppImage.
    for (final size in [256, 512]) {
      await _write(
        '$root/$linuxDir/didacta-$size.png',
        await _render(size, padding: 0.04),
      );
    }

    stdout.writeln(
      'iconos escritos: ${macSizes.length} para macOS, 5 para la web, '
      'uno para Windows y 2 para Linux',
    );
  });
}

/// Pinta el icono a [size] píxeles y devuelve el PNG.
Future<ByteData> _render(
  int size, {
  required double padding,
  bool rounded = true,
  double markInset = 0.055,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintDidactaIcon(
    canvas,
    Size(size.toDouble(), size.toDouble()),
    padding: padding,
    rounded: rounded,
    markInset: markInset,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (png == null) {
    throw StateError('no se pudo codificar el PNG de $size px');
  }
  return png;
}

/// Empaqueta varios PNG en un `.ico`.
///
/// El formato es una cabecera de 6 bytes, una entrada de 16 por imagen y los
/// datos detrás. Las entradas guardan el tamaño en **un byte**, y por eso 256
/// se escribe como 0: es la convención del formato, no un error.
Uint8List _ico(Map<int, Uint8List> images) {
  final entries = images.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final header = BytesBuilder();
  final directory = ByteData(16 * entries.length);
  var offset = 6 + 16 * entries.length;

  for (var i = 0; i < entries.length; i++) {
    final size = entries[i].key;
    final data = entries[i].value;
    final at = i * 16;
    directory.setUint8(at + 0, size >= 256 ? 0 : size);
    directory.setUint8(at + 1, size >= 256 ? 0 : size);
    directory.setUint8(at + 2, 0); // sin paleta
    directory.setUint8(at + 3, 0); // reservado
    directory.setUint16(at + 4, 1, Endian.little); // planos
    directory.setUint16(at + 6, 32, Endian.little); // bits por píxel
    directory.setUint32(at + 8, data.length, Endian.little);
    directory.setUint32(at + 12, offset, Endian.little);
    offset += data.length;
  }

  header.add([0, 0, 1, 0, entries.length & 0xFF, entries.length >> 8]);
  header.add(directory.buffer.asUint8List());
  for (final entry in entries) {
    header.add(entry.value);
  }
  return header.toBytes();
}

Future<void> _write(String path, ByteData bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${bytes.lengthInBytes ~/ 1024} kB  $path');
}
