/* A3 · Entrar con tu cuenta de GitHub: lo que el guion no puede decir solo.
 *
 * El resto del montaje sale del guion (`estudio/recorrido.js`). Aquí se
 * dibujan las dos páginas de github.com --pegar el código y elegir los
 * repositorios--, que no se pueden fotografiar sin entrar de verdad. Van en
 * inglés, que es como las enseña GitHub; la voz dice qué hacer en ellas.
 */
window.montaje = function (E, G, D) {
  const { W, H, nodo, anim, tarea } = E;

  const capa = () => nodo({ clase: 'capa', estilo: { width: `${W}px`, height: `${H}px`, zIndex: 10 } });
  const visible = (n, ini, fin) =>
    anim(n, [
      [ini, { o: 0 }],
      [ini + 0.4, { o: 1 }, 'sale'],
      [fin - 0.4, { o: 1 }],
      [fin, { o: 0 }, 'suave'],
    ]);
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

  /** Una ventana de navegador con una página dibujada dentro. */
  function navegador(g, direccion, html, o = {}) {
    const ancho = o.ancho || 1300;
    const alto = o.alto || 760;
    const x = (W - ancho) / 2;
    const y = o.y ?? (H - alto) / 2 + 20;
    const raiz = nodo({ clase: 'ventana', padre: g, estilo: { left: `${x}px`, top: `${y}px`, width: `${ancho}px`, height: `${alto}px` } });
    nodo({
      clase: 'barra navegador',
      padre: raiz,
      html: `<i></i><i></i><i></i><span class="flechas">‹ ›</span><span class="direccion"><svg viewBox="0 0 16 16"><path d="M4.5 7V5a3.5 3.5 0 0 1 7 0v2M3.5 7h9v6.5h-9z" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>${direccion}</span>`,
    });
    const pagina = nodo({ padre: raiz, clase: 'abs', html, estilo: { top: '52px', left: 0, width: `${ancho}px`, height: `${alto - 52}px`, background: '#f6f8fa', fontFamily: 'Inter' } });
    return { raiz, pagina, x, y, ancho, alto };
  }

  const gato = `<div style="width:64px;height:64px;margin:0 auto;color:#1f2328">${Recorrido.ICONOS.github}</div>`;
  const verde = 'background:#1f883d;color:#fff;border-radius:8px;font-weight:600;display:flex;align-items:center;justify-content:center';

  Recorrido.montar(E, G, D, {
    // Pegar el código y autorizar.
    github({ escena }) {
      const e = G.escena(escena.id);
      const g = capa();
      const codigo = 'WDJB-MJHT';
      const casillas = codigo
        .split('')
        .map((c) => (c === '-' ? '<span style="font-size:34px;color:#8c959f;margin:0 6px">–</span>' : `<span class="c" data-c="${c}" style="display:inline-grid;place-items:center;width:52px;height:64px;margin:0 4px;border-radius:8px;background:#fff;box-shadow:0 0 0 1px #d0d7de;font:700 30px 'JetBrains Mono',monospace;color:#1f2328"></span>`))
        .join('');
      const p1 = navegador(
        g,
        'github.com/login/device',
        `<div style="padding-top:70px;text-align:center">${gato}
          <div style="margin-top:22px;font-size:30px;font-weight:400;color:#1f2328">Device Activation</div>
          <div style="width:620px;margin:30px auto 0;padding:34px 30px;background:#fff;border-radius:12px;box-shadow:0 0 0 1px #d0d7de">
            <div style="font-size:20px;color:#1f2328;margin-bottom:22px">Enter the code displayed on your device</div>
            <div>${casillas}</div>
            <div class="continuar" style="${verde};height:52px;margin-top:30px;font-size:20px">Continue</div>
          </div></div>`,
      );
      const tPega = G.palabra('pegar', 'pega');
      const tAutoriza = G.palabra('pegar', 'autoriza');
      const letras = [...p1.pagina.querySelectorAll('.c')];
      tarea((t) => {
        const u = E.clamp((t - tPega) / 0.9, 0, 1);
        const n = Math.round(u * letras.length);
        letras.forEach((l, i) => {
          l.textContent = i < n ? l.dataset.c : '';
        });
      });
      const p2 = navegador(
        g,
        'github.com/login/device',
        `<div style="padding-top:60px;text-align:center">${gato}
          <div style="margin-top:22px;font-size:30px;color:#1f2328">Authorize <b>Didacta</b></div>
          <div style="width:620px;margin:30px auto 0;padding:34px 30px;background:#fff;border-radius:12px;box-shadow:0 0 0 1px #d0d7de;text-align:left">
            <div style="font-size:20px;color:#1f2328;line-height:1.5"><b>Didacta</b> by <b>franjfal</b> wants to act on your behalf.</div>
            <div style="margin-top:18px;font-size:17px;color:#59636e;line-height:1.5">It will only reach the repositories you choose. It cannot see your password.</div>
            <div class="autorizar" style="${verde};height:52px;margin-top:30px;font-size:20px">Authorize Didacta</div>
          </div></div>`,
      );
      const tFinPega = tPega + 1.1;
      anim(p1.raiz, [
        [e.ini, { o: 0, y: 40 }],
        [e.ini + 0.6, { o: 1, y: 0 }, 'sale4'],
        [tAutoriza - 0.5, { o: 1 }],
        [tAutoriza - 0.2, { o: 0 }],
      ]);
      anim(p2.raiz, [[0, { o: 0 }], [tAutoriza - 0.4, { o: 0 }], [tAutoriza - 0.1, { o: 1 }]]);
      const cur = E.cursor(null, { padre: g, desde: { x: W / 2 + 400, y: 900, lienzo: true } });
      cur.mostrar(tFinPega - 0.6, e.fin - 0.3);
      cur.ir(tFinPega - 0.5, tAutoriza - 0.7, centro(p1.pagina.querySelector('.continuar')));
      cur.clic(tAutoriza - 0.6);
      cur.ir(tAutoriza - 0.1, tAutoriza + 0.8, centro(p2.pagina.querySelector('.autorizar')));
      cur.clic(tAutoriza + 0.9);

      // La contraseña, aquí y en ningún otro sitio: la dirección.
      const tCon = G.palabra('contrasena', 'github.com');
      const barra = p2.raiz.querySelector('.direccion');
      E.resaltar(null, () => rect(barra), { t0: tCon - 0.2, t1: e.fin - 0.3, etiqueta: 'La contraseña, solo aquí', lado: 'abajo', pad: 4, padre: g });
      visible(g, e.ini, e.fin + 0.05);
    },

    // Elegir a qué repositorios llega.
    repos({ escena }) {
      const e = G.escena(escena.id);
      const g = capa();
      const radio = (on) => `<span style="display:inline-block;width:20px;height:20px;border-radius:50%;box-shadow:inset 0 0 0 ${on ? 6 : 2}px ${on ? '#0969da' : '#8c959f'};margin-right:14px;vertical-align:-3px"></span>`;
      const repo = (n) => `<span style="display:inline-flex;align-items:center;gap:8px;margin:8px 10px 0 0;padding:8px 14px;border-radius:20px;background:#ddf4ff;color:#0969da;font-size:17px;font-weight:600">▣ ${n}</span>`;
      const p = navegador(
        g,
        'github.com/apps/didacta/installations/new',
        `<div style="padding:50px 0 0 0;text-align:center">${gato}
          <div style="margin-top:18px;font-size:30px;color:#1f2328">Install <b>Didacta</b></div>
          <div style="width:720px;margin:26px auto 0;padding:30px 34px;background:#fff;border-radius:12px;box-shadow:0 0 0 1px #d0d7de;text-align:left">
            <div style="font-size:19px;color:#1f2328;margin-bottom:18px">for these repositories:</div>
            <div class="todos" style="font-size:19px;color:#59636e;padding:10px 0">${radio(false)}All repositories</div>
            <div class="solo" style="font-size:19px;color:#1f2328;padding:10px 0;font-weight:600">${radio(true)}Only select repositories
              <div style="margin:6px 0 0 34px;font-weight:400">${repo('didacta-ejemplo')}${repo('apuntes-calculo')}</div></div>
            <div style="${verde};height:52px;margin-top:26px;font-size:20px">Install</div>
          </div></div>`,
      );
      anim(p.raiz, [
        [e.ini, { o: 0, y: 40 }],
        [e.ini + 0.6, { o: 1, y: 0 }, 'sale4'],
      ]);
      const tSolo = G.palabra('elegir', 'solo los que');
      E.resaltar(null, () => rect(p.pagina.querySelector('.solo')), { t0: tSolo - 0.2, t1: e.fin - 0.3, etiqueta: 'Solo los que tú elijas', lado: 'derecha', pad: 8, padre: g });
      visible(g, e.ini, e.fin + 0.05);
    },
  });
};
