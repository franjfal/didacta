/// La respuesta de la web: aquí no hay dónde guardar nada.
///
/// Un navegador no tiene carpeta de datos que el motor pueda leer, y el motor
/// tampoco está. Las plantillas de quien trabaje en la web viven en sus
/// repositorios, que es donde tienen que vivir de todas formas.
library;

import 'template_store.dart';

bool get supported => false;

Future<TemplateStore?> openStore() async => null;
