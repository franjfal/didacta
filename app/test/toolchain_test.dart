/// La tabla de qué se instala en cada sistema, leída desde los tres.
///
/// Se prueba aquí y no delante de cada máquina por la razón de siempre: la
/// rama de Windows la escribe alguien en un Mac, y lo único que impide que
/// esté rota es que algo la lea. [Host] es un parámetro justo para esto.
///
/// Lo que se comprueba no es la letra de cada orden --eso cambiará-- sino las
/// propiedades de las que depende la interfaz: que siempre haya un plan que
/// no dependa de nada, que todo plan tenga instrucciones a mano por si falla,
/// y que lo que se descargue vaya por https.
@TestOn('vm')
library;

import 'package:didacta_app/model/toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('leer una versión', () {
    test('de lo que contesta cada programa', () {
      // Tal cual salen. Tres formatos distintos, que es justo por lo que esto
      // busca un número en lugar de partir por espacios.
      expect(versionFrom('git version 2.39.5 (Apple Git-154)'), '2.39.5');
      expect(versionFrom('Python 3.11.4'), '3.11.4');
      // Aquí hay dos números y el bueno es el segundo: se busca el primero
      // **con punto**, que es lo que distingue una versión de un año.
      expect(
        versionFrom('Latexmk, John Collins, 2 January 2024. Version 4.83'),
        '4.83',
      );
    });

    test('sin ninguna versión, null', () {
      // Que el programa conteste algo que no es una versión es información:
      // arrancó. Inventarse un «desconocida» la escondería, y quien llama
      // prefiere quedarse con la primera línea tal cual.
      expect(versionFrom('command not found'), isNull);
      expect(versionFrom('tlmgr revision 69207'), isNull);
      expect(versionFrom(''), isNull);
    });
  });

  group('la versión mínima', () {
    test('3.10 es mayor que 3.9, que comparado como texto no lo es', () {
      // El fallo clásico. Con `compareTo` de cadenas, «3.10» < «3.9» y una
      // Python perfectamente válida quedaría rechazada.
      expect(meetsMinimum('3.10.2', '3.9'), isTrue);
      expect(meetsMinimum('3.9', '3.9'), isTrue);
      expect(meetsMinimum('3.9.18', '3.9'), isTrue);
      expect(meetsMinimum('3.8.10', '3.9'), isFalse);
      expect(meetsMinimum('2.7.18', '3.9'), isFalse);
    });

    test('no haber podido leerla no cierra la puerta', () {
      // Negar el paso por no haber sabido leer una cadena sería el peor de
      // los errores: deja sin usar algo que funciona.
      expect(meetsMinimum(null, '3.9'), isTrue);
    });
  });

  group('las herramientas', () {
    test('cada una dice qué se pierde faltando ella, y no lo mismo', () {
      // Cuatro avisos idénticos no dicen cuál de los cuatro es el urgente. Y
      // lo que se pierde es distinto de verdad: sin git no hay nada que
      // abrir, y sin LaTeX se trabaja igual y solo falta el PDF.
      final dicho = <String>{};
      for (final tool in didactaTools) {
        expect(tool.missing, isNotEmpty, reason: tool.name);
        expect(tool.what, isNotEmpty, reason: tool.name);
        expect(dicho.add(tool.missing), isTrue, reason: tool.name);
      }
    });

    test('solo git impide trabajar; las demás, solo compilar', () {
      expect(toolById(ToolId.git).onlyToCompile, isFalse);
      expect(toolById(ToolId.latex).onlyToCompile, isTrue);
      expect(toolById(ToolId.python).onlyToCompile, isTrue);
      expect(toolById(ToolId.engine).onlyToCompile, isTrue);
    });

    test('git va antes que el motor, que se descarga con git', () {
      final orden = didactaTools.map((tool) => tool.id).toList();
      expect(orden.indexOf(ToolId.git), lessThan(orden.indexOf(ToolId.engine)));
    });
  });

  group('los planes', () {
    test('siempre acaban en uno que no depende de nada', () {
      // Es lo que permite que `choose` nunca devuelva null y que la interfaz
      // no tenga que dibujar la fila sin botón y sin explicación.
      for (final host in Host.values) {
        for (final tool in didactaTools) {
          final plans = plansFor(tool.id, host);
          expect(plans, isNotEmpty, reason: '${tool.name} en ${host.name}');
          expect(
            plans.last.needs,
            isNull,
            reason:
                'El último plan de ${tool.name} en ${host.name} depende de '
                '${plans.last.needs}, así que en una máquina sin eso no queda '
                'ninguno.',
          );
        }
      }
    });

    test('todos tienen cómo hacerlo a mano', () {
      // El modal de fallo se apoya en esto. Un plan automático sin
      // instrucciones deja el peor modal posible: «no se pudo» y nada más.
      for (final host in Host.values) {
        for (final tool in didactaTools) {
          for (final plan in plansFor(tool.id, host)) {
            expect(
              plan.manualSteps,
              isNotEmpty,
              reason:
                  '«${plan.label}» (${tool.name}, ${host.name}) no dice cómo '
                  'hacerlo a mano.',
            );
          }
        }
      }
    });

    test('lo que se descarga va por https y tiene nombre', () {
      // Lo descargado se ejecuta. Una dirección sin cifrar es una dirección
      // que cualquiera en la red puede contestar, y un fichero sin extensión
      // en Windows no se puede lanzar.
      for (final host in Host.values) {
        for (final tool in didactaTools) {
          for (final plan in plansFor(tool.id, host)) {
            if (plan.kind != InstallKind.script &&
                plan.kind != InstallKind.installer) {
              continue;
            }
            expect(plan.url, isNotNull, reason: plan.label);
            expect(
              Uri.parse(plan.url!).scheme,
              'https',
              reason: '${plan.label} descarga sin cifrar.',
            );
            expect(plan.filename, isNotNull, reason: plan.label);
          }
        }
      }
    });

    test('una orden sin programa no se puede lanzar', () {
      for (final host in Host.values) {
        for (final tool in didactaTools) {
          for (final plan in plansFor(tool.id, host)) {
            if (plan.kind != InstallKind.command) continue;
            expect(plan.program, isNotNull, reason: plan.label);
            expect(plan.arguments, isNotEmpty, reason: plan.label);
          }
        }
      }
    });

    test('el motor lo instala Didacta, no una orden del sistema', () {
      for (final host in Host.values) {
        final plans = plansFor(ToolId.engine, host);
        expect(plans, hasLength(1));
        expect(plans.single.kind, InstallKind.own);
      }
    });
  });

  group('las distribuciones de TeX', () {
    test('hay una recomendada en cada sistema, y no pide administrador', () {
      // La recomendada es la que se ofrece marcada, así que tiene que ser la
      // que funciona sin ayuda de nadie: en un ordenador de la universidad,
      // «pide la contraseña de administrador» quiere decir «no puedes».
      for (final host in Host.values) {
        final options = latexOptions(host);
        final recommended = options.where((option) => option.recommended);
        expect(recommended, hasLength(1), reason: host.name);
        expect(recommended.single.needsAdmin, isFalse, reason: host.name);
        expect(recommended.single.plan.automatic, isTrue, reason: host.name);
      }
    });

    test('todas dicen cuánto ocupan y a dónde ir si falla', () {
      // El tamaño es el dato que de verdad decide entre TinyTeX y MacTeX, y
      // la guía es a donde hay que mandar a alguien cuando lo que sabemos
      // hacer no ha bastado.
      for (final host in Host.values) {
        for (final option in latexOptions(host)) {
          expect(option.size, isNotEmpty, reason: option.name);
          expect(option.what, isNotEmpty, reason: option.name);
          expect(Uri.parse(option.guide).scheme, 'https', reason: option.name);
        }
      }
    });

    test('las de macOS son las tres de la documentación', () {
      expect(latexOptions(Host.macos).map((option) => option.id), [
        'tinytex',
        'basictex',
        'mactex',
      ]);
    });
  });

  group('los paquetes de TeX', () {
    test('están los que el preámbulo carga sí o sí', () {
      // Sin beamer no hay diapositivas y sin babel-spanish no compila una
      // unidad en castellano, que es el caso de todas.
      expect(didactaTexPackages, contains('latexmk'));
      expect(didactaTexPackages, contains('beamer'));
      expect(didactaTexPackages, contains('pgfplots'));
      expect(didactaTexPackages, contains('tcolorbox'));
      expect(didactaTexPackages, contains('babel-spanish'));
    });

    test('uno por idioma de latex/lang', () {
      // Babel carga el fichero del idioma por nombre: sin él la compilación
      // para en seco aunque el texto esté perfecto.
      for (final language in [
        'spanish',
        'catalan',
        'english',
        'german',
        'basque',
        'french',
        'galician',
        'italian',
        'portuges',
      ]) {
        expect(didactaTexPackages, contains('babel-$language'));
      }
    });

    test('sin repetidos: tlmgr los lee de una lista', () {
      expect(didactaTexPackages.toSet(), hasLength(didactaTexPackages.length));
    });
  });
}
