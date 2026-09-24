/// Qué carpetas no se mandan nunca a la Papelera.
///
/// Se prueba porque es lo único que se interpone entre un botón y la carpeta
/// equivocada: la lista de repositorios la puede haber escrito cualquiera, y
/// una ruta mal guardada puede ser la carpeta de usuario entera.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/folder_safety.dart';

String? why(
  String folder, {
  String home = '/Users/ana',
  String base = '/Users/ana/Didacta',
  String? engine = '/Users/ana/Didacta/didacta',
  List<String> others = const [],
}) => whyNotTrash(
  folder,
  home: home,
  cloneBase: base,
  engine: engine,
  others: others,
);

void main() {
  test('la carpeta de un repositorio, sí', () {
    expect(why('/Users/ana/Didacta/curso'), isNull);
    // Añadido desde el disco, fuera de la carpeta de los clones: también.
    expect(why('/Users/ana/Documentos/apuntes'), isNull);
  });

  test('la carpeta de usuario, la raíz y lo que las contiene, no', () {
    expect(why('/Users/ana'), contains('carpeta de usuario'));
    expect(why('/Users/ana/'), contains('carpeta de usuario'));
    expect(why('/Users'), contains('dentro está tu carpeta de usuario'));
    expect(why('/'), contains('raíz'));
  });

  test('la carpeta de todos los clones, no', () {
    expect(why('/Users/ana/Didacta'), contains('se clonan todos'));
  });

  test('el motor, ni entero ni un trozo', () {
    expect(why('/Users/ana/Didacta/didacta'), contains('motor'));
    expect(why('/Users/ana/Didacta/didacta/cli'), contains('dentro del motor'));
  });

  test('ni una que tenga dentro otro repositorio, ni una dentro de otro', () {
    expect(
      why('/Users/ana/Documentos', others: ['/Users/ana/Documentos/apuntes']),
      contains('otro repositorio'),
    );
    expect(
      why('/Users/ana/Didacta/curso/sub', others: ['/Users/ana/Didacta/curso']),
      contains('dentro de otro repositorio'),
    );
  });

  test('una que empieza igual no está dentro', () {
    // `/Users/ana/Didacta2` no está dentro de `/Users/ana/Didacta`.
    expect(why('/Users/ana/Didacta2'), isNull);
  });

  test('una ruta a medias, no', () {
    expect(why(''), isNotNull);
    expect(why('curso'), contains('ruta completa'));
  });

  test('en Windows, sin fijarse en mayúsculas ni en barras', () {
    expect(
      why(
        r'c:\users\ana',
        home: r'C:\Users\Ana',
        base: r'C:\Users\Ana\Didacta',
        engine: null,
      ),
      contains('carpeta de usuario'),
    );
    expect(
      why(r'C:\', home: r'C:\Users\Ana', base: '', engine: null),
      contains('raíz'),
    );
    expect(
      why(
        r'C:\Users\Ana\Didacta\curso',
        home: r'C:\Users\Ana',
        base: r'C:\Users\Ana\Didacta',
        engine: null,
      ),
      isNull,
    );
  });
}
