/// Hablar con Google o con Azure.
///
/// Detrás de una interfaz común porque la aplicación no quiere saber cuál hay
/// puesto: pide traducir y le da igual quién conteste. Y porque el día que
/// haya un tercero --o uno propio, en un servidor del departamento-- añadirlo
/// tiene que ser un fichero, no tocar todo lo que traduce.
///
/// **Ningún mensaje de error lleva la clave dentro.** Es fácil que se cuele:
/// los dos proveedores la aceptan en la URL, así que un «no se pudo pedir
/// $url» la imprime entera, y ese texto acaba en un registro que alguien pega
/// en un correo. Aquí las URL se construyen con la clave en una cabecera
/// cuando se puede, y lo que se cuenta del fallo es el código y lo que dijo el
/// servidor, nunca lo que se le mandó.
library;

import '../model/translation.dart';

/// Lo que se sabe de un proveedor después de preguntarle.
class ProviderCheck {
  const ProviderCheck({
    required this.ok,
    required this.message,
    this.languages = const [],
  });

  final bool ok;

  /// Qué contestó, en términos de alguien que va a arreglarlo.
  final String message;

  /// Los idiomas que dice admitir, cuando contesta bien. Sirve para avisar de
  /// que un idioma de la asignatura no lo traduce nadie antes de intentarlo.
  final List<String> languages;
}

/// Un fallo hablando con el proveedor.
///
/// Con el código y lo que dijo, y **sin nada de lo que se le mandó**: ni la
/// clave, ni la URL que la lleva, ni el texto a traducir.
class TranslationException implements Exception {
  const TranslationException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message ($status)';
}

abstract class Translator {
  TranslationProvider get provider;

  /// Le pregunta si está vivo y si la credencial vale.
  ///
  /// Pidiendo la lista de idiomas y no traduciendo algo: es la llamada más
  /// barata que comprueba lo mismo --que la clave se acepta-- y no gasta
  /// caracteres de la cuota por comprobar una configuración.
  Future<ProviderCheck> check();

  /// Traduce, respetando lo que venga marcado como intraducible.
  ///
  /// El texto llega ya protegido: las fórmulas, los entornos y las claves de
  /// `\label` van como etiquetas `<x id="N"/>`, que los dos proveedores saben
  /// respetar en modo HTML.
  Future<List<String>> translate(
    List<String> pieces, {
    required String from,
    required String to,
  });
}
