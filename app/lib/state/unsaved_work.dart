/// Lo que hay escrito y sin guardar, en cualquier pantalla.
///
/// Cada editor se apunta aquí mientras tiene cambios, y se borra al guardar,
/// al descartar o al cerrarse. Lo consultan los dos sitios por los que se
/// pierde trabajo sin darse cuenta: salir de una pantalla y cerrar Didacta.
/// Antes no había ningún aviso, y cambiar de lección con un párrafo a medio
/// escribir se lo llevaba sin decir nada.
///
/// Sin avisar a nadie al cambiar: se apunta desde los `build`, y quien
/// pregunta lo hace en el momento de salir, no mirándolo en pantalla.
library;

class UnsavedWork {
  final Map<Object, ({String what, String place})> _open = {};

  /// Apunta lo que [owner] tiene sin guardar, dicho para leer --«"Espacios
  /// normados" en va»--, o lo borra con null.
  ///
  /// [place] es la dirección de la pantalla donde está (`Routes.unit(…)`):
  /// al salir de una pantalla se pregunta por lo suyo y no por lo de otra.
  void mark(Object owner, String? what, {String place = ''}) {
    if (what == null) {
      _open.remove(owner);
    } else {
      _open[owner] = (what: what, place: Uri.parse(place).path);
    }
  }

  bool get isEmpty => _open.isEmpty;

  /// Qué hay sin guardar, en el orden en que se empezó a escribir.
  List<String> get what => [for (final entry in _open.values) entry.what];

  /// Lo que hay sin guardar en la pantalla de [place].
  List<String> whatAt(String place) {
    final path = Uri.parse(place).path;
    return [
      for (final entry in _open.values)
        if (entry.place == path) entry.what,
    ];
  }
}
