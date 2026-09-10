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

    stdout.writeln(
      'iconos escritos: ${macSizes.length} para macOS y 5 para la web',
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

Future<void> _write(String path, ByteData bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${bytes.lengthInBytes ~/ 1024} kB  $path');
}
