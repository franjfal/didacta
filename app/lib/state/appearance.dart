/// Claro, oscuro o lo que diga el sistema.
///
/// Tres modos y no un interruptor de dos, porque lo que casi todo el mundo
/// quiere es que la aplicación haga lo mismo que el resto del ordenador --de
/// día claro, de noche oscuro--, y eso es «lo del sistema», que no es ni lo
/// uno ni lo otro. El botón del carril alterna entre claro y oscuro desde lo
/// que se ve; Ajustes deja volver a «el del sistema».
///
/// Lo que decide aquí es **qué paleta** está en uso. Cambiarla y volver a
/// pintar lo hace la raíz de la aplicación, que es la única que tiene a mano
/// todo el árbol.
library;

import 'package:flutter/widgets.dart';

import '../data/preferences.dart';
import '../ui/theme.dart';

enum AppearanceMode {
  system,
  light,
  dark;

  static AppearanceMode parse(String? value) => switch (value) {
    'light' => AppearanceMode.light,
    'dark' => AppearanceMode.dark,
    _ => AppearanceMode.system,
  };
}

class Appearance extends ChangeNotifier with WidgetsBindingObserver {
  Appearance({this.preferences}) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Dónde se apunta. Sin ellas --una prueba-- se cambia y no se recuerda.
  final Preferences? preferences;

  AppearanceMode _mode = AppearanceMode.system;
  AppearanceMode get mode => _mode;

  /// Lo que se ve ahora, resuelto el «lo del sistema».
  Brightness get brightness => switch (_mode) {
    AppearanceMode.light => Brightness.light,
    AppearanceMode.dark => Brightness.dark,
    AppearanceMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  DidactaPalette get palette => brightness == Brightness.dark
      ? DidactaPalette.dark
      : DidactaPalette.light;

  /// Los tamaños del texto por los que se pasa con ⌘+ y ⌘−.
  ///
  /// Pocos y separados: con pasos del cinco por ciento hacen falta seis
  /// pulsaciones para notar algo. Del 85 % --una pantalla pequeña con mucho
  /// que enseñar-- al 150 % --el proyector del aula--.
  static const List<double> textScales = [0.85, 0.9, 1, 1.1, 1.2, 1.35, 1.5];

  double _textScale = 1;

  /// Cuánto más grande se ve el texto: 1 es el normal.
  double get textScale => _textScale;

  /// Lee lo que se eligió la última vez. Antes de la primera pantalla: leerlo
  /// después sería enseñar un parpadeo en claro a quien trabaja en oscuro.
  Future<void> load() async {
    final stored = await preferences?.appearance();
    final next = AppearanceMode.parse(stored);
    final scale = _nearest(await preferences?.textScale() ?? 1);
    if (next == _mode && scale == _textScale) return;
    _mode = next;
    _textScale = scale;
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    final next = _nearest(value);
    if (next == _textScale) return;
    _textScale = next;
    notifyListeners();
    await preferences?.setTextScale(next);
  }

  /// Un paso más grande, si lo hay: ⌘+.
  Future<void> biggerText() {
    final at = textScales.indexOf(_textScale);
    return setTextScale(textScales[(at + 1).clamp(0, textScales.length - 1)]);
  }

  /// Un paso más pequeño, si lo hay: ⌘−.
  Future<void> smallerText() {
    final at = textScales.indexOf(_textScale);
    return setTextScale(textScales[(at - 1).clamp(0, textScales.length - 1)]);
  }

  /// El de siempre: ⌘0.
  Future<void> normalText() => setTextScale(1);

  /// El de la lista más cercano a [value]: lo guardado por otra versión, o
  /// un valor a mano, cae siempre en un paso por el que ⌘+ y ⌘− saben seguir.
  static double _nearest(double value) {
    var best = textScales.first;
    for (final scale in textScales) {
      if ((scale - value).abs() < (best - value).abs()) best = scale;
    }
    return best;
  }

  Future<void> setMode(AppearanceMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await preferences?.setAppearance(mode.name);
  }

  /// Al otro de lo que se ve: el botón del carril.
  Future<void> toggle() => setMode(
    brightness == Brightness.dark ? AppearanceMode.light : AppearanceMode.dark,
  );

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppearanceMode.system) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
