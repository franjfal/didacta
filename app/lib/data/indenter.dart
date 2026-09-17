/// Dejar un `.tex` con la forma que tenía que tener.
///
/// Se usa al guardar desde el editor y al escribir una traducción. Prueba
/// `latexindent` --la herramienta de CTAN, la buena-- y si no está o falla,
/// usa el indentador propio de [indentLatex], que siempre está.
///
/// **Por qué las dos.** `latexindent` entiende de LaTeX mucho más que
/// nosotros: alinea columnas de tablas, respeta ficheros de configuración por
/// proyecto, sabe de entornos anidados raros. Pero es un script de Perl con
/// cuatro dependencias de CPAN --`File::HomeDir`, `Log::Log4perl`,
/// `Log::Dispatch`, `Unicode::GCString`-- que MacTeX **no** instala. En una
/// máquina recién montada está el fichero y no arranca, que es el peor de los
/// dos mundos: parece disponible y no lo está. Didacta la usa gente que da
/// clase; pedirles `cpan install` para poder guardar un fichero no es una
/// opción.
///
/// Así que se intenta la buena y se cae de pie en la nuestra, sin decir nada:
/// el resultado es un fichero bien puesto en los dos casos, y cuál de las dos
/// lo hizo no es asunto de quien está escribiendo.
library;

import 'indenter_stub.dart' if (dart.library.io) 'indenter_io.dart' as platform;

/// El `.tex` sangrado. Nunca lanza: si todo falla, devuelve [text].
///
/// [texPath] es el directorio de TeX configurado a mano, si lo hay: es donde
/// vive `latexindent` cuando el PATH de la aplicación no lo lleva, que en
/// macOS es siempre.
Future<String> beautifyLatex(String text, {String? texPath}) =>
    platform.beautifyLatex(text, texPath: texPath);

/// Si `latexindent` está y funciona de verdad.
///
/// «Funciona de verdad» quiere decir que se le ha dado algo que sangrar y ha
/// contestado, no que el fichero exista: el caso que hay que distinguir es
/// justo el del script presente al que le faltan los módulos.
Future<bool> systemIndenterWorks({String? texPath}) =>
    platform.systemIndenterWorks(texPath: texPath);
