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
/// una ventana estrecha --allí es una barra abajo--, una asignatura puede no
/// tener ningún curso y una lección puede no usarse en ningún sitio. Un tour
/// que se queda señalando el vacío es peor que uno corto.
///
/// **Navega, y deja las cosas como estaban.** Era un tour que no se movía del
/// armazón --el carril y la barra de arriba-- y eso dejaba sin contar lo que
/// de verdad cuesta encontrar: cómo es una asignatura por dentro, dónde se
/// congela un curso, qué filtra la biblioteca y cómo se ven los idiomas de una
/// lección. Ahora cada capítulo lleva a su pantalla --la primera asignatura,
/// su curso más reciente, un documento, una lección con traducciones-- y al
/// terminar, o al salirse, se vuelve a donde se estaba.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// A qué pantalla hay que ir para un paso, o `null` si no hay ninguna que
/// sirva --no hay asignaturas, no hay lecciones--.
typedef TourPlace = String? Function(Session session);

/// Un paso: a qué parte señala, en qué pantalla, y qué dice de ella.
class TourStep {
  const TourStep({
    required this.id,
    required this._title,
    required this._body,
    this._chapter,
    this.place,
  });

  /// El identificador del [TourTarget] al que señala.
  final String id;

  /// Lo que dice, en el idioma de la interfaz: los pasos son constantes, y
  /// se traducen al leerlos.
  String get title => tr(_title);
  String get body => tr(_body);
  final String _title;
  final String _body;

  /// El capítulo al que pertenece, que se lee encima del título.
  String? get chapter => _chapter == null ? null : tr(_chapter);
  final String? _chapter;

  /// Dónde está. Sin él, el paso es del armazón y se enseña donde se esté.
  final TourPlace? place;
}

// ------------------------------------------------------------ los sitios ---

/// La primera asignatura que se ve en la lista, con su curso más reciente.
({String course, String year})? _firstYear(Session session) {
  for (final course in session.sortedCourses) {
    if (session.isHiddenCourse(course.id)) continue;
    for (final year in session.sortedYearsOf(course)) {
      if (session.isHiddenYear(course.id, year)) continue;
      return (course: course.id, year: year);
    }
  }
  return null;
}

String? _toCourses(Session session) => Routes.courses();

String? _toLibrary(Session session) => Routes.library();

String? _toYear(Session session) {
  final first = _firstYear(session);
  return first == null ? null : Routes.year(first.course, first.year);
}

String? _toDocument(Session session) {
  final first = _firstYear(session);
  if (first == null) return null;
  final year = session.fullYear(first.course, first.year);
  for (final group in year?.byTheme ?? const <ThemedDocuments>[]) {
    if (group.documents.isEmpty) continue;
    return Routes.document(first.course, first.year, group.documents.first.id);
  }
  return null;
}

/// La lección que mejor enseña una lección: con varios idiomas, alguno por
/// traducir, y usada en algún documento. Una recién creada con un solo idioma
/// y sin usar dejaría vacíos justo los tres sitios que el paso explica.
String? _toUnit(Session session) {
  Unit? best;
  var score = -1;
  for (final unit in session.catalogue.units) {
    if (unit.isProblem) continue;
    final present = unit.statuses.values
        .where((status) => status != TranslationStatus.missing)
        .length;
    final missing = unit.statuses.values.contains(TranslationStatus.missing);
    final points =
        present * 2 + (missing ? 3 : 0) + (unit.usedBy.isNotEmpty ? 4 : 0);
    if (points > score) {
      score = points;
      best = unit;
    }
  }
  return best == null ? null : Routes.unit(best.path);
}

// ------------------------------------------------------------ los pasos ---

/// Los pasos del tour, en orden y por capítulos.
///
/// Del armazón primero --lo que está en todas las pantallas--, después cada
/// pantalla por el orden en que se trabaja: la asignatura, su curso, un
/// documento, la biblioteca y una lección. Y el armazón otra vez al final,
/// para los dos sitios que quedan.
const List<TourStep> defaultTour = [
  TourStep(
    id: 'rail',
    chapter: 'La ventana',
    title: 'Dónde está cada cosa',
    body:
        'Asignaturas es lo que estás dando este cuatrimestre, y por eso va '
        'primero. La biblioteca es todo el material ordenado por materia, que '
        'es cómo se busca. Traducción es la cola de lo que falta. Y Ajustes.',
  ),
  TourStep(
    id: 'sync',
    chapter: 'La ventana',
    title: 'Dónde va lo que escribes',
    body:
        'El repositorio en el que estás trabajando, lo que tienes sin enviar y '
        'lo que hay en GitHub que todavía no tienes. Está arriba en todas las '
        'pantallas porque dónde acaba un cambio no debería ser un misterio.',
  ),

  TourStep(
    id: 'courses-first',
    chapter: 'Asignaturas',
    place: _toCourses,
    title: 'Una asignatura',
    body:
        'Con sus cursos académicos debajo, el más reciente primero. La '
        'estrella la marca como tuya y el ojo la oculta de la lista: la '
        'asignatura sigue en el repositorio, solo deja de estorbar.',
  ),
  TourStep(
    id: 'courses-year-first',
    chapter: 'Asignaturas',
    place: _toCourses,
    title: 'Un curso académico',
    body:
        'Pulsa para entrar. Desde la fila misma se compila el curso entero '
        '--una pulsación larga elige el idioma-- y se exporta todo lo '
        'compilado a una carpeta.',
  ),
  TourStep(
    id: 'courses-year-menu',
    chapter: 'Asignaturas',
    place: _toCourses,
    title: 'Congelar y copiar',
    body:
        'El menú de cada curso. «Crear versión congelada» guarda el curso tal '
        'cual se dio, para poder volver a él aunque las lecciones cambien '
        'después; «Copiar a otro curso» empieza el año siguiente con la misma '
        'estructura y sin copiar ni una lección.',
  ),
  TourStep(
    id: 'courses-view',
    chapter: 'Asignaturas',
    place: _toCourses,
    title: 'Qué asignaturas ves',
    body:
        'Las que das, las ocultas o todas. Después de unos años la lista de '
        'lo que ya no se da es larga, y esto es lo que la quita de en medio.',
  ),

  TourStep(
    id: 'year-theme-first',
    chapter: 'Un curso por dentro',
    place: _toYear,
    title: 'Temas y documentos',
    body:
        'Los documentos del curso --el tema de teoría, la hoja de problemas, '
        'el examen--, agrupados por temas si los tiene. La cabecera de un '
        'tema lo pliega y compila todo lo que lleva dentro.',
  ),
  TourStep(
    id: 'year-document-first',
    chapter: 'Un curso por dentro',
    place: _toYear,
    title: 'Un documento',
    body:
        'Ábrelo para ver sus lecciones y sacar sus PDF. Se arrastra para '
        'cambiarlo de orden o de tema, y su menú lo mueve, lo duplica en otro '
        'curso o lo vincula a otro sitio sin copiarlo.',
  ),
  TourStep(
    id: 'year-actions',
    chapter: 'Un curso por dentro',
    place: _toYear,
    title: 'Lo que se añade aquí',
    body:
        'Un tema nuevo, un documento suelto y «Compilar el curso», que saca '
        'de una vez todos los PDF de todos los documentos.',
  ),

  TourStep(
    id: 'document-tabs',
    chapter: 'Un documento',
    place: _toDocument,
    title: 'Lo que tiene un documento',
    body:
        'La composición es la lista de lecciones en el orden en que se leen. '
        'Fuente es el LaTeX entero; Compilar saca las versiones que elijas en '
        'los idiomas que elijas; Traducir aparece si falta algo; e Historial '
        'dice quién cambió qué.',
  ),
  TourStep(
    id: 'document-outputs',
    chapter: 'Un documento',
    place: _toDocument,
    title: 'Las salidas',
    body:
        'Qué PDF salen de este documento --diapositivas, apuntes, la copia '
        'del profesor-- y en qué idiomas están ya compilados. Pulsa uno para '
        'abrirlo en una pestaña.',
  ),
  TourStep(
    id: 'document-info',
    chapter: 'Un documento',
    place: _toDocument,
    title: 'Dónde se da y qué versiones tiene',
    body:
        'En qué cursos está este documento, en qué temas, y sus versiones '
        'congeladas, para abrir la que se dio tal día.',
  ),

  TourStep(
    id: 'library-search',
    chapter: 'La biblioteca',
    place: _toLibrary,
    title: 'Buscar',
    body:
        'Por título, por etiqueta o por lo que dice dentro. Al escribir, el '
        'árbol se aplana en una lista de resultados: «hilbert» no es un sitio '
        'del árbol.',
  ),
  TourStep(
    id: 'library-filters',
    chapter: 'La biblioteca',
    place: _toLibrary,
    title: 'Los filtros',
    body:
        'Qué está traducido y qué falta, de qué tipo es cada lección, y en qué '
        'orden salen: por ruta, por título, las más usadas o lo que está por '
        'traducir primero. Y en qué idioma se leen los títulos.',
  ),
  TourStep(
    id: 'library-browser',
    chapter: 'La biblioteca',
    place: _toLibrary,
    title: 'Todo el material, por materias',
    body:
        'Área, tema y lección, de todos tus repositorios juntos. Cada lección '
        'dice en cuántos sitios se usa: la que no se usa en ninguno es la que '
        'se puede tocar sin miedo.',
  ),

  TourStep(
    id: 'unit-languages',
    chapter: 'Una lección',
    place: _toUnit,
    title: 'Sus idiomas',
    body:
        'Una pestaña por idioma. El punto relleno dice que ese idioma existe '
        'y su color, en qué estado está; el anillo rojo, que falta. Abrir el '
        'que falta es empezar a traducirlo.',
  ),
  TourStep(
    id: 'unit-compile',
    chapter: 'Una lección',
    place: _toUnit,
    title: 'Compilar una lección sola',
    body:
        'Para ver cómo queda sin compilar el tema entero: eliges la versión '
        '--diapositivas, apuntes, libro-- y el idioma, y el PDF se abre en una '
        'pestaña al lado.',
  ),
  TourStep(
    id: 'unit-editor',
    chapter: 'Una lección',
    place: _toUnit,
    title: 'Escribir y guardar',
    body:
        'El LaTeX de la lección en el idioma de la pestaña. El estado dice si '
        'la traducción está hecha, revisada o desfasada, y guardar lo deja en '
        'el historial con tu nombre.',
  ),
  TourStep(
    id: 'unit-used',
    chapter: 'Una lección',
    place: _toUnit,
    title: 'Sus datos, y dónde se usa',
    body:
        'Su tipo, sus etiquetas y, debajo, todos los documentos que la '
        'incluyen. Es lo que hay que mirar antes de cambiarla: corregirla '
        'aquí la corrige en todos ellos.',
  ),

  TourStep(
    id: 'rail-translations',
    chapter: 'Y para acabar',
    title: 'Lo que falta por traducir',
    body:
        'Ordenado por cuántos documentos usan cada unidad, no alfabéticamente: '
        'así es una cola de trabajo y no una lista de reproches. El número '
        'dice cuánto hay esperando.',
  ),
  TourStep(
    id: 'rail-settings',
    chapter: 'Y para acabar',
    title: 'Y el resto',
    body:
        'Tu cuenta, los repositorios abiertos, los idiomas, dónde está LaTeX, '
        'la traducción automática y las actualizaciones. Desde aquí se vuelve '
        'a ver esta presentación, y se abre el ejemplo si no lo tienes.',
  ),
];

// ----------------------------------------------------------- los objetivos ---

/// Dónde está cada objetivo, por su identificador.
///
/// Un mapa de módulo y no un `InheritedWidget`: los objetivos están repartidos
/// por la aplicación --uno dentro del icono de una
/// `NavigationRailDestination`, que no es un sitio donde se pueda leer un
/// contexto cómodamente-- y hay una sola aplicación en pie. Lo que se gana es
/// que marcar una parte de la interfaz sea envolverla y nada más.
///
/// **Un identificador, un sitio a la vez.** La clave es global, así que dos
/// objetivos con el mismo en pantalla a la vez se caen. En una lista se marca
/// solo el primero.
final Map<String, GlobalKey> tourTargets = {};

/// Envuelve la parte de la interfaz a la que un paso señala.
class TourTarget extends StatelessWidget {
  TourTarget({required this.id, required this.child})
    : super(key: tourTargets.putIfAbsent(id, GlobalKey.new));

  final String id;
  final Widget child;

  /// [child] envuelto si [when], tal cual si no. Para el primero de una
  /// lista: marcar todos repetiría la clave.
  static Widget first({
    required String id,
    required bool when,
    required Widget child,
  }) => when ? TourTarget(id: id, child: child) : child;

  @override
  Widget build(BuildContext context) => child;
}

/// Dónde está en pantalla el objetivo de un paso, si está.
Rect? rectOf(String id) {
  final context = tourTargets[id]?.currentContext;
  final object = context?.findRenderObject();
  if (object is! RenderBox || !object.hasSize || !object.attached) return null;
  final origin = object.localToGlobal(Offset.zero);
  final rect = origin & object.size;
  // Un objetivo de tamaño cero es un objetivo que no está: señalarlo
  // dibujaría un agujero en una esquina.
  if (rect.isEmpty) return null;
  return rect;
}

// ------------------------------------------------------------ el control ---

/// En qué paso va el tour, o si no está en marcha.
class TourController extends ChangeNotifier {
  TourController({this.steps = defaultTour, this.onFinished});

  final List<TourStep> steps;

  /// Qué hacer al terminar o al salirse. Las dos cosas llaman aquí: salirse
  /// del tour es haberlo hecho, y volver a ofrecerlo en el siguiente arranque
  /// es no haber entendido lo que significó cerrarlo.
  final Future<void> Function()? onFinished;

  /// Cómo cambiar de pantalla, dónde se está y de qué sesión se sacan los
  /// sitios. Los pone la aplicación cuando ya tiene el router: el tour se
  /// crea antes. Sin ellos, los pasos que llevan a una pantalla se saltan.
  void Function(String location)? _navigate;
  String Function()? _locate;
  Session? _session;

  void attach({
    required void Function(String location) navigate,
    required String Function() locate,
    required Session session,
  }) {
    _navigate = navigate;
    _locate = locate;
    _session = session;
  }

  int _at = -1;

  /// Buscando el siguiente objetivo: se ha cambiado de pantalla y todavía no
  /// ha aparecido.
  bool _seeking = false;

  /// Cada búsqueda lleva su número, y una que ya no es la última se calla:
  /// pulsar «Siguiente» dos veces seguidas, o salirse mientras una pantalla
  /// carga, no puede acabar enseñando un paso viejo.
  int _run = 0;

  /// Dónde se estaba al empezar, y a dónde se ha ido el tour.
  String? _origin;
  String? _placed;

  bool get running => _seeking || (_at >= 0 && _at < steps.length);

  /// Si está entre dos pasos, esperando a que el siguiente aparezca.
  bool get seeking => _seeking;

  /// El paso actual, o `null` si no hay ninguno en pantalla.
  TourStep? get step =>
      !_seeking && _at >= 0 && _at < steps.length ? steps[_at] : null;

  int get number => _at + 1;
  int get total => steps.length;

  void start() {
    _origin = _locate?.call();
    _placed = null;
    _at = -1;
    _seek(0, 1);
  }

  void next() {
    if (!running || _seeking) return;
    _seek(_at + 1, 1);
  }

  void back() {
    if (!running || _seeking || _at <= 0) return;
    _seek(_at - 1, -1);
  }

  void stop() {
    if (!running) return;
    _run += 1;
    _finish();
  }

  void _seek(int from, int direction) {
    final run = ++_run;
    unawaited(_find(from, direction, run));
  }

  /// El primer paso a partir de [from], hacia [direction], cuyo objetivo
  /// aparece.
  Future<void> _find(int from, int direction, int run) async {
    for (var i = from; i >= 0 && i < steps.length; i += direction) {
      final step = steps[i];
      var moved = false;
      if (step.place != null) {
        final navigate = _navigate;
        final session = _session;
        final where = navigate == null || session == null
            ? null
            : step.place!(session);
        if (where == null) continue;
        if (where != _placed) {
          _placed = where;
          _seeking = true;
          notifyListeners();
          navigate!(where);
          moved = true;
        }
      }
      final found = await _appears(step.id, patient: moved, run: run);
      if (run != _run) return;
      if (!found) continue;
      _at = i;
      _seeking = false;
      notifyListeners();
      _reveal(step.id);
      return;
    }
    if (run != _run) return;
    // Hacia atrás no se termina: si no queda nada antes, se queda donde
    // estaba.
    if (direction < 0 && _at >= 0) {
      _seeking = false;
      notifyListeners();
      return;
    }
    _finish();
  }

  /// Si el objetivo de un paso está, o llega a estar.
  ///
  /// Recién cambiada la pantalla se espera un poco: la de un curso lee su
  /// `year.yaml` del disco y los temas salen después. En la misma pantalla,
  /// no: lo que no está ya no va a llegar.
  Future<bool> _appears(
    String id, {
    required bool patient,
    required int run,
  }) async {
    if (rectOf(id) != null) return true;
    final tries = patient ? 80 : 2;
    for (var i = 0; i < tries; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (run != _run) return false;
      if (rectOf(id) != null) return true;
    }
    return false;
  }

  /// Que se vea: un objetivo dentro de una lista puede estar más abajo.
  void _reveal(String id) {
    final context = tourTargets[id]?.currentContext;
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ).catchError((Object _) {}),
    );
  }

  void _finish() {
    _at = -1;
    _seeking = false;
    notifyListeners();
    // A donde se estaba, si el tour se movió. Dejar a alguien en una lección
    // que no ha elegido es dejarle perdido justo al acabar de orientarle.
    final origin = _origin;
    if (_placed != null && origin != null) _navigate?.call(origin);
    _placed = null;
    _origin = null;
    final finished = onFinished;
    if (finished != null) unawaited(finished());
  }
}

// ------------------------------------------------------------- el velo ---

/// El velo, el hueco y el globo. Va por encima de toda la aplicación.
///
/// Vuelve a medir el objetivo en cada fotograma mientras el tour está en
/// marcha: una pantalla que acaba de cargar mueve lo que había debajo, y un
/// hueco que se queda donde estaba el objetivo hace un momento señala otra
/// cosa. Y de un paso al siguiente el hueco se desliza en lugar de saltar,
/// que es lo que permite seguirlo con la vista.
class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.controller});

  final TourController controller;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with TickerProviderStateMixin {
  late final Ticker _watch = createTicker(_measure);
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  Rect? _from;
  Rect? _to;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(TourOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _watch.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _changed() {
    final running = widget.controller.running;
    if (running && !_watch.isActive) unawaited(_watch.start());
    if (!running && _watch.isActive) {
      _watch.stop();
      _from = null;
      _to = null;
    }
    if (mounted) setState(() {});
  }

  void _measure(Duration _) {
    final step = widget.controller.step;
    if (step == null) return;
    final target = rectOf(step.id);
    if (target == null || target == _to) return;
    setState(() {
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      _from = _to == null || still ? target : _current;
      _to = target;
      unawaited(_slide.forward(from: still ? 1 : 0));
    });
  }

  Rect? get _current {
    final to = _to;
    if (to == null) return null;
    return Rect.lerp(
      _from ?? to,
      to,
      Curves.easeInOutCubic.transform(_slide.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.running) return const SizedBox.shrink();
    final step = controller.step;
    final size = MediaQuery.sizeOf(context);

    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            controller.stop();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            controller.next();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            controller.back();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            // Entre un paso y otro, el velo sin hueco: la pantalla de debajo
            // está cambiando y lo que se viera por el agujero no sería nada.
            final hole = step == null ? null : (_current ?? rectOf(step.id));
            return Stack(
              children: [
                // Pulsar fuera avanza, igual que el botón: es lo que hace
                // todo el mundo sin leer, y castigarlo cerrando el tour
                // entero sería una trampa.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.next,
                  child: CustomPaint(
                    size: size,
                    painter: _Spotlight(
                      target: hole,
                      accent: context.palette.accent,
                    ),
                  ),
                ),
                if (step != null && hole != null)
                  Positioned.fill(
                    child: CustomSingleChildLayout(
                      delegate: _BubbleLayout(target: _to ?? hole),
                      child: _Bubble(controller: controller, step: step),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// El velo con un hueco donde está el objetivo, o sin hueco entre pasos.
class _Spotlight extends CustomPainter {
  const _Spotlight({required this.target, required this.accent});

  final Rect? target;
  final Color accent;

  static const double _pad = 6;
  static const Radius _radius = Radius.circular(10);

  @override
  void paint(Canvas canvas, Size size) {
    final veil = Paint()..color = didactaVeil;
    final hole = target;
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, veil);
      return;
    }
    final rounded = RRect.fromRectAndRadius(hole.inflate(_pad), _radius);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rounded),
      ),
      veil,
    );
    // Un halo además del borde: sobre un fondo claro, dos píxeles verdes
    // solos se pierden, y el hueco tiene que verse desde el otro lado de la
    // pantalla.
    canvas.drawRRect(
      rounded.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = accent.withValues(alpha: 0.28),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_Spotlight old) =>
      old.target != target || old.accent != accent;
}

/// Dónde va el globo: donde quepa entero, al lado del hueco.
///
/// A la derecha primero --el carril está pegado al borde izquierdo--, luego
/// debajo, encima y a la izquierda. Con su tamaño de verdad y no uno
/// supuesto: un paso con dos líneas y otro con seis no caben en los mismos
/// sitios, y colocarlos igual era lo que dejaba los botones de uno fuera de
/// la ventana.
class _BubbleLayout extends SingleChildLayoutDelegate {
  const _BubbleLayout({required this.target});

  final Rect target;

  static const double _gap = 16;
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          (constraints.maxWidth - _margin * 2).clamp(0, _Bubble.width),
          constraints.maxHeight - _margin * 2,
        ),
      );

  @override
  Offset getPositionForChild(Size area, Size child) {
    double x(double value) =>
        value.clamp(_margin, area.width - child.width - _margin);
    double y(double value) =>
        value.clamp(_margin, area.height - child.height - _margin);

    if (target.right + _gap + child.width + _margin <= area.width) {
      return Offset(target.right + _gap, y(target.top));
    }
    if (target.bottom + _gap + child.height + _margin <= area.height) {
      return Offset(x(target.left), target.bottom + _gap);
    }
    if (target.top - _gap - child.height >= _margin) {
      return Offset(x(target.left), target.top - _gap - child.height);
    }
    if (target.left - _gap - child.width >= _margin) {
      return Offset(target.left - _gap - child.width, y(target.top));
    }
    // No cabe al lado de nada: un objetivo que ocupa media pantalla. Abajo a
    // la derecha, que es donde menos tapa.
    return Offset(
      area.width - child.width - _margin,
      area.height - child.height - _margin,
    );
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.target != target;
}

/// El globo con el texto del paso.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.controller, required this.step});

  final TourController controller;
  final TourStep step;

  static const double width = 344;

  @override
  Widget build(BuildContext context) {
    final last = controller.number == controller.total;
    return SizedBox(
      width: width,
      child: TweenAnimationBuilder<double>(
        // Una entrada corta para cada paso: sin ella, el texto cambiaba de
        // golpe y no se notaba que era otro.
        key: ValueKey(step.id),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 6),
            child: child,
          ),
        ),
        child: Material(
          color: context.palette.card,
          elevation: 6,
          shadowColor: context.palette.shadow.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: controller.number / controller.total,
                minHeight: 3,
                backgroundColor: context.palette.rule,
                color: context.palette.accent,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Todo el hueco para el capítulo: con un `Flexible`
                        // al lado de un `Spacer` se lo repartían a medias, y
                        // «Un curso por dentro» salía cortado.
                        Expanded(
                          child: Text(
                            step.chapter?.toUpperCase() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                              color: context.palette.accentDark,
                            ),
                          ),
                        ),
                        Text(
                          tr('{0} de {1}', [
                            controller.number,
                            controller.total,
                          ]),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.muted,
                          ),
                        ),
                        const SizedBox(width: 2),
                        // Salir, en la esquina y con una cruz: donde se busca
                        // en cualquier cosa que sale por encima. Abajo, en la
                        // fila de «Siguiente», competía con él y no cabía.
                        //
                        // Sin `tooltip`: el velo va en el `builder` de la
                        // aplicación, por encima del `Navigator`, y ahí no
                        // hay `Overlay` donde sacarlo. Una etiqueta para el
                        // lector de pantalla dice lo mismo.
                        IconButton(
                          key: const Key('tour-skip'),
                          onPressed: controller.stop,
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            semanticLabel: tr('Salir del recorrido'),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.body,
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (controller.number > 1)
                          TextButton.icon(
                            key: const Key('tour-back'),
                            onPressed: controller.back,
                            icon: const Icon(Icons.arrow_back, size: 15),
                            label: Text(tr('Atrás')),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                          ),
                        const Spacer(),
                        FilledButton(
                          key: const Key('tour-next'),
                          onPressed: controller.next,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: Text(last ? tr('Listo') : tr('Siguiente')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
