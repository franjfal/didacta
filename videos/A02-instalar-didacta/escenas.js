/* A2 · Instalar Didacta: el montaje.
 *
 * Lo de Didacta es de verdad: la página de Descargar sale de la web
 * construida ahora (`estudio/web.mjs`) y la bienvenida, de la propia
 * aplicación. Lo de cada sistema --la ventana del disco de macOS, el aviso de
 * Gatekeeper, Ajustes del Sistema, SmartScreen, el instalador, el terminal--
 * se dibuja: no hay forma de fotografiarlo sin instalar de verdad, y un
 * dibujo claro enseña mejor dónde pulsar que una captura con todo lo demás.
 * Los textos de esos dibujos son los que enseña cada sistema en castellano;
 * la voz no los lee, dice qué hacer.
 *
 * Como en el A1, ningún tiempo está escrito a mano: todo cuelga de
 * `G.frase()` y `G.palabra()`.
 */
window.montaje = function (E, G, D) {
  const { W, H, nodo, anim, tarea, sonido } = E;
  const V = D.video;
  const version = V.version || '0.3.0';
  const ficheros = {
    macos: `Didacta-${version}-macos-universal.dmg`,
    windows: `Didacta-${version}-windows-x64.exe`,
    linux: `Didacta-${version}-linux-x64.AppImage`,
  };

  // ---------------------------------------------------------- utilidades --

  const capa = (z = 10) => nodo({ clase: 'capa', estilo: { width: `${W}px`, height: `${H}px`, zIndex: z } });

  const visible = (n, ini, fin, entra = 0.45, sale = 0.4) =>
    anim(n, [
      [ini, { o: 0 }],
      [ini + entra, { o: 1 }, 'sale'],
      [fin - sale, { o: 1 }],
      [fin, { o: 0 }, 'suave'],
    ]);

  const entra = (n, t, o = {}) =>
    anim(n, [
      [t, { o: 0, y: o.dy ?? 36, blur: o.blur ?? 8, s: o.s ?? 1 }],
      [t + (o.dur ?? 0.65), { o: 1, y: 0, blur: 0, s: 1 }, o.curva || 'sale4'],
    ]);
  const sale = (n, t, o = {}) =>
    anim(n, [
      [t, { o: 1, y: 0, blur: 0 }],
      [t + (o.dur ?? 0.45), { o: 0, y: o.dy ?? -26, blur: o.blur ?? 6 }, 'entra'],
    ]);

  const centrado = (html, top, estilo = {}, padre) =>
    nodo({ padre, html, estilo: { position: 'absolute', left: 0, width: `${W}px`, top: `${top}px`, textAlign: 'center', ...estilo } });

  const caja = (padre, x, y, w, h, clase = '', html = '', estilo = {}) =>
    nodo({ padre, clase: `abs ${clase}`, html, estilo: { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: h == null ? 'auto' : `${h}px`, ...estilo } });

  /** Un rectángulo de un nodo, en el lienzo, sin contar sus animaciones. */
  const rect = (n) => {
    let x = 0;
    let y = 0;
    let el = n;
    while (el && el.id !== 'lienzo') {
      x += el.offsetLeft;
      y += el.offsetTop;
      el = el.offsetParent;
    }
    return { x, y, w: n.offsetWidth, h: n.offsetHeight };
  };
  const centro = (n) => {
    const r = rect(n);
    return { x: r.x + r.w / 2, y: r.y + r.h / 2, lienzo: true };
  };

  /** Texto que se escribe letra a letra entre t0 y t1. */
  const teclear = (n, texto, t0, t1) => {
    n.textContent = '';
    tarea((t) => {
      const u = E.clamp((t - t0) / (t1 - t0), 0, 1);
      n.textContent = texto.slice(0, Math.round(u * texto.length));
    });
  };

  const icono = {
    ok: '<svg viewBox="0 0 24 24" width="30" height="30"><circle cx="12" cy="12" r="11" fill="#346e34"/><path d="M7 12.5l3.2 3.2L17 9" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    no: '<svg viewBox="0 0 24 24" width="30" height="30"><circle cx="12" cy="12" r="11" fill="#aa4b4b"/><path d="M8 8l8 8M16 8l-8 8" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/></svg>',
    escudo: '<svg viewBox="0 0 24 24" width="28" height="28"><path d="M12 2l8 3v6c0 5-3.4 9.4-8 11-4.6-1.6-8-6-8-11V5z" fill="#346e34"/><path d="M8 12l3 3 5-6" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    carpeta: (color = '#4f9fe8') =>
      `<svg viewBox="0 0 120 96" width="100%" height="100%"><defs><linearGradient id="cf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}"/><stop offset="1" stop-color="#2f7fce"/></linearGradient></defs><path d="M6 18a8 8 0 0 1 8-8h30l10 10h52a8 8 0 0 1 8 8v54a8 8 0 0 1-8 8H14a8 8 0 0 1-8-8z" fill="#3c8ee0"/><path d="M6 32a8 8 0 0 1 8-8h92a8 8 0 0 1 8 8v50a8 8 0 0 1-8 8H14a8 8 0 0 1-8-8z" fill="url(#cf)"/><path d="M42 58l18 12 18-12" fill="none" stroke="#ffffff99" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    fichero: (texto, color) =>
      `<svg viewBox="0 0 80 100" width="100%" height="100%"><path d="M6 6h46l22 22v66H6z" fill="#fff" stroke="#c9cfc5" stroke-width="3"/><path d="M52 6v22h22" fill="#eef0eb" stroke="#c9cfc5" stroke-width="3"/><rect x="12" y="62" width="56" height="22" rx="5" fill="${color}"/><text x="40" y="78" text-anchor="middle" font-family="Inter" font-weight="800" font-size="13" fill="#fff">${texto}</text></svg>`,
  };

  // Los dibujos de cada sistema, con sus propios estilos.
  nodo({
    tag: 'style',
    padre: document.head,
    html: `
      .mac { position:absolute; border-radius:16px; overflow:hidden; background:#fff; font-family:Inter;
             box-shadow:0 0 0 1px rgba(0,0,0,.10), 0 30px 70px -18px rgba(28,31,38,.40); }
      .mac .tit { height:44px; display:flex; align-items:center; gap:9px; padding-left:18px;
                  background:linear-gradient(#f4f4f4,#ebebeb); border-bottom:1px solid #dcdcdc; position:relative; }
      .mac .tit i { width:14px; height:14px; border-radius:50%; display:block; }
      .mac .tit i:nth-child(1){background:#ff5f57} .mac .tit i:nth-child(2){background:#febc2e} .mac .tit i:nth-child(3){background:#28c840}
      .mac .tit b { position:absolute; left:0; right:0; text-align:center; font-size:16px; font-weight:600; color:#555; }
      .alerta { position:absolute; width:440px; padding:34px 30px 26px; border-radius:26px; background:rgba(246,246,246,.98);
                box-shadow:0 0 0 1px rgba(0,0,0,.12), 0 40px 90px -20px rgba(0,0,0,.45); text-align:center; font-family:Inter; }
      .alerta h3 { margin:18px 0 10px; font-size:21px; font-weight:700; color:#1c1f26; }
      .alerta p { margin:0 0 22px; font-size:15.5px; line-height:1.4; color:#3b3f46; }
      .alerta .btn { height:40px; border-radius:10px; display:flex; align-items:center; justify-content:center;
                     font-size:16px; font-weight:600; margin-top:10px; }
      .btn.azul { background:#0a84ff; color:#fff; } .btn.gris { background:#e3e3e5; color:#1c1f26; }
      .ajustes .lado { position:absolute; left:0; top:44px; bottom:0; width:300px; background:#f0f0f2; border-right:1px solid #dedee2; padding:18px 14px; }
      .ajustes .buscar { height:34px; border-radius:9px; background:#e2e2e6; margin-bottom:16px; color:#8a8d93; font-size:15px; display:flex; align-items:center; padding-left:12px; }
      .ajustes .item { height:38px; border-radius:9px; display:flex; align-items:center; gap:12px; padding-left:10px; font-size:16px; color:#26292f; }
      .ajustes .item span { width:24px; height:24px; border-radius:7px; display:block; }
      .ajustes .item.sel { background:#0a84ff; color:#fff; }
      .ajustes .panel { position:absolute; left:300px; right:0; top:44px; bottom:0; overflow:hidden; background:#f7f7f9; }
      .ajustes .dentro { position:absolute; left:40px; right:40px; top:26px; }
      .ajustes h2 { margin:0 0 20px; font-size:26px; font-weight:700; color:#1c1f26; }
      .ajustes h4 { margin:30px 0 10px 6px; font-size:16px; font-weight:700; color:#6b6f76; }
      .ajustes .grupo { background:#fff; border-radius:12px; box-shadow:0 0 0 1px #e3e3e7; }
      .ajustes .fila { min-height:52px; display:flex; align-items:center; gap:14px; padding:10px 18px; font-size:16px; color:#26292f; border-top:1px solid #eeeef1; }
      .ajustes .fila:first-child { border-top:0; }
      .ajustes .fila .valor { margin-left:auto; color:#6b6f76; }
      .ajustes .boton { margin-left:auto; flex:none; height:34px; padding:0 18px; border-radius:9px; background:#fff; box-shadow:0 0 0 1px #cfcfd4, 0 1px 2px rgba(0,0,0,.08);
                        display:flex; align-items:center; font-weight:600; color:#1c1f26; }
      .hoja-mac { position:absolute; width:420px; padding:28px 28px 22px; border-radius:22px; background:rgba(246,246,246,.99);
                  box-shadow:0 0 0 1px rgba(0,0,0,.12), 0 30px 80px -20px rgba(0,0,0,.45); font-family:Inter; text-align:center; }
      .hoja-mac h3 { margin:14px 0 6px; font-size:18px; font-weight:700; } .hoja-mac p { margin:0 0 16px; font-size:15px; color:#3b3f46; }
      .hoja-mac .campo { height:36px; border-radius:8px; background:#fff; box-shadow:0 0 0 1px #d0d0d5; margin-bottom:10px; display:flex; align-items:center; padding:0 12px; font-size:16px; color:#26292f; }
      .hoja-mac .dos { display:flex; gap:10px; margin-top:8px; } .hoja-mac .dos .btn { flex:1; height:38px; border-radius:9px; display:flex; align-items:center; justify-content:center; font-weight:600; }
      .smart { position:absolute; background:#1c4f8f; color:#fff; font-family:'Segoe UI',Inter; box-shadow:0 30px 80px -20px rgba(0,0,0,.5); }
      .smart h3 { margin:0; font-size:40px; font-weight:400; letter-spacing:-.01em; }
      .smart p { font-size:19px; line-height:1.45; color:#e8eef7; margin:22px 0 0; }
      .smart .enlace { margin-top:18px; font-size:19px; text-decoration:underline; color:#fff; display:inline-block; }
      .smart .dato { font-size:19px; color:#e8eef7; margin-top:10px; }
      .smart .pie { position:absolute; right:30px; bottom:26px; display:flex; gap:12px; }
      .smart .bw { height:40px; padding:0 22px; display:flex; align-items:center; border:2px solid #fff; font-size:18px; color:#fff; }
      .win { position:absolute; background:#fff; border-radius:10px; overflow:hidden; font-family:'Segoe UI',Inter;
             box-shadow:0 0 0 1px rgba(0,0,0,.12), 0 30px 70px -18px rgba(28,31,38,.40); }
      .win .tit { height:40px; display:flex; align-items:center; gap:10px; padding-left:14px; font-size:15px; color:#26292f; background:#f3f3f3; }
      .win .tit .x { margin-left:auto; width:46px; height:40px; display:grid; place-items:center; color:#555; font-size:18px; }
      .win .op { display:flex; gap:16px; align-items:flex-start; padding:16px 18px; border-radius:8px; margin:0 26px 10px; }
      .win .op strong { display:block; font-size:19px; font-weight:600; color:#1c4f8f; } .win .op small { display:block; margin-top:4px; font-size:15px; color:#555; }
      .terminal { position:absolute; border-radius:14px; overflow:hidden; background:#1e2127; font-family:'JetBrains Mono',monospace;
                  box-shadow:0 0 0 1px rgba(0,0,0,.25), 0 30px 70px -18px rgba(0,0,0,.5); }
      .terminal .tit { height:40px; display:flex; align-items:center; gap:8px; padding-left:16px; background:#2b2f36; color:#b9c0ca; font-family:Inter; font-size:15px; position:relative; }
      .terminal .tit i { width:13px; height:13px; border-radius:50%; background:#4a505a; display:block; }
      .terminal .tit b { position:absolute; left:0; right:0; text-align:center; font-weight:600; }
      .terminal .lin { padding:0 26px; font-size:24px; line-height:44px; color:#e6e9ee; white-space:pre; }
      .terminal .pr { color:#8ccf8c; }
      .tarjeta { position:absolute; background:#fff; border-radius:20px; font-family:Inter;
                 box-shadow:0 0 0 1px rgba(28,31,38,.07), 0 18px 44px -12px rgba(28,31,38,.25); }
      .dlg { position:absolute; width:620px; border-radius:18px; background:#fff; padding:30px 32px 24px; font-family:Inter;
             box-shadow:0 0 0 1px rgba(28,31,38,.08), 0 36px 90px -24px rgba(28,31,38,.40); }
      .dlg h3 { margin:0 0 20px; font-size:28px; font-weight:700; color:#1c1f26; letter-spacing:-.01em; }
      .dlg .dato { display:flex; font-size:20px; line-height:40px; color:#1c1f26; } .dlg .dato span { width:230px; color:#62697a; }
      .dlg .pie { display:flex; justify-content:flex-end; gap:14px; margin-top:26px; }
      .dlg .pie div { height:48px; padding:0 22px; border-radius:24px; display:flex; align-items:center; font-weight:700; font-size:19px; }
    `,
  });

  // --------------------------------------------------------------- fondo --

  nodo({ clase: 'fondo' });
  nodo({ clase: 'reticula' });
  for (const e of G.escenas) {
    if (!e.capitulo) continue;
    const chip = nodo({ clase: 'capitulo', html: `<span class="numero">${e.numero}</span>${e.capitulo}`, estilo: { left: '60px', top: '48px', zIndex: 50 } });
    const hasta = Math.min(e.ini + 3.4, e.fin - 0.3);
    anim(chip, [
      [e.ini + 0.1, { o: 0, x: -16 }],
      [e.ini + 0.6, { o: 1, x: 0 }, 'sale4'],
      [hasta, { o: 1, x: 0 }],
      [hasta + 0.5, { o: 0, x: -10 }, 'suave'],
    ]);
  }
  const progreso = nodo({ clase: 'progreso', estilo: { width: `${W}px`, zIndex: 60 } });
  tarea((t) => {
    progreso.style.transform = `scaleX(${Math.min(1, t / G.total)})`;
  });
  for (const id of ['descargar', 'macos', 'windows', 'linux', 'al-dia', 'cierre']) sonido(G.escena(id).ini, 'soplo', 0.8);

  // ------------------------------------------------------------ apertura --
  {
    const a = G.escena('apertura');
    const g = capa();
    const m = E.marca({ tam: 190, x: W / 2 - 95, y: 196, padre: g });
    m.baldosa.style.transformBox = 'fill-box';
    m.baldosa.style.transformOrigin = '50% 50%';
    anim(m.baldosa, [
      [a.ini + 0.1, { o: 0, s: 0.5 }],
      [a.ini + 0.75, { o: 1, s: 1 }, 'rebote'],
    ]);
    m.hojas.forEach((h, i) =>
      anim(h, [
        [a.ini + 0.35 + 0.1 * i, { o: 0, x: -8, y: 10 }],
        [a.ini + 0.85 + 0.1 * i, { o: 1, x: 0, y: 0 }, 'sale4'],
      ]),
    );
    const ante = centrado(`${V.codigo} · ${V.ruta}`, 452, {}, g);
    ante.className = 'antetitulo';
    Object.assign(ante.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    entra(ante, a.ini + 0.8, { dy: 16 });
    const titulo = centrado('', 502, { fontSize: '112px' }, g);
    titulo.className = 'titular';
    Object.assign(titulo.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    titulo.textContent = V.titulo;
    E.palabras(titulo, a.ini + 0.95, { paso: 0.09, dy: 40 });
    const sub = centrado(V.subtitulo, 650, { fontSize: '40px' }, g);
    sub.className = 'entradilla';
    Object.assign(sub.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    entra(sub, a.ini + 1.55, { dy: 20 });
    // Lo que habrá al acabar, dicho en una línea: instalada, abierta y con
    // la protección del sistema en su sitio.
    const promesa = centrado(
      `<span class="chip" style="font-size:26px">${icono.escudo}Sin desactivar ninguna protección</span>`,
      758,
      {},
      g,
    );
    entra(promesa, G.palabra('presentacion', 'protección') - 0.5, { dy: 18, curva: 'rebote' });
    sale(g, a.fin - 0.5, { dur: 0.5, dy: -30 });
  }

  // ----------------------------------------------------------- descargar --
  {
    const d = G.escena('descargar');
    const g = capa();
    const cam = E.camara(g);
    const v = E.ventana({ captura: 'descargas', x: 260, y: 70, ancho: 1400, padre: g, camara: cam });
    anim(v.raiz, [
      [d.ini, { o: 0, y: 60, s: 0.97 }],
      [d.ini + 0.7, { o: 1, y: 0, s: 1 }, 'sale4'],
    ]);
    const tMac = G.palabra('web', 'macOS');
    const tarjetas = ['tarjeta-macos', 'tarjeta-windows', 'tarjeta-linux'].map((z) => v.zona(z));
    const x0 = Math.min(...tarjetas.map((r) => r.x));
    const y0 = Math.min(...tarjetas.map((r) => r.y));
    const todas = { x: x0, y: y0, w: Math.max(...tarjetas.map((r) => r.x + r.w)) - x0, h: Math.max(...tarjetas.map((r) => r.y + r.h)) - y0 };
    cam.enfocar(tMac - 0.9, tMac + 0.1, todas, { margen: 0.07, max: 1.7 });
    [
      ['macos', 'macOS', '.dmg'],
      ['windows', 'Windows', '.exe'],
      ['linux', 'Linux', '.AppImage'],
    ].forEach(([zona, nombre, ext]) => {
      const t = G.palabra('web', nombre);
      E.resaltar(v, zona, { t0: t - 0.15, t1: d.fin - 0.35, etiqueta: `${nombre} <span style="opacity:.75;font-weight:600">${ext}</span>`, lado: 'derecha', pad: 6 });
    });
    visible(g, d.ini, d.fin + 0.05, 0.3, 0.4);
  }

  // --------------------------------------------------------------- macOS --
  {
    const s = G.escena('macos');
    const g = capa();

    // El fichero bajado, que se abre en la ventana del disco.
    const tAbre = G.palabra('arrastrar', 'abre');
    const dmg = caja(g, W / 2 - 330, 470, 660, 110, 'tarjeta', `<div style="display:flex;align-items:center;gap:22px;padding:18px 26px"><div style="width:58px;height:72px">${icono.fichero('DMG', '#6b707a')}</div><div class="mono" style="font-size:24px;font-weight:600">${ficheros.macos}</div></div>`);
    anim(dmg, [
      [s.ini + 0.2, { o: 0, y: 30 }],
      [s.ini + 0.8, { o: 1, y: 0 }, 'sale4'],
      [tAbre + 0.2, { o: 1, s: 1 }],
      [tAbre + 0.7, { o: 0, s: 1.25 }, 'entra'],
    ]);

    // La ventana del disco: Didacta, una flecha y Aplicaciones.
    const fx = 460;
    const fy = 250;
    const fw = 1000;
    const fh = 560;
    const finder = caja(g, fx, fy, fw, fh, 'mac', `<div class="tit"><i></i><i></i><i></i><b>Didacta ${version}</b></div>`);
    const tArrastra = G.palabra('arrastrar', 'arrastra');
    const tAplic = G.palabra('arrastrar', 'Aplicaciones', { fin: true });
    const tAviso = G.frase('aviso').ini;
    anim(finder, [
      [tAbre + 0.25, { o: 0, s: 0.9 }],
      [tAbre + 0.85, { o: 1, s: 1 }, 'sale4'],
      [tAviso - 0.1, { o: 1, blur: 0 }],
      [tAviso + 0.4, { o: 0.35, blur: 4 }],
      [G.frase('abrir-igualmente').ini + 0.4, { o: 0.35 }],
      [G.frase('abrir-igualmente').ini + 0.9, { o: 0 }],
    ]);
    const app = E.marca({ tam: 170, x: 190, y: 170, padre: finder });
    const rotApp = caja(finder, 150, 356, 250, 40, '', 'Didacta', { textAlign: 'center', fontSize: '22px', fontWeight: 600 });
    const destino = caja(finder, 620, 180, 180, 150, '', icono.carpeta());
    caja(finder, 585, 356, 250, 40, '', 'Aplicaciones', { textAlign: 'center', fontSize: '22px', fontWeight: 600 });
    caja(finder, 400, 230, 200, 40, '', '<svg viewBox="0 0 200 40" width="200" height="40"><path d="M10 20h160" stroke="#b9bfb5" stroke-width="5" stroke-dasharray="4 12" stroke-linecap="round"/><path d="M162 8l18 12-18 12" fill="none" stroke="#b9bfb5" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>');
    caja(finder, 0, 450, fw, 40, '', 'Arrastra Didacta a la carpeta Aplicaciones', { textAlign: 'center', fontSize: '19px', color: '#8a9097' });
    anim(destino, [
      [tAplic - 0.05, { s: 1 }],
      [tAplic + 0.15, { s: 1.12 }, 'sale'],
      [tAplic + 0.5, { s: 1 }, 'rebote'],
    ]);
    destino.style.transformOrigin = '50% 60%';

    // Lo que se arrastra: una copia del icono que sigue al puntero.
    const inicio = { x: fx + 190 + 85, y: fy + 170 + 85, lienzo: true };
    const fin = { x: fx + 620 + 90, y: fy + 180 + 80, lienzo: true };
    const fantasma = E.marca({ tam: 150, x: 0, y: 0, padre: g });
    fantasma.raiz.style.zIndex = 44;
    anim(fantasma.raiz, [
      [0, { o: 0 }],
      [tArrastra, { o: 0 }],
      [tArrastra + 0.12, { o: 0.75 }],
      [tAplic, { o: 0.75 }],
      [tAplic + 0.2, { o: 0 }],
    ]);
    const cur = E.cursor(null, { padre: g, desde: { x: fx + fw + 120, y: fy + fh + 80, lienzo: true } });
    cur.mostrar(tAbre + 0.8, tAviso + 0.2);
    cur.ir(tAbre + 0.9, tArrastra - 0.05, { ...inicio, x: inicio.x + 10, y: inicio.y + 12 });
    cur.ir(tArrastra + 0.1, tAplic, { ...fin, x: fin.x + 10, y: fin.y + 12 });
    cur.clic(tArrastra);
    tarea((t) => {
      if (t < tArrastra || t > tAplic + 0.3) return;
      const u = E.curvas.muysuave(E.clamp((t - tArrastra - 0.1) / (tAplic - tArrastra - 0.1), 0, 1));
      const mx = (inicio.x + fin.x) / 2 - (fin.y - inicio.y) * 0.12;
      const my = (inicio.y + fin.y) / 2 + (fin.x - inicio.x) * 0.12;
      const x = (1 - u) * (1 - u) * inicio.x + 2 * (1 - u) * u * mx + u * u * fin.x;
      const y = (1 - u) * (1 - u) * inicio.y + 2 * (1 - u) * u * my + u * u * fin.y;
      fantasma.raiz.style.left = `${x - 75}px`;
      fantasma.raiz.style.top = `${y - 75}px`;
    });
    anim(app.raiz, [
      [tArrastra, { o: 1 }],
      [tArrastra + 0.1, { o: 0.45 }],
    ]);
    anim(rotApp, [[tArrastra, { o: 1 }], [tArrastra + 0.1, { o: 0.45 }]]);

    // El aviso de Gatekeeper.
    const ax = W / 2 - 220;
    const ay = 230;
    const alerta = caja(
      g,
      ax,
      ay,
      440,
      null,
      'alerta',
      `<div class="ic" style="width:84px;height:84px;margin:0 auto;position:relative"></div>
       <h3>No se ha abierto «Didacta»</h3>
       <p>Apple no ha podido verificar que «Didacta» esté libre de malware que pueda dañar el Mac o poner en peligro tu privacidad.</p>
       <div class="btn azul">Aceptar</div><div class="btn gris">Trasladar a la papelera</div>`,
    );
    alerta.style.zIndex = 20;
    E.marca({ tam: 84, x: 0, y: 0, padre: alerta.querySelector('.ic') });
    const tCierra = G.frase('abrir-igualmente').ini;
    anim(alerta, [
      [tAviso + 0.1, { o: 0, s: 0.92 }],
      [tAviso + 0.6, { o: 1, s: 1 }, 'rebote'],
      [tCierra + 0.35, { o: 1, s: 1 }],
      [tCierra + 0.7, { o: 0, s: 0.95 }, 'entra'],
    ]);
    const tFirma = G.palabra('aviso', 'firmada');
    const titAlerta = alerta.querySelector('h3');
    E.resaltar(null, () => rect(alerta), {
      t0: tFirma - 0.2,
      t1: tCierra,
      color: '#be8237',
      etiqueta: 'Es por la firma que falta, nada más',
      lado: 'derecha',
      pad: 6,
      caja: false,
      padre: g,
    });
    const cur2 = E.cursor(null, { padre: g, desde: { x: ax + 520, y: ay + 520, lienzo: true } });
    const botonAceptar = alerta.querySelector('.btn.azul');
    cur2.mostrar(tCierra - 0.9, tCierra + 0.5);
    cur2.ir(tCierra - 0.8, tCierra + 0.1, { ...centro(botonAceptar), dx: 0 });
    cur2.clic(tCierra + 0.2);

    // Ajustes del Sistema → Privacidad y seguridad → Seguridad.
    const tAjustes = G.palabra('abrir-igualmente', 'Ajustes');
    const tPriv = G.palabra('abrir-igualmente', 'Privacidad');
    const tAbajo = G.palabra('abrir-igualmente', 'Abajo');
    const tPulsa = G.palabra('abrir-igualmente', 'pulsa');
    const tIgual = G.palabra('abrir-igualmente', 'igualmente', { fin: true });
    const sx = 330;
    const sy = 150;
    const sw = 1260;
    const sh = 700;
    const colores = ['#2f8cf5', '#2f8cf5', '#2f8cf5', '#ef4a4a', '#ef4a4a', '#6e5ce6', '#8e8e93', '#1c1f26', '#2f8cf5', '#30b0c7', '#2f8cf5'];
    const items = ['Wi‑Fi', 'Bluetooth', 'Red', 'Notificaciones', 'Sonido', 'Concentración', 'General', 'Apariencia', 'Privacidad y seguridad', 'Escritorio y Dock', 'Pantallas'];
    const ajustes = caja(
      g,
      sx,
      sy,
      sw,
      sh,
      'mac ajustes',
      `<div class="tit"><i></i><i></i><i></i><b>Ajustes del Sistema</b></div>
       <div class="lado"><div class="buscar">Buscar</div>${items.map((x, i) => `<div class="item" data-i="${i}"><span style="background:${colores[i]}"></span>${x}</div>`).join('')}</div>
       <div class="panel"><div class="dentro">
         <h2>Privacidad y seguridad</h2>
         <div class="grupo">${['Localización', 'Cámara', 'Micrófono', 'Fotos', 'Archivos y carpetas', 'Accesibilidad'].map((x) => `<div class="fila">${x}<span class="valor">›</span></div>`).join('')}</div>
         <h4>Seguridad</h4>
         <div class="grupo">
           <div class="fila">Permitir aplicaciones de<span class="valor">App Store y desarrolladores identificados</span></div>
           <div class="fila bloqueada"><span style="flex:1">Se ha bloqueado el uso de «Didacta» porque no es de un desarrollador identificado.</span><span class="boton">Abrir igualmente</span></div>
         </div>
       </div></div>`,
    );
    const sel = ajustes.querySelector('.item[data-i="8"]');
    anim(ajustes, [
      [tAjustes - 0.4, { o: 0, y: 50, s: 0.97 }],
      [tAjustes + 0.3, { o: 1, y: 0, s: 1 }, 'sale4'],
    ]);
    tarea((t) => sel.classList.toggle('sel', t >= tPriv));
    const dentro = ajustes.querySelector('.dentro');
    anim(dentro, [
      [tAbajo - 0.2, { y: 0 }],
      [tAbajo + 0.8, { y: -300 }, 'muysuave'],
    ]);
    const botonAbrir = ajustes.querySelector('.boton');
    const zonaBoton = () => {
      const r = rect(botonAbrir);
      return { ...r, y: r.y + E.valor(dentro, 'y', tPulsa + 1, -300) };
    };
    E.resaltar(null, zonaBoton, { t0: tPulsa - 0.1, t1: G.frase('contrasena').ini + 0.3, etiqueta: 'Abrir igualmente', lado: 'abajo', alinear: 'derecha', pad: 6, padre: g });
    const cur3 = E.cursor(null, { padre: g, desde: { x: sx + 180, y: sy + 700, lienzo: true } });
    cur3.mostrar(tAjustes + 0.3, G.frase('contrasena').ini + 0.4);
    cur3.ir(tPriv - 0.6, tPriv, { ...centro(sel) });
    cur3.clic(tPriv);
    cur3.ir(tPulsa, tIgual - 0.1, { ...zonaBoton(), x: zonaBoton().x + zonaBoton().w / 2, y: zonaBoton().y + zonaBoton().h / 2, lienzo: true });
    cur3.clic(tIgual);

    // La contraseña, una vez; y Didacta, abierta.
    const tCon = G.frase('contrasena').ini;
    const tVez = G.palabra('contrasena', 'vez', { fin: true });
    const tPartir = G.palabra('contrasena', 'partir');
    const hojaCon = caja(
      g,
      W / 2 - 210,
      300,
      420,
      null,
      'hoja-mac',
      `<div style="width:60px;height:60px;margin:0 auto;border-radius:14px;background:#8e8e93;display:grid;place-items:center"><svg viewBox="0 0 24 24" width="34" height="34"><path d="M7 10V7a5 5 0 0 1 10 0v3M5 10h14v11H5z" fill="none" stroke="#fff" stroke-width="2"/></svg></div>
       <h3>Ajustes del Sistema quiere hacer cambios</h3><p>Introduce tu contraseña para permitirlo.</p>
       <div class="campo">Profe</div><div class="campo punto"></div>
       <div class="dos"><div class="btn gris">Cancelar</div><div class="btn azul">Aceptar</div></div>`,
    );
    hojaCon.style.zIndex = 21;
    anim(hojaCon, [
      [tCon - 0.1, { o: 0, y: -30 }],
      [tCon + 0.4, { o: 1, y: 0 }, 'sale4'],
      [tVez + 0.35, { o: 1 }],
      [tVez + 0.7, { o: 0 }],
    ]);
    teclear(hojaCon.querySelector('.punto'), '●●●●●●●●●●', tCon + 0.5, tCon + 1.5);
    const cur4 = E.cursor(null, { padre: g, desde: { x: W / 2 + 300, y: 800, lienzo: true } });
    const aceptar = hojaCon.querySelector('.btn.azul');
    cur4.mostrar(tCon + 1.2, tVez + 0.6);
    cur4.ir(tCon + 1.3, tVez - 0.1, { ...centro(aceptar) });
    cur4.clic(tVez);
    anim(ajustes, [
      [tVez + 0.3, { o: 1, blur: 0 }],
      [tVez + 0.8, { o: 0, blur: 6 }],
    ]);
    const v = E.ventana({ captura: 'bienvenida', x: 360, y: 150, ancho: 1200, padre: g });
    anim(v.raiz, [
      [tPartir - 0.5, { o: 0, y: 40, s: 0.96 }],
      [tPartir + 0.2, { o: 1, y: 0, s: 1 }, 'sale4'],
    ]);
    const tCual = G.palabra('contrasena', 'cualquier');
    E.resaltar(v, () => ({ x: v.x, y: v.y, w: v.ancho, h: v.alto }), { t0: tCual - 0.2, t1: s.fin - 0.2, caja: false, etiqueta: `${icono.ok.replace('#346e34', '#ffffff').replace('stroke="#fff"', 'stroke="#346e34"')}Abierta, sin desactivar nada`, lado: 'abajo', pad: -60 });
    visible(g, s.ini, s.fin + 0.05, 0.3, 0.4);
  }

  // ------------------------------------------------------------- Windows --
  {
    const s = G.escena('windows');
    const g = capa();
    const tIni = s.ini;
    const exe = caja(g, W / 2 - 330, 470, 660, 110, 'tarjeta', `<div style="display:flex;align-items:center;gap:22px;padding:18px 26px"><div style="width:58px;height:72px">${icono.fichero('EXE', '#2d5fa0')}</div><div class="mono" style="font-size:24px;font-weight:600">${ficheros.windows}</div></div>`);
    const tEjecuta = G.palabra('smartscreen', 'ejecuta');
    const tProt0 = G.palabra('smartscreen', 'protegido');
    anim(exe, [
      [tIni + 0.2, { o: 0, y: 30 }],
      [tIni + 0.8, { o: 1, y: 0 }, 'sale4'],
      [tProt0 - 0.6, { o: 1, s: 1 }],
      [tProt0 - 0.2, { o: 0, s: 1.15 }, 'entra'],
    ]);
    const curExe = E.cursor(null, { padre: g, desde: { x: W / 2 + 420, y: 760, lienzo: true } });
    curExe.mostrar(tIni + 0.6, tProt0 - 0.2);
    curExe.ir(tIni + 0.7, tEjecuta + 0.2, { x: W / 2 - 250, y: 530, lienzo: true });
    curExe.clic(tEjecuta + 0.35);
    curExe.clic(tEjecuta + 0.55);

    // SmartScreen: primero el aviso; con «Más información», el botón.
    const tProt = G.palabra('smartscreen', 'protegido');
    const tMas = G.palabra('smartscreen', 'Más información');
    const tEjec = G.palabra('smartscreen', 'Ejecutar de todas formas');
    const tFin = G.frase('smartscreen').fin;
    const bx = W / 2 - 420;
    const by = 230;
    const smart = caja(g, bx, by, 840, 430, 'smart');
    const uno = caja(
      smart,
      0,
      0,
      840,
      430,
      '',
      `<div style="padding:44px 48px"><h3>Windows protegió su PC</h3>
       <p>Microsoft Defender SmartScreen impidió el inicio de una aplicación desconocida. Ejecutar esta aplicación puede poner su PC en riesgo.</p>
       <span class="enlace">Más información</span></div><div class="pie"><div class="bw">No ejecutar</div></div>`,
    );
    const dos = caja(
      smart,
      0,
      0,
      840,
      430,
      '',
      `<div style="padding:44px 48px"><h3>Windows protegió su PC</h3>
       <p>Microsoft Defender SmartScreen impidió el inicio de una aplicación desconocida. Ejecutar esta aplicación puede poner su PC en riesgo.</p>
       <div class="dato" style="margin-top:22px">Aplicación: ${ficheros.windows}</div><div class="dato">Editor: Editor desconocido</div></div>
       <div class="pie"><div class="bw ejecutar">Ejecutar de todas formas</div><div class="bw">No ejecutar</div></div>`,
    );
    anim(smart, [
      [tProt - 0.5, { o: 0, s: 0.95 }],
      [tProt + 0.1, { o: 1, s: 1 }, 'sale4'],
      [tFin + 0.3, { o: 1 }],
      [tFin + 0.7, { o: 0 }],
    ]);
    anim(uno, [[tMas + 0.25, { o: 1 }], [tMas + 0.45, { o: 0 }]]);
    anim(dos, [[0, { o: 0 }], [tMas + 0.25, { o: 0 }], [tMas + 0.45, { o: 1 }]]);
    const enlace = uno.querySelector('.enlace');
    const ejecutar = dos.querySelector('.ejecutar');
    const cur = E.cursor(null, { padre: g, desde: { x: bx + 900, y: by + 600, lienzo: true } });
    cur.mostrar(tProt + 0.1, tFin + 0.5);
    cur.ir(tMas - 0.7, tMas + 0.05, { ...centro(enlace) });
    cur.clic(tMas + 0.15);
    cur.ir(tMas + 0.6, tEjec + 0.3, { ...centro(ejecutar) });
    cur.clic(tEjec + 0.45);
    E.resaltar(null, () => rect(ejecutar), { t0: tEjec - 0.05, t1: tFin + 0.2, etiqueta: 'Falta la firma, como en el Mac', color: '#be8237', lado: 'arriba', alinear: 'derecha', pad: 6, padre: g });

    // Solo para ti: sin administrador.
    const tPara = G.frase('para-ti').ini;
    const tAdmin = G.palabra('para-ti', 'administrador', { fin: true });
    const inno = caja(
      g,
      W / 2 - 640,
      260,
      780,
      null,
      'win',
      `<div class="tit"><span style="width:18px;height:18px;border-radius:4px;background:#55aa55;display:block"></span>Seleccione el modo de instalación<span class="x">✕</span></div>
       <div style="padding:26px 30px 10px;font-size:18px;color:#26292f;line-height:1.45">Didacta puede instalarse solo para usted o para todos los usuarios de este equipo.</div>
       <div class="op mi" style="background:#eef5ff"><span style="font-size:26px;color:#1c4f8f">→</span><div><strong>Instalar para mí solamente (recomendado)</strong><small>Sin privilegios de administrador</small></div></div>
       <div class="op" style="margin-bottom:26px"><span style="font-size:22px">🛡</span><div><strong style="color:#555">Instalar para todos los usuarios</strong><small>Requiere privilegios de administrador</small></div></div>`,
    );
    anim(inno, [
      [tPara - 0.1, { o: 0, y: 40 }],
      [tPara + 0.5, { o: 1, y: 0 }, 'sale4'],
    ]);
    const mi = inno.querySelector('.op.mi');
    E.resaltar(null, () => rect(mi), { t0: G.palabra('para-ti', 'solo') - 0.1, t1: G.frase('python').ini, etiqueta: `${icono.escudo.replace('#346e34', '#ffffff').replace('stroke="#fff"', 'stroke="#346e34"')}Sin contraseña de administrador`, lado: 'derecha', pad: 4, padre: g });
    anim(inno, [
      [tAdmin + 0.5, { o: 1, y: 0 }],
      [G.frase('python').ini + 0.2, { o: 0, y: -30 }],
    ]);

    // Python: el de python.org, no el que trae Windows.
    const tPy = G.frase('python').ini;
    const tOrg = G.palabra('python', 'python.org');
    const tTienda = G.palabra('python', 'tienda');
    const bien = caja(
      g,
      W / 2 - 700,
      330,
      640,
      300,
      'tarjeta',
      `<div style="padding:40px 44px"><div style="display:flex;align-items:center;gap:16px;font-size:34px;font-weight:800">${icono.ok}python.org</div>
       <div style="margin-top:18px;font-size:23px;color:#62697a;line-height:1.45">Descarga Python 3.9 o posterior. Didacta lo encuentra sola, sin tocar el PATH.</div></div>`,
    );
    const mal = caja(
      g,
      W / 2 + 60,
      330,
      640,
      300,
      'tarjeta',
      `<div style="padding:40px 44px"><div style="display:flex;align-items:center;gap:16px;font-size:34px;font-weight:800">${icono.no}<span class="mono" style="font-size:32px">python.exe</span></div>
       <div style="margin-top:18px;font-size:23px;color:#62697a;line-height:1.45">El que trae Windows no es un Python: solo abre la Microsoft Store.</div></div>`,
    );
    const titPy = centrado('Lo que Windows no trae', 220, { fontSize: '52px' }, g);
    titPy.className = 'titular';
    Object.assign(titPy.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    entra(titPy, tPy + 0.1, { dy: 20 });
    entra(bien, tOrg - 0.3, { dy: 30 });
    entra(mal, tTienda - 0.9, { dy: 30 });
    visible(g, s.ini, s.fin + 0.05, 0.3, 0.4);
  }

  // --------------------------------------------------------------- Linux --
  {
    const s = G.escena('linux');
    const g = capa();
    const tPermiso = G.palabra('appimage', 'permiso');
    const tAbrelo = G.palabra('appimage', 'ábrelo');
    const tDonde = G.frase('donde').ini;
    const term = caja(g, W / 2 - 560, 200, 1120, 210, 'terminal', `<div class="tit"><i></i><i></i><i></i><b>Terminal</b></div><div style="height:26px"></div><div class="lin"><span class="pr">~/Descargas $ </span><span class="c1"></span></div><div class="lin"><span class="pr p2">~/Descargas $ </span><span class="c2"></span></div>`);
    const orden1 = `chmod +x ${ficheros.linux}`;
    const orden2 = `./${ficheros.linux}`;
    teclear(term.querySelector('.c1'), orden1, tPermiso - 0.2, tPermiso + 1.0);
    teclear(term.querySelector('.c2'), orden2, tAbrelo - 0.5, tAbrelo + 0.3);
    const p2 = term.querySelector('.p2');
    tarea((t) => {
      p2.style.visibility = t >= tPermiso + 1.1 ? 'visible' : 'hidden';
    });
    anim(term, [
      [s.ini + 0.1, { o: 0, y: 40 }],
      [s.ini + 0.7, { o: 1, y: 0 }, 'sale4'],
      [tDonde - 0.2, { o: 1, y: 0 }],
      [tDonde + 0.3, { o: 0, y: -30 }],
    ]);
    const abierta = E.ventana({ captura: 'bienvenida', x: W / 2 - 330, y: 470, ancho: 660, padre: g });
    anim(abierta.raiz, [
      [tAbrelo + 0.4, { o: 0, y: 30, s: 0.94 }],
      [tAbrelo + 0.9, { o: 1, y: 0, s: 1 }, 'rebote'],
      [tDonde - 0.2, { o: 1 }],
      [tDonde + 0.3, { o: 0 }],
    ]);

    // Donde se deje, ahí se actualiza.
    const tCarpeta = G.palabra('donde', 'carpeta');
    const tAct = G.palabra('donde', 'actualizará');
    const carpeta = caja(g, W / 2 - 130, 330, 260, 210, '', icono.carpeta('#7fb86f'));
    caja(g, W / 2 - 180, 548, 360, 50, '', '<span class="mono" style="font-size:26px;font-weight:600">~/Aplicaciones</span>', { textAlign: 'center' });
    const fich = caja(g, W / 2 - 600, 350, 150, 190, '', icono.fichero('APP', '#346e34'));
    const nombre = caja(g, W / 2 - 740, 552, 430, 40, '', `<span class="mono" style="font-size:19px">${ficheros.linux}</span>`, { textAlign: 'center' });
    const grupoCarpeta = [carpeta, carpeta.nextSibling];
    for (const n of grupoCarpeta) entra(n, tDonde + 0.2, { dy: 20 });
    entra(fich, tDonde + 0.1, { dy: 20 });
    entra(nombre, tDonde + 0.1, { dy: 20 });
    anim(fich, [
      [tCarpeta, { x: 0, y: 0, s: 1 }],
      [tCarpeta + 1.0, { x: 520, y: -10, s: 0.62 }, 'muysuave'],
      [tCarpeta + 1.2, { o: 1 }],
      [tCarpeta + 1.45, { o: 0 }],
    ]);
    anim(nombre, [[tCarpeta, { o: 1 }], [tCarpeta + 0.4, { o: 0 }]]);
    const aqui = centrado(`<span class="chip" style="font-size:28px">${icono.ok}Se actualiza aquí, en su sitio</span>`, 680, {}, g);
    entra(aqui, tAct - 0.4, { dy: 18, curva: 'rebote' });
    visible(g, s.ini, s.fin + 0.05, 0.3, 0.4);
  }

  // -------------------------------------------------------------- al día --
  {
    const s = G.escena('al-dia');
    const g = capa();
    const tTres = G.palabra('actualiza', 'tres');
    const tPregunta = G.palabra('actualiza', 'pregunta');
    const [ma, mi, pa] = version.split('.').map(Number);
    const siguienteVersion = `${ma}.${mi}.${(pa || 0) + 1}`;
    const dlg = caja(
      g,
      W / 2 - 310,
      200,
      620,
      null,
      'dlg',
      `<h3>Hay una versión nueva de Didacta</h3>
       <div class="dato"><span>Versión instalada</span>${version}</div>
       <div class="dato"><span>Nueva versión</span>${siguienteVersion}</div>
       <div class="pie"><div class="botones" style="display:flex;gap:14px;padding:0;height:auto"><div style="color:#346e34">Más tarde</div><div style="background:#346e34;color:#fff">Actualizar ahora</div></div></div>`,
    );
    entra(dlg, s.ini + 0.2, { dy: 40 });
    const pie = dlg.querySelector('.botones');
    E.resaltar(null, () => rect(pie), { t0: tPregunta - 0.15, t1: s.fin - 0.2, etiqueta: 'Pregunta antes', lado: 'abajo', alinear: 'derecha', pad: 8, padre: g });
    ['macOS', 'Windows', 'Linux'].forEach((nombre, k) => {
      const chip = nodo({ padre: g, clase: 'chip', html: `${icono.ok}${nombre}`, estilo: { position: 'absolute', left: `${W / 2 - 390 + k * 270}px`, top: '640px', fontSize: '28px' } });
      entra(chip, tTres - 0.2 + 0.15 * k, { dy: 18, curva: 'rebote' });
    });
    visible(g, s.ini, s.fin + 0.05, 0.3, 0.4);
  }

  // -------------------------------------------------------------- cierre --
  {
    const z = G.escena('cierre');
    const g = capa();
    const m = E.marca({ tam: 150, x: W / 2 - 75, y: 200, padre: g });
    m.baldosa.style.transformBox = 'fill-box';
    m.baldosa.style.transformOrigin = '50% 50%';
    anim(m.baldosa, [[z.ini, { o: 0, s: 0.6 }], [z.ini + 0.6, { o: 1, s: 1 }, 'rebote']]);
    m.hojas.forEach((h, i) => anim(h, [[z.ini + 0.2 + 0.08 * i, { o: 0, x: -6, y: 8 }], [z.ini + 0.7 + 0.08 * i, { o: 1, x: 0, y: 0 }, 'sale4']]));
    const l1 = centrado('', 420, { fontSize: '80px' }, g);
    l1.className = 'titular';
    Object.assign(l1.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    l1.textContent = 'El aviso es por la firma que falta,';
    E.palabras(l1, G.frase('lema').ini - 0.15, { paso: 0.08 });
    const l2 = centrado('', 516, { fontSize: '80px' }, g);
    l2.className = 'titular';
    Object.assign(l2.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center', color: 'var(--verde-oscuro)' });
    l2.textContent = 'no por la aplicación.';
    E.palabras(l2, G.palabra('lema', 'no por') - 0.25, { paso: 0.1 });
    const sig = centrado(`<span class="chip" style="font-size:30px;padding:14px 26px 14px 20px"><span class="punto" style="background:var(--verde-oscuro)"></span>Siguiente&nbsp;&nbsp;<b>${V.siguiente}</b></span>`, 700, {}, g);
    entra(sig, G.frase('siguiente').ini - 0.1, { dy: 20 });
    const url = centrado('franjfal.github.io/didacta', 812, { fontSize: '26px', fontWeight: 600, color: 'var(--apagado)', letterSpacing: '0.01em' }, g);
    entra(url, G.frase('siguiente').ini + 0.5, { dy: 10 });
    visible(g, z.ini, G.total + 1, 0.3, 0.01);
  }
};
