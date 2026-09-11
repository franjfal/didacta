import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
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
