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

  test('el icono de Windows está, y lleva los siete tamaños dentro', () {
    // `flutter create --platforms=windows` deja el icono azul de Flutter, y
    // un `.ico` con un solo tamaño se reescala fatal a 16 px. Se comprueba la
    // estructura del contenedor, que es lo comprobable sin descodificar.
    final bytes = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final header = ByteData.sublistView(bytes, 0, 6);
    expect(header.getUint16(0, Endian.little), 0, reason: 'reservado');
    expect(header.getUint16(2, Endian.little), 1, reason: 'tipo: icono');
    final count = header.getUint16(4, Endian.little);
    expect(count, 7, reason: 'los siete tamaños');

    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      final entry = ByteData.sublistView(bytes, 6 + i * 16, 22 + i * 16);
      // 256 se guarda como 0: es la convención del formato, no un error.
      final width = entry.getUint8(0);
      sizes.add(width == 0 ? 256 : width);
      final offset = entry.getUint32(12, Endian.little);
      // Cada entrada es un PNG de verdad, no relleno.
      expect(
        bytes.sublist(offset, offset + 8),
        [137, 80, 78, 71, 13, 10, 26, 10],
        reason: 'la entrada de ${sizes.last} px no es un PNG',
      );
    }
    expect(sizes, [16, 24, 32, 48, 64, 128, 256]);
  });

  test('el icono de Windows es el nuestro, no el azul de Flutter', () async {
    // El 256 de dentro del `.ico`, sacado por su desplazamiento.
    final bytes = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final entry = ByteData.sublistView(bytes, 6 + 6 * 16, 22 + 6 * 16);
    final offset = entry.getUint32(12, Endian.little);
    final length = entry.getUint32(8, Endian.little);
    final png = bytes.sublist(offset, offset + length);

    final temp = File(
      '${Directory.systemTemp.path}/didacta-icon-test.png',
    )..writeAsBytesSync(png);
    addTearDown(() => temp.deleteSync());
    expect(await centreColour(temp), predicate(isDidactaGreen), reason: 'azul');
  });

  test('el icono de Linux está, para el AppImage y el escritorio', () {
    for (final size in [256, 512]) {
      final file = File('../packaging/linux/didacta-$size.png');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(pngSize(file.readAsBytesSync()).width, size);
    }
  });

  test('el .desktop de Linux nombra el binario que de verdad se genera', () {
    // `Exec=didacta` tiene que coincidir con el `BINARY_NAME` del CMake: si
    // se separan, el AppImage se construye y no arranca.
    final desktop = File('../packaging/linux/didacta.desktop').readAsStringSync();
    expect(desktop, contains('Exec=didacta'));
    expect(desktop, contains('Name=Didacta'));
    expect(desktop, contains('Icon=didacta'));

    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(BINARY_NAME "didacta")'));
    expect(cmake, contains('set(APPLICATION_ID "es.uv.didacta")'));
  });

  test('Windows también se llama Didacta, no didacta_app', () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(rc, contains('"ProductName", "Didacta"'));
    expect(rc, isNot(contains('didacta_app')));

    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main, contains('L"Didacta"'));

    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(BINARY_NAME "didacta")'));
  });

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
