import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Lo primero: antes de que arranque Flutter, que lee los ajustes en
    // cuanto empieza, y antes de `setFrameUsingName`, que lee dónde estaba
    // la ventana. Las dos cosas se guardan con el nombre de la aplicación.
    LegacyIdentity.bringPreferences()

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Una ventana con sitio para trabajar, un mínimo por debajo del cual no
    // se deja encoger, y memoria de dónde estaba.
    //
    // La plantilla abre en 800x600 y la aplicación se estrenaba apretada: la
    // biblioteca tiene tres columnas --categorías, temas, unidades-- y por
    // debajo de unos 1000 px se pliega a una sola, así que el primer
    // arranque enseñaba la versión estrecha de una pantalla pensada para la
    // ancha. El mínimo es el ancho por debajo del cual la interfaz cambia de
    // forma a propósito, no uno por debajo del cual se rompe: encogerla
    // sigue funcionando.
    self.contentMinSize = NSSize(width: 560, height: 480)

    // Y donde la dejaste. `setFrameUsingName` devuelve false la primera vez,
    // que es justo cuando hay que decidir un tamaño; después manda lo que
    // el usuario haya puesto, que es lo correcto: una aplicación que se
    // recoloca sola en cada arranque es de las cosas que más molestan.
    let autosave = NSWindow.FrameAutosaveName("DidactaMainWindow")
    if !self.setFrameUsingName(autosave) {
      let preferred = NSSize(width: 1280, height: 840)
      if let screen = self.screen ?? NSScreen.main {
        // Sin salirse de la pantalla: en un portátil de 13 pulgadas
        // 1280x840 no cabe con el Dock y la barra de menú.
        let usable = screen.visibleFrame
        self.setContentSize(NSSize(
          width: min(preferred.width, usable.width - 40),
          height: min(preferred.height, usable.height - 40)
        ))
      } else {
        self.setContentSize(preferred)
      }
      self.center()
    }
    self.setFrameAutosaveName(autosave)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Lo que Didacta guardó cuando se llamaba de otra forma.
///
/// Hasta la 0.2.0 el identificador era `es.uv.didacta`, y macOS guarda los
/// ajustes de cada aplicación en un dominio con su identificador. Al pasar a
/// `io.github.franjfal.didacta`, la aplicación arrancaba con un dominio vacío:
/// sin repositorios, sin la bienvenida vista, sin la ventana donde estaba.
/// Quien se actualizara sola se encontraría una instalación nueva.
///
/// Así que la primera vez se copia lo de antes. Sólo lo que falte --nunca
/// encima de algo que ya esté-- y una sola vez: la marca que queda impide
/// volver a hacerlo, también después de «Restablecer», que es justo cuando
/// traerlo otra vez desharía lo que se pidió. El dominio viejo no se borra:
/// una versión anterior de Didacta lo seguiría usando.
private enum LegacyIdentity {
  static let bundleIdentifier = "es.uv.didacta"

  /// Sin el prefijo `flutter.` a propósito: `shared_preferences` sólo ve las
  /// claves que lo llevan, así que ni la aplicación la lee ni «Restablecer»,
  /// que borra las suyas, se la lleva.
  static let marker = "didacta.legacy.migrated"

  static func bringPreferences() {
    let defaults = UserDefaults.standard
    guard Bundle.main.bundleIdentifier != bundleIdentifier,
          defaults.object(forKey: marker) == nil else { return }
    if let old = defaults.persistentDomain(forName: bundleIdentifier) {
      for (key, value) in old where defaults.object(forKey: key) == nil {
        defaults.set(value, forKey: key)
      }
    }
    defaults.set(bundleIdentifier, forKey: marker)
  }
}
