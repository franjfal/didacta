// Fotografía páginas de la web de Didacta, con sus zonas, para los vídeos.
//
//     node videos/estudio/web.mjs <web construida> <capturas.json> <carpeta>
//
// Lo mismo que `app/tool/shots_video.dart` hace con la aplicación, pero con
// la web de documentación: cada captura es una página de verdad, de la web
// construida ahora, y trae sus zonas --«descargar macOS», «el buscador»--
// medidas por el propio navegador. El montaje va a la zona por su nombre, así
// que si mañana la página cambia, el vídeo la sigue.
//
// En `capturas.json`, la lista `web`:
//
//     {"nombre": "descargas", "pagina": "descargas/",
//      "ancho": 1440, "alto": 900,              // la ventana, en puntos
//      "bajar_a": {"texto": "Descargar"},        // opcional: lo que queda arriba
//      "cajas": {"macos": {"selector": "a[href$='.dmg']"},
//                "titulo": {"texto": "Descargar"}}}
//
// Se sirve la web desde un servidor de aquí mismo --una web de MkDocs no se
// deja abrir como fichero-- y se fotografía al doble de densidad, como las
// capturas de la aplicación, para que la cámara pueda acercarse.

import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const [raiz, especificacion, salida] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(especificacion, 'utf-8'));
const densidad = 2;

const tipos = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.vtt': 'text/vtt', '.mp4': 'video/mp4',
};
const servidor = http.createServer((pet, res) => {
  let ruta = decodeURIComponent(new URL(pet.url, 'http://x').pathname);
  let fichero = path.join(raiz, ruta);
  if (fs.existsSync(fichero) && fs.statSync(fichero).isDirectory()) fichero = path.join(fichero, 'index.html');
  if (!fs.existsSync(fichero)) {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { 'content-type': tipos[path.extname(fichero)] || 'application/octet-stream' });
  fs.createReadStream(fichero).pipe(res);
});
await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${servidor.address().port}/`;

const navegador = await chromium.launch({
  channel: process.env.DIDACTA_CHROME ? undefined : 'chrome',
  executablePath: process.env.DIDACTA_CHROME || undefined,
  headless: true,
  args: ['--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'],
});

fs.mkdirSync(salida, { recursive: true });
for (const c of spec.web || []) {
  const ancho = c.ancho || 1440;
  const alto = c.alto || 900;
  const contexto = await navegador.newContext({
    viewport: { width: ancho, height: alto },
    deviceScaleFactor: densidad,
    colorScheme: 'light',
    locale: 'es-ES',
  });
  const hoja = await contexto.newPage();
  await hoja.goto(base + (c.pagina || ''), { waitUntil: 'networkidle' });
  await hoja.evaluate(() => document.fonts.ready);

  // Qué queda arriba: la página, bajada hasta ese elemento.
  if (c.bajar_a) {
    await hoja.evaluate(({ q, margen }) => {
      const el = q.selector
        ? document.querySelector(q.selector)
        : [...document.querySelectorAll('h1,h2,h3,p,a,li,span,strong')].find((e) => e.textContent.trim().includes(q.texto));
      if (el) window.scrollTo(0, el.getBoundingClientRect().top + window.scrollY - margen);
    }, { q: c.bajar_a, margen: c.bajar_a.margen ?? 90 });
    await hoja.waitForTimeout(250);
  }

  const zonas = await hoja.evaluate(({ cajas, d }) => {
    const out = {};
    for (const [nombre, q] of Object.entries(cajas || {})) {
      let el = null;
      if (q.selector) el = [...document.querySelectorAll(q.selector)][q.n || 0];
      else if (q.texto) {
        const todos = [...document.querySelectorAll('h1,h2,h3,h4,p,a,li,span,strong,code,label,button')]
          .filter((e) => e.textContent.trim() === q.texto || (q.contiene && e.textContent.includes(q.texto)));
        el = todos[q.n || 0];
      }
      if (!el) continue;
      const r = el.getBoundingClientRect();
      out[nombre] = [r.x * d, r.y * d, r.width * d, r.height * d].map((v) => Math.round(v));
    }
    return out;
  }, { cajas: c.cajas, d: densidad });

  const png = path.join(salida, `${c.nombre}.png`);
  await hoja.screenshot({ path: png });
  fs.writeFileSync(
    path.join(salida, `${c.nombre}.json`),
    JSON.stringify({ ancho: ancho * densidad, alto: alto * densidad, zonas, direccion: c.direccion || '' }, null, 1),
  );
  const faltan = Object.keys(c.cajas || {}).filter((k) => !(k in zonas));
  console.log(`  ${c.nombre}.png  (${Object.keys(zonas).length} zonas${faltan.length ? `; no encuentro: ${faltan.join(', ')}` : ''})`);
  await contexto.close();
}

await navegador.close();
servidor.close();
