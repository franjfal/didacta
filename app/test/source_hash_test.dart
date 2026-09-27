/// La huella del original, igual que la calcula el motor.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/source_hash.dart';

void main() {
  test('da lo mismo que el motor', () {
    // Los mismos ejemplos que `tests/test_engine.py`: si uno de los dos lados
    // cambia la forma de calcularla, las traducciones se quedan todas
    // desactualizadas, o ninguna lo está nunca.
    expect(contentHash('  Hola\r\n\tmundo  \n'), 'sha256:ca8f60b2cc7f0583');
    expect(
      contentHash('La norma de \$\\|x\\|\$ es\n  única.'),
      'sha256:1c101d4652ae9780',
    );
  });

  test('re-sangrar no cambia la huella', () {
    expect(contentHash('a\n  b'), contentHash('a b'));
  });

  test('cambiar una palabra, sí', () {
    expect(contentHash('a b'), isNot(contentHash('a c')));
  });
}
