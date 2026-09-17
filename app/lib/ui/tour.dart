/// El tour guiado: señalar una parte de la interfaz y decir para qué es.
///
/// Existe porque la bienvenida contesta «qué es esto» y deja sin contestar
/// «dónde está cada cosa», que es la pregunta de los cinco minutos
/// siguientes. Un vídeo o una página de la documentación también la
/// contestan, pero no sobre la ventana que la persona tiene delante, que es
/// donde tiene que acabar sabiéndolo.
///
/// Tres decisiones, y las tres son por lo mismo --que un tutorial que estorba
/// se cierra a los diez segundos y no se vuelve a abrir--:
///
/// **Se sale en cualquier momento**, con el botón, con ++esc++ o pulsando
/// fuera. Y salirse cuenta como hecho: no vuelve solo.
///
/// **Un paso cuyo objetivo no está montado se salta.** El carril no existe en
/// una ventana estrecha --allí es una barra abajo-- y una pantalla puede no
/// tener la barra de sincronización. Un tour que se queda señalando el vacío
/// es peor que uno corto.
///
/// **No navega.** Todos los pasos son del armazón, que está en todas las
/// pantallas. Un tour que cambia de pantalla debajo de quien lo lee le quita
/// lo que estaba mirando, y además tendría que saber deshacerlo al acabar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Un paso: a qué parte señala y qué dice de ella.
class TourStep {
  const TourStep({required this.id, required this.title, required this.body});

  /// El identificador del [TourTarget] al que señala.
  final String id;

  final String title;
  final String body;
}

/// Los pasos del tour, en orden.
///
/// Todos son del armazón a propósito (ver la cabecera de este fichero).
const List<TourStep> defaultTour = [
  TourStep(
    id: 'rail',
    title: 'Cuatro sitios',
    body:
        'Asignaturas es lo que estás dando este cuatrimestre, y por eso va '
        'primero. La biblioteca es todo el material ordenado por materia, que '
        'es cómo se busca. Traducción es la cola de lo que falta. Y Ajustes.',
  ),
  TourStep(
    id: 'rail-library',
    title: 'La biblioteca',
    body:
        'El material de todos tus repositorios, junto y en árbol. Al escribir '
        'cambia a búsqueda y se aplana: «hilbert» no es un sitio del árbol.',
  ),
  TourStep(
    id: 'rail-translations',
    title: 'Lo que falta por traducir',
    body:
        'Ordenado por cuántos documentos usan cada unidad, no alfabéticamente: '
        'así es una cola de trabajo y no una lista de reproches. El número '
        'dice cuánto hay esperando.',
  ),
  TourStep(
    id: 'sync',
    title: 'Dónde va lo que escribes',
    body:
        'El repositorio en el que estás trabajando, lo que tienes sin enviar y '
        'lo que hay en GitHub que todavía no tienes. Está arriba en todas las '
        'pantallas porque dónde acaba un cambio no debería ser un misterio.',
  ),
  TourStep(
    id: 'rail-settings',
    title: 'Y el resto',
    body:
        'Tu cuenta, los repositorios abiertos, dónde está LaTeX, la traducción '
        'automática y las actualizaciones. Desde aquí se vuelve a ver esta '
        'presentación cuando haga falta.',
  ),
];

/// Dónde está cada objetivo, por su identificador.
///
/// Un mapa de módulo y no un `InheritedWidget`: los objetivos están repartidos
/// por el armazón --uno dentro del icono de una `NavigationRailDestination`,
/// que no es un sitio donde se pueda leer un contexto cómodamente-- y hay una
/// sola aplicación en pie. Lo que se gana es que marcar una parte de la
/// interfaz sea envolverla y nada más.
final Map<String, GlobalKey> tourTargets = {};

/// Envuelve la parte de la interfaz a la que un paso señala.
class TourTarget extends StatelessWidget {
  TourTarget({required this.id, required this.child})
    : super(key: tourTargets.putIfAbsent(id, GlobalKey.new));

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// En qué paso va el tour, o si no está en marcha.
class TourController extends ChangeNotifier {
  TourController({this.steps = defaultTour, this.onFinished});

  final List<TourStep> steps;

  /// Qué hacer al terminar o al salirse. Las dos cosas llaman aquí: salirse
  /// del tour es haberlo hecho, y volver a ofrecerlo en el siguiente arranque
  /// es no haber entendido lo que significó cerrarlo.
  final Future<void> Function()? onFinished;

  int _at = -1;

  bool get running => _at >= 0 && _at < steps.length;

  /// El paso actual, o `null` si no está en marcha.
  TourStep? get step => running ? steps[_at] : null;

  int get number => _at + 1;
  int get total => steps.length;

  void start() {
    _at = _nextMounted(0);
    notifyListeners();
    if (!running) onFinished?.call();
  }

  void next() {
    if (!running) return;
    _at = _nextMounted(_at + 1);
    notifyListeners();
    if (!running) onFinished?.call();
  }

  void stop() {
    if (_at < 0) return;
    _at = -1;
    notifyListeners();
    onFinished?.call();
  }

  /// El primer paso a partir de [from] cuyo objetivo está en pantalla.
  int _nextMounted(int from) {
    for (var i = from; i < steps.length; i += 1) {
      if (rectOf(steps[i].id) != null) return i;
    }
    return steps.length;
  }
}

/// Dónde está en pantalla el objetivo de un paso, si está.
Rect? rectOf(String id) {
  final context = tourTargets[id]?.currentContext;
  final object = context?.findRenderObject();
  if (object is! RenderBox || !object.hasSize) return null;
  final origin = object.localToGlobal(Offset.zero);
  final rect = origin & object.size;
  // Un objetivo de tamaño cero --o fuera de la ventana-- es un objetivo que
  // no está: señalarlo dibujaría un agujero en una esquina.
  if (rect.isEmpty) return null;
  return rect;
}

/// El velo, el hueco y el globo. Va por encima de toda la aplicación.
class TourOverlay extends StatelessWidget {
  const TourOverlay({super.key, required this.controller});

  final TourController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final step = controller.step;
        if (step == null) return const SizedBox.shrink();
        final target = rectOf(step.id);
        if (target == null) return const SizedBox.shrink();

        final size = MediaQuery.sizeOf(context);
        return Positioned.fill(
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                controller.stop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                // Pulsar fuera avanza, igual que el botón: es lo que hace
                // todo el mundo sin leer, y castigarlo cerrando el tour
                // entero sería una trampa.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.next,
                  child: CustomPaint(
                    size: size,
                    painter: _Spotlight(target: target),
                  ),
                ),
                _Bubble(
                  controller: controller,
                  step: step,
                  target: target,
                  area: size,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// El velo con un hueco donde está el objetivo.
class _Spotlight extends CustomPainter {
  const _Spotlight({required this.target});

  final Rect target;

  static const double _pad = 6;
  static const Radius _radius = Radius.circular(8);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(target.inflate(_pad), _radius);
    final veil = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(veil, Paint()..color = const Color(0xB3121417));
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = didactaAccent,
    );
  }

  @override
  bool shouldRepaint(_Spotlight old) => old.target != target;
}

/// El globo con el texto del paso, al lado del hueco.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.controller,
    required this.step,
    required this.target,
    required this.area,
  });

  final TourController controller;
  final TourStep step;
  final Rect target;
  final Size area;

  static const double width = 330;
  static const double gap = 14;

  @override
  Widget build(BuildContext context) {
    // A la derecha del objetivo si cabe --el carril está pegado al borde
    // izquierdo, que es el caso de casi todos los pasos-- y si no, debajo.
    final toTheRight = target.right + gap + width < area.width;
    final left = toTheRight
        ? target.right + gap
        : (target.left).clamp(12.0, area.width - width - 12);
    final top = toTheRight
        ? target.top.clamp(12.0, area.height - 220)
        : (target.bottom + gap).clamp(12.0, area.height - 220);

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        color: didactaCard,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.body,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              // La cuenta cede y los botones no: en una tarjeta de 330 la
              // fila se pasaba quince píxeles --«Salir» y «Siguiente» con el
              // relleno que Material les pone de serie-- y un desbordamiento
              // en una capa encima de todo se come la mitad del recorrido.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${controller.number} de ${controller.total}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('tour-skip'),
                    onPressed: controller.stop,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Salir'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    key: const Key('tour-next'),
                    onPressed: controller.next,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(
                      controller.number == controller.total
                          ? 'Listo'
                          : 'Siguiente',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
