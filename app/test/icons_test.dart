/// Que el icono de la aplicación siga siendo el nuestro.
///
/// Este test existe por una razón concreta y probable: `flutter create`
/// --que es lo que se ejecuta para añadir una plataforma, o para reparar los
/// ficheros de una-- **restaura los iconos por defecto de Flutter** encima de
/// los nuestros, sin avisar. Los PNG están versionados, así que compilar no
/// depende de haberlos generado; lo que no había era nada que se diera cuenta
/// si alguien los pisaba.
///
/// Así que esto no comprueba que el icono sea bonito, que no es comprobable.
/// Comprueba lo que sí lo es: que cada fichero está, que tiene el tamaño que
/// dice su nombre, y que su color es el verde de la casa y no el azul de la
/// plantilla de Flutter. Eso es exactamente el fallo que puede volver.
///
/// Se regeneran con:
///
///     flutter test tool/generate_icons.dart
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/ui/theme.dart';

const String macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

/// Los tamaños que pide `Contents.json` de macOS.
const List<int> macSizes = [16, 32, 64, 128, 256, 512, 1024];

/// Un PNG, leído lo justo para saber de qué tamaño es y de qué color.
///
/// Sin dependencias de imagen: el encabezado de un PNG dice el tamaño en los
/// bytes 16 a 24, y para el color basta descodificarlo con el motor, que ya
/// está aquí.
({int width, int height}) pngSize(Uint8List bytes) {
  expect(bytes.sublist(0, 8), [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: 'no es un PNG');
  final header = ByteData.sublistView(bytes, 16, 24);
  return (width: header.getUint32(0), height: header.getUint32(4));
}

/// El color de un píxel del centro de la baldosa.
Future<Color> centreColour(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData();
  // Un punto arriba a la izquierda del centro: en el centro está la hoja
  // blanca, y lo que interesa es el verde de la baldosa.
  final x = (image.width * 0.22).round();
  final y = (image.height * 0.5).round();
  final offset = (y * image.width + x) * 4;
  final pixel = data!.buffer.asUint8List(data.offsetInBytes + offset, 4);
  image.dispose();
  codec.dispose();
  return Color.fromARGB(pixel[3], pixel[0], pixel[1], pixel[2]);
}

/// Si dos colores son el mismo verde, con margen para el degradado y para la
/// compresión.
bool isDidactaGreen(Color colour) {
  // El icono va del verde claro al oscuro, así que se comprueba la forma del
  // color y no un valor exacto: verde dominante, y ni gris ni azul.
  final r = colour.r;
  final g = colour.g;
  final b = colour.b;
  return colour.a > 0.9 && g > r + 0.06 && g > b + 0.06 && g > 0.2 && g < 0.85;
}

void main() {
  test('los siete iconos de macOS están, y son del tamaño que dicen', () {
    for (final size in macSizes) {
      final file = File('$macDir/app_icon_$size.png');
      expect(file.existsSync(), isTrue, reason: file.path);
      final found = pngSize(file.readAsBytesSync());
      expect(found.width, size, reason: file.path);
      expect(found.height, size, reason: file.path);
    }
  });

  test('el icono es el nuestro, no el de la plantilla de Flutter', () async {
    // El fallo que este test existe para coger: `flutter create` restaura el
    // icono por defecto de Flutter, que es azul, y nadie se enteraría hasta
    // ver el Dock.
    for (final size in [128, 512, 1024]) {
      final colour = await centreColour(File('$macDir/app_icon_$size.png'));
      expect(
        isDidactaGreen(colour),
        isTrue,
        reason:
            'app_icon_$size.png no es verde ($colour). Si acabas de ejecutar '
            '`flutter create`, ha pisado los iconos: regenéralos con '
            '`flutter test tool/generate_icons.dart`.',
      );
    }
  });

  test('los iconos de la web están, con sus tamaños', () {
    final expected = {
      'web/favicon.png': 16,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
    };
    for (final entry in expected.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: entry.key);
      final found = pngSize(file.readAsBytesSync());
      expect(found.width, entry.value, reason: entry.key);
    }
  });

  test('el de la web también es el nuestro', () async {
    final colour = await centreColour(File('web/icons/Icon-512.png'));
    expect(isDidactaGreen(colour), isTrue, reason: '$colour');
  });

  test(
    'el «maskable» llega al borde, que es lo que lo hace maskable',
    () async {
      // El sistema lo recorta con la forma que quiera, así que no puede tener
      // el margen del icono de macOS: una esquina transparente se ve como un
      // mordisco en el círculo.
      final file = File('web/icons/Icon-maskable-512.png');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData())!;
      final pixels = data.buffer.asUint8List(data.offsetInBytes);

      int alphaAt(int x, int y) => pixels[(y * image.width + x) * 4 + 3];

      // Las cuatro esquinas, un píxel dentro.
      for (final (x, y) in [
        (1, 1),
        (image.width - 2, 1),
        (1, image.height - 2),
        (image.width - 2, image.height - 2),
      ]) {
        expect(alphaAt(x, y), 255, reason: 'esquina ($x, $y) transparente');
      }
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'macOS sí lleva margen, que es donde el sistema pone la sombra',
    () async {
      // Y el contrario: el icono de macOS **tiene** que tener la esquina
      // transparente, o el cuadrado redondeado del sistema se ve recortado
      // sobre un cuadrado verde.
      final file = File('$macDir/app_icon_512.png');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData())!;
      final pixels = data.buffer.asUint8List(data.offsetInBytes);
      expect(pixels[3], 0, reason: 'la esquina de arriba a la izquierda pinta');
      image.dispose();
      codec.dispose();
    },
  );

  test('la aplicación de macOS se llama Didacta', () {
    // La plantilla la llama `didacta_app`, que es el nombre del paquete de
    // Dart, y eso es lo que sale en la barra de menú y en el Dock.
    final settings = <String, String>{};
    for (final line in File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsLinesSync()) {
      // Solo los ajustes: un comentario que mencione el valor de la
      // plantilla no es el valor de la plantilla, y buscar en el fichero
      // entero hacía fallar el test por su propia explicación.
      if (line.trimLeft().startsWith('//')) continue;
      final at = line.indexOf('=');
      if (at < 0) continue;
      settings[line.substring(0, at).trim()] = line.substring(at + 1).trim();
    }
    expect(settings['PRODUCT_NAME'], 'Didacta');
    expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], 'es.uv.didacta');
  });

  test('la web también se llama Didacta', () {
    // El manifiesto es lo que el navegador usa al instalarla, y la plantilla
    // lo deja con el nombre del paquete de Dart y «A new Flutter project».
    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, contains('"name": "Didacta"'));
    expect(manifest, contains('"theme_color": "#346E34"'));
    expect(manifest, isNot(contains('A new Flutter project')));

    final index = File('web/index.html').readAsStringSync();
    expect(index, contains('<title>Didacta</title>'));
    expect(index, isNot(contains('A new Flutter project')));
  });

  test('el color de la marca es el del tema, no un verde parecido', () {
    // Que el icono y la interfaz no puedan separarse: si alguien cambia el
    // acento del tema, esto recuerda que hay que regenerar los iconos.
    expect(didactaAccentDark, const Color(0xFF346E34));
  });
}
