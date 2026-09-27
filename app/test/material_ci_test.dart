/// Compilar el material en GitHub: el workflow de cada repositorio de
/// contenido, el reutilizable que llama, y no escribirlo con un token que
/// GitHub no deja enviar.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/material_ci.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

void main() {
  group('el workflow del repositorio de contenido', () {
    final text = materialWorkflow(engineRef: 'v1.2.3');

    test('llama al del motor, en la versión de esta aplicación', () {
      expect(
        text,
        contains(
          'uses: franjfal/didacta/.github/workflows/material.yml@v1.2.3',
        ),
      );
      expect(text, contains('engine-ref: v1.2.3'));
      expect(isMaterialWorkflow(text), isTrue);
    });

    test('no compila otra vez por lo que el propio workflow escribe', () {
      expect(text, contains('"generated/**"'));
      expect(text, contains('"site/**"'));
    });

    test('una compilación de desarrollo, contra main', () {
      expect(materialEngineRef(const AppVersion(0, 0, 0)), 'main');
      expect(materialEngineRef(const AppVersion(0, 2, 1)), 'v0.2.1');
    });

    test('uno escrito a mano no es el de Didacta', () {
      expect(isMaterialWorkflow('name: CI\non: push\n'), isFalse);
    });
  });

  group('el reutilizable, en este repositorio', () {
    // Lo que el de cada repositorio llama tiene que existir: un `uses:` a un
    // fichero que no está deja el CI roto en cuanto alguien lo añade.
    final file = File('../$materialWorkflowPath');

    test('existe, y se puede llamar', () {
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('workflow_call:'));
    });

    test('separa lo que se reparte de lo del profesor', () {
      final text = file.readAsStringSync();
      expect(text, contains('--to "salida/repartir/'));
      expect(text, contains('--reveal-up-to teacher --to "salida/profesor/'));
      // El HTML, con lo de repartir y sin `--reveal-up-to`.
      expect(text, contains('didacta html "\$curso" \\\n'));
      expect(text, contains('--to "salida/repartir/\$carpeta/html"'));
      // Lo que se reparte, sin `--reveal-up-to`: lo del estudiante, que es
      // lo que hace `didacta export` por defecto.
      final repartir = RegExp(
        r'export "\$curso" \\\s*\n\s*--to "salida/repartir/',
      );
      expect(repartir.hasMatch(text), isTrue);
    });
  });

  group('añadirlo desde Ajustes', () {
    FakeSession make(FakeGateway gateway) => FakeSession(
      gatewayOverride: gateway,
      catalogue: catalogueWith(defaultUnits()),
    );

    test('se escribe como un cambio más', () async {
      final gateway = FakeGateway();
      final session = make(gateway);
      expect(await session.hasMaterialCi('test/repo'), isFalse);

      await session.addMaterialCi('test/repo');

      expect(gateway.commits.single.path, materialWorkflowPath);
      expect(isMaterialWorkflow(gateway.commits.single.text), isTrue);
      expect(await session.hasMaterialCi('test/repo'), isTrue);
    });

    test(
      'con un token de antes del permiso, no escribe nada y lo dice',
      () async {
        final gateway = FakeGateway();
        final session = make(gateway)..workflowsAllowed = false;

        await expectLater(
          session.addMaterialCi('test/repo'),
          throwsA(isA<MaterialCiException>()),
        );
        expect(gateway.commits, isEmpty);
      },
    );

    test('sin poder preguntar, tampoco', () async {
      final gateway = FakeGateway();
      final session = make(gateway)..workflowsAllowed = null;
      await expectLater(
        session.addMaterialCi('test/repo'),
        throwsA(
          isA<MaterialCiException>().having(
            (error) => error.unknown,
            'unknown',
            isTrue,
          ),
        ),
      );
      expect(gateway.commits, isEmpty);
    });
  });
}
