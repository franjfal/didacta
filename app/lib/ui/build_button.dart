/// Compilar, y en qué idioma.
///
/// Compilar es la operación más larga que hay aquí --un curso entero puede ser
/// media hora-- y hasta ahora se hacía siempre en el idioma propio de cada
/// documento. Eso está bien para quien da la asignatura en uno solo, y es
/// exactamente lo contrario de lo que quiere quien la da en dos: la víspera de
/// la clase en valenciano no se quieren los tres idiomas, se quiere el
/// valenciano.
///
/// Así que **pulsar compila el idioma en el que se está trabajando**, que es
/// el de la barra de arriba, y mantener pulsado abre el menú con las dos
/// opciones, diciendo cuál es cada una por su nombre. Lo corriente en un
/// gesto, lo demás a un gesto de distancia.
///
/// **Pulsar compila las versiones del documento**, las que declara en su
/// `year.yaml`: un tema de teoría admite siete y el que se da solo en
/// diapositivas no quiere esperar por el libro. Todas, en el menú.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se pide compilar: en qué idiomas, y si todas las versiones.
///
/// Idiomas vacíos nunca: o el actual, o todos los de la asignatura. Sin
/// [everyVersion], las que declara cada documento.
typedef BuildChoice = ({List<String> languages, bool everyVersion});

/// Lo que se compila al elegir en el menú.
typedef BuildRequest = void Function(BuildChoice choice);

/// Los idiomas de una asignatura, con su nombre, para este menú.
///
/// Los que declara la asignatura, y si no declara ninguno los del espacio de
/// trabajo. Nunca vacío: sin ningún idioma no habría nada que compilar, y el
/// botón quedaría muerto sin decir por qué.
List<LanguageOption> buildLanguagesOf({
  required List<String> declared,
  required List<LanguageOption> known,
  required String fallback,
}) {
  final wanted = declared.isNotEmpty
      ? declared
      : [for (final option in known) option.code];
  final options = [
    for (final code in wanted)
      known.where((o) => o.code == code).firstOrNull ??
          LanguageOption(code: code, name: code),
  ];
  return options.isEmpty
      ? [LanguageOption(code: fallback, name: fallback)]
      : options;
}

/// Abre el menú de compilar en [at] y devuelve lo elegido, o null.
Future<BuildChoice?> askBuildLanguages(
  BuildContext context, {
  required Offset at,
  required List<LanguageOption> options,
  required String current,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;
  final name =
      options.where((o) => o.code == current).firstOrNull?.name ?? current;
  final all = [for (final option in options) option.code];
  final here = all.contains(current) ? [current] : [all.first];
  // El idioma de la barra puede no ser uno de los de esta asignatura. Decir
  // «compilar en castellano» y sacar valenciano sería mentir, así que se dice
  // lo que va a salir.
  final hereName = all.contains(current) ? name : options.first.name;

  return showMenu<BuildChoice>(
    context: context,
    position: RelativeRect.fromLTRB(
      at.dx,
      at.dy,
      overlay.size.width - at.dx,
      overlay.size.height - at.dy,
    ),
    items: [
      PopupMenuItem<BuildChoice>(
        key: const Key('build-current-language'),
        value: (languages: here, everyVersion: false),
        child: Text(
          all.length < 2
              ? tr('Compilar sus versiones')
              : tr('Compilar en {0}', [hereName]),
        ),
      ),
      if (all.length > 1)
        PopupMenuItem<BuildChoice>(
          key: const Key('build-all-languages'),
          value: (languages: all, everyVersion: false),
          child: Text(tr('Compilar en los {0} idiomas', [all.length])),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<BuildChoice>(
        key: const Key('build-every-version'),
        value: (languages: here, everyVersion: true),
        child: Text(
          all.length < 2
              ? tr('Compilar todas las versiones')
              : tr('Todas las versiones, en {0}', [hereName]),
        ),
      ),
    ],
  );
}

/// El botón redondo de compilar, con su menú al mantener pulsado.
class BuildButton extends StatelessWidget {
  const BuildButton({
    super.key,
    required this.id,
    required this.what,
    required this.options,
    required this.current,
    required this.onBuild,
  });

  final String id;

  /// Qué se compila, para el tooltip: en una lista de temas, «Compilar» no
  /// dice cuál.
  final String what;

  final List<LanguageOption> options;
  final String current;
  final BuildRequest onBuild;

  String get _currentName =>
      options.where((o) => o.code == current).firstOrNull?.name ?? current;

  List<String> get _tapLanguages =>
      options.any((o) => o.code == current) ? [current] : [options.first.code];

  @override
  Widget build(BuildContext context) => GestureDetector(
    // Siempre, también con un solo idioma: queda la otra pregunta, la de
    // compilar todas las versiones y no solo las del documento.
    onLongPressStart: (details) async {
      final chosen = await askBuildLanguages(
        context,
        at: details.globalPosition,
        options: options,
        current: current,
      );
      if (chosen != null) onBuild(chosen);
    },
    // El tooltip, fuera del `IconButton` y en disparo manual. Puesto como
    // `tooltip:` trae consigo su propio reconocedor de pulsación larga, gana
    // el pulso en el arena de gestos y el menú de idiomas no llega a abrirse
    // nunca. En manual sigue saliendo al pasar el ratón, que es como se lee
    // un tooltip en un escritorio.
    child: Tooltip(
      message: options.length < 2
          ? tr(
              'Compilar {0}, en sus versiones. Mantén pulsado para '
              'compilarlas todas',
              [what],
            )
          : tr(
              'Compilar {0} en {1}. Mantén pulsado para elegir '
              'el idioma o compilar todas las versiones',
              [what, _currentName],
            ),
      triggerMode: TooltipTriggerMode.manual,
      child: IconButton(
        key: Key('build-$id'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.play_circle_outline, size: 18),
        color: context.palette.accentDark,
        onPressed: () =>
            onBuild((languages: _tapLanguages, everyVersion: false)),
      ),
    ),
  );
}

/// Cuántos documentos se compilan sin preguntar.
///
/// Un tema son uno o dos; un curso entero, treinta o cuarenta, y eso es media
/// hora con el ordenador ocupado. Con un clic y sin avisar, el ▶ de un curso
/// lanzaba esa media hora cuando se quería mirar un tema.
const int bigBuild = 4;

/// Pregunta antes de compilar [documents] documentos, si son muchos.
///
/// Devuelve si se sigue. Con pocos no pregunta: un diálogo delante de cada
/// compilación de un tema es un diálogo que se aprende a aceptar sin leer.
Future<bool> confirmBigBuild(
  BuildContext context, {
  required int documents,
  required String what,
  List<String> languages = const [],
  String? question,
}) async {
  if (documents < bigBuild) return true;
  final inLanguages = languages.isEmpty
      ? tr('cada uno en su idioma')
      : languages.length == 1
      ? tr('en {0}', [languages.single])
      : tr('en {0}', [languages.join(', ')]);
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('confirm-big-build'),
      title: Text(question ?? tr('¿Compilar {0} entero?', [what])),
      content: SizedBox(
        width: 440,
        child: Text(
          tr(
            'Son {0} documentos, {1}. Puede tardar un buen '
            'rato, y mientras tanto el ordenador va más lento. Abajo se ve por '
            'cuál va, y se puede detener en cualquier momento.',
            [documents, inLanguages],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('confirm-big-build-go'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Compilar {0}', [documents])),
        ),
      ],
    ),
  );
  return answer == true;
}
