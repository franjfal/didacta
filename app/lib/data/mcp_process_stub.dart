/// Sin procesos no hay servidor: en la web esto no puede existir.
library;

import 'mcp_process.dart';

McpRunner runnerFor({required String enginePath, String? texPath}) =>
    const UnavailableRunner(
      'El servidor MCP necesita lanzar el motor, y en el navegador no se '
      'pueden lanzar procesos. Usa la aplicación de escritorio.',
    );
