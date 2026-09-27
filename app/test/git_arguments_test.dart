/// Lo que se le pasa a git, sin lanzarlo.
///
/// Los topes y `lowSpeedLimit` son lo que impide que un guardado se quede
/// colgado con la red a medias. Quitarlos sin querer no falla en ningún test
/// que lance git de verdad --con red buena todo termina--, así que se fijan
/// aquí, mirando los argumentos.
@TestOn('vm')
library;

import 'package:didacta_app/data/local_clone_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('el tope de tiempo', () {
    test('clonar tiene más margen que lo demás de la red', () {
      expect(gitTimeLimit(['clone', 'x', 'y']), const Duration(minutes: 15));
      for (final command in ['fetch', 'pull', 'push', 'ls-remote']) {
        expect(gitTimeLimit([command]), const Duration(minutes: 5));
      }
    });

    test('lo local, poco', () {
      for (final command in ['status', 'commit', 'add', 'diff']) {
        expect(gitTimeLimit([command]), const Duration(minutes: 2));
      }
    });

    test('la orden se lee detrás de los -c', () {
      expect(
        gitTimeLimit(['-c', 'user.name=Ana', 'push', 'origin']),
        const Duration(minutes: 5),
      );
    });
  });

  group('los argumentos', () {
    test('la red corta una conexión muerta antes del tope', () {
      for (final command in ['clone', 'fetch', 'pull', 'push', 'ls-remote']) {
        final full = gitArguments([command]);
        expect(full, containsAllInOrder(['-c', 'http.lowSpeedLimit=1000']));
        expect(full, containsAllInOrder(['-c', 'http.lowSpeedTime=30']));
      }
    });

    test('lo local no lleva lo de la red', () {
      final full = gitArguments(['status', '--porcelain', '-z']);
      expect(full.where((each) => each.startsWith('http.')), isEmpty);
    });

    test('siempre las rutas tal cual y sin convertir el fin de línea', () {
      for (final command in ['status', 'push']) {
        final full = gitArguments([command]);
        expect(full, containsAllInOrder(['-c', 'core.quotePath=false']));
        expect(full, containsAllInOrder(['-c', 'core.autocrlf=false']));
      }
    });

    test('la orden va al final, detrás de toda la configuración', () {
      final full = gitArguments(['push', 'origin', 'main'], token: 'ghp_x');
      expect(full.sublist(full.length - 3), ['push', 'origin', 'main']);
    });

    test('el token nunca va en los argumentos', () {
      final full = gitArguments(['push'], token: 'ghp_secreto');
      expect(full.join(' '), isNot(contains('ghp_secreto')));
      expect(full, contains('credential.helper='));
    });

    test('sin token, sin ayudante', () {
      final full = gitArguments(['push']);
      expect(full.where((each) => each.startsWith('credential.')), isEmpty);
    });
  });
}
