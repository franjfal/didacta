// Pinta un vídeo fotograma a fotograma y se lo pasa a ffmpeg.
//
//     node videos/estudio/grabar.mjs pagina.html salida.mp4 [--fps 30]
//     node videos/estudio/grabar.mjs pagina.html carpeta --fotos 3.5,12,40
//
// Usa el Chrome que ya haya en la máquina, sin ventana: `playwright-core` no
// descarga ningún navegador. Cada fotograma es `Estudio.pintar(t)` y una
// captura, así que el vídeo no depende de lo rápido que vaya el ordenador:
// uno lento tarda más en hacerlo, pero sale igual.

import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [pagina, salida, ...resto] = process.argv.slice(2);
const opcion = (nombre, porDefecto) => {
  const i = resto.indexOf(`--${nombre}`);
  return i >= 0 ? resto[i + 1] : porDefecto;
};
const fps = Number(opcion('fps', 30));
const fotos = opcion('fotos', null);
const desde = Number(opcion('desde', 0));

const navegador = await chromium.launch({
  channel: process.env.DIDACTA_CHROME ? undefined : 'chrome',
  executablePath: process.env.DIDACTA_CHROME || undefined,
  headless: true,
  args: ['--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'],
});
const hoja = await navegador.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
const avisos = [];
hoja.on('console', (m) => { if (m.type() === 'warning' || m.type() === 'error') avisos.push(m.text()); });
hoja.on('pageerror', (e) => { console.error(`Error en el montaje: ${e.message}`); process.exit(1); });
await hoja.goto(pathToFileURL(path.resolve(pagina)).href);
await hoja.waitForFunction(() => window.__listo !== undefined, null, { timeout: 30000 });
await hoja.evaluate(() => window.__listo);
const duracion = await hoja.evaluate(() => window.__duracion);
const cdp = await hoja.context().newCDPSession(hoja);

async function fotografiar(t) {
  await hoja.evaluate((tt) => window.__pintar(tt), t);
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true });
  return Buffer.from(data, 'base64');
}

if (fotos) {
  fs.mkdirSync(salida, { recursive: true });
  for (const t of fotos.split(',').map(Number)) {
    const nombre = path.join(salida, `t${t.toFixed(2).padStart(7, '0')}.png`);
    fs.writeFileSync(nombre, await fotografiar(t));
    console.log(nombre);
  }
} else {
  const total = Math.ceil(duracion * fps);
  const ffmpeg = spawn('ffmpeg', [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-tune', 'animation',
    '-pix_fmt', 'yuv420p', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
    '-r', String(fps), '-movflags', '+faststart', salida,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });
  const empezado = Date.now();
  let avisado = -1;
  for (let f = Math.floor(desde * fps); f < total; f += 1) {
    const png = await fotografiar(f / fps);
    if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once('drain', r));
    const pct = Math.floor((f / total) * 20);
    if (pct !== avisado) {
      avisado = pct;
      const pasado = (Date.now() - empezado) / 1000;
      process.stdout.write(`  ${String(pct * 5).padStart(3)} %  fotograma ${f}/${total}  (${pasado.toFixed(0)} s)\n`);
    }
  }
  ffmpeg.stdin.end();
  await new Promise((r) => ffmpeg.on('close', r));
  const sonidos = await hoja.evaluate(() => window.__sonidos);
  fs.writeFileSync(salida.replace(/\.mp4$/, '.sonidos.json'), JSON.stringify(sonidos, null, 1));
  console.log(`  ${total} fotogramas en ${((Date.now() - empezado) / 1000).toFixed(0)} s → ${salida}`);
}
for (const a of [...new Set(avisos)]) console.warn(`  aviso del montaje: ${a}`);
await navegador.close();
