/// Que comparar versiones no sea comparar cadenas.
///
/// El fallo que estos tests existen para coger no se ve: si `1.10.0` se
/// considera menor que `1.9.0` --que es lo que pasa comparando texto-- la
/// aplicación no falla, simplemente **deja de ofrecer actualizaciones** y
/// nadie se entera hasta que alguien pregunta por qué sigue con la de hace
/// tres meses.
library;

import 'package:didacta_app/model/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('leer una versión', () {
    test('la forma normal', () {
      final version = AppVersion.parse('1.4.2');
      expect(version.major, 1);
      expect(version.minor, 4);
      expect(version.patch, 2);
      expect(version.isPreRelease, isFalse);
      expect(version.build, isNull);
      expect(version.toString(), '1.4.2');
      expect(version.tag, 'v1.4.2');
    });

    test('con el build de pubspec', () {
      final version = AppVersion.parse('1.4.2+142');
      expect(version.build, 142);
      // El build no sale al enseñarla: no ordena nada, así que no distingue.
      expect(version.toString(), '1.4.2');
    });

    test('con la v del tag delante', () {
      // Para poder leer directamente el `tag_name` que devuelve GitHub.
      expect(AppVersion.parse('v1.4.2'), AppVersion.parse('1.4.2'));
    });

    test('una preliberación', () {
      final version = AppVersion.parse('1.4.2-rc.1');
      expect(version.isPreRelease, isTrue);
      expect(version.preRelease, ['rc', '1']);
      expect(version.toString(), '1.4.2-rc.1');
    });

    test('lo que no es una versión da null y no revienta', () {
      // Esto lee lo que venga de la red. Un manifiesto roto es un caso
      // normal que se maneja, no una excepción que sube hasta la interfaz.
      for (final bad in [
        '',
        '1.4',
        '1.4.2.3',
        'uno.cuatro.dos',
        '1.4.x',
        '-1.4.2',
        '1.4.2-',
        '1.4.2-rc..1',
        ' 1.4.2 extra',
        'latest',
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '«$bad»');
      }
      expect(AppVersion.tryParse(null), isNull);
    });

    test('espacios alrededor sí se perdonan', () {
      expect(AppVersion.tryParse('  1.4.2  ')?.toString(), '1.4.2');
    });
  });

  group('comparar', () {
    AppVersion v(String text) => AppVersion.parse(text);

    test('el caso que rompe comparar como texto', () {
      // '1.10.0' < '1.9.0' es cierto como cadena y falso como versión. Este
      // es el test que justifica todo el fichero.
      expect(v('1.10.0') > v('1.9.0'), isTrue);
      expect(v('1.0.10') > v('1.0.9'), isTrue);
      expect(v('2.0.0') > v('10.0.0'), isFalse);
    });

    test('por major, luego minor, luego patch', () {
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.5.0') > v('1.4.99'), isTrue);
      expect(v('1.4.3') > v('1.4.2'), isTrue);
    });

    test('iguales', () {
      expect(v('1.4.2') == v('1.4.2'), isTrue);
      expect(v('1.4.2') >= v('1.4.2'), isTrue);
      expect(v('1.4.2') > v('1.4.2'), isFalse);
    });

    test('el build no ordena', () {
      // Por especificación. Dos builds de la misma versión son la misma
      // versión, y ofrecer «actualizar» de 1.4.2+1 a 1.4.2+2 sería ofrecer
      // lo mismo con otro número.
      expect(v('1.4.2+1') > v('1.4.2+9'), isFalse);
      expect(v('1.4.2+9') > v('1.4.2+1'), isFalse);
    });

    test('una preliberación va antes que la final', () {
      // La regla que impide que quien tenga una rc se quede sin la versión
      // de verdad.
      expect(v('1.4.2-rc.1') < v('1.4.2'), isTrue);
      expect(v('1.4.2') > v('1.4.2-rc.9'), isTrue);
    });

    test('entre preliberaciones', () {
      expect(v('1.4.2-rc.1') < v('1.4.2-rc.2'), isTrue);
      expect(v('1.4.2-rc.2') < v('1.4.2-rc.10'), isTrue); // numérico, no texto
      expect(v('1.4.2-alpha') < v('1.4.2-beta'), isTrue);
      expect(v('1.4.2-rc') < v('1.4.2-rc.1'), isTrue); // menos es menor
      expect(v('1.4.2-1') < v('1.4.2-alpha'), isTrue); // numérico antes
    });

    test('se pueden ordenar', () {
      final versions = [
        v('1.10.0'),
        v('1.2.0'),
        v('2.0.0'),
        v('1.2.0-rc.1'),
        v('1.9.9'),
      ]..sort();
      expect(versions.map((each) => each.toString()).toList(), [
        '1.2.0-rc.1',
        '1.2.0',
        '1.9.9',
        '1.10.0',
        '2.0.0',
      ]);
    });
  });
}
