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
/// Con un solo idioma no hay menú: no hay nada que elegir, y un menú de una
/// opción es un clic de más.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import 'theme.dart';

/// Lo que se compila al elegir en el menú.
///
/// Lista vacía nunca: o el idioma actual, o todos los de la asignatura.
typedef BuildRequest = void Function(List<String> languages);

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

/// Abre el menú de idiomas en [at] y devuelve lo elegido, o null.
Future<List<String>?> askBuildLanguages(
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

  return showMenu<List<String>>(
    context: context,
    position: RelativeRect.fromLTRB(
      at.dx,
      at.dy,
      overlay.size.width - at.dx,
      overlay.size.height - at.dy,
    ),
    items: [
      PopupMenuItem<List<String>>(
        key: const Key('build-current-language'),
        value: all.contains(current) ? [current] : [all.first],
        child: Text(
          all.contains(current)
              ? 'Compilar en $name'
              // El idioma de la barra puede no ser uno de los de esta
              // asignatura. Decir «compilar en castellano» y sacar valenciano
              // sería mentir, así que se dice lo que va a salir.
              : 'Compilar en ${options.first.name}',
        ),
      ),
      PopupMenuItem<List<String>>(
        key: const Key('build-all-languages'),
        value: all,
        child: Text('Compilar en los ${all.length} idiomas'),
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
    onLongPressStart: options.length < 2
        ? null
        : (details) async {
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
          ? 'Compilar $what, en todas sus versiones'
          : 'Compilar $what en $_currentName. Mantén pulsado para elegir '
                'el idioma',
      triggerMode: TooltipTriggerMode.manual,
      child: IconButton(
        key: Key('build-$id'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.play_circle_outline, size: 18),
        color: didactaAccentDark,
        onPressed: () => onBuild(_tapLanguages),
      ),
    ),
  );
}
