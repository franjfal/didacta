/* B2 · Una lección, muchas versiones: el gráfico que el guion no trae.
 *
 * Una diapositiva con pausas frente a la misma sin ellas. El resto sale del
 * guion (`estudio/recorrido.js`).
 */
window.montaje = function (E, G, D) {
  const { W, H, nodo, anim } = E;
  const capa = () => nodo({ clase: 'capa', estilo: { width: `${W}px`, height: `${H}px`, zIndex: 10 } });
  const visible = (n, ini, fin) =>
    anim(n, [
      [ini, { o: 0 }],
      [ini + 0.4, { o: 1 }, 'sale'],
      [fin - 0.4, { o: 1 }],
      [fin, { o: 0 }, 'suave'],
    ]);
  const entra = (n, t, dy = 26) =>
    anim(n, [
      [t, { o: 0, y: dy, blur: 6 }],
      [t + 0.55, { o: 1, y: 0, blur: 0 }, 'sale4'],
    ]);

  Recorrido.montar(E, G, D, {
    pausas({ escena }) {
      const e = G.escena(escena.id);
      const g = capa();
      const puntos = ['Se acerca a L.', 'Tanto como se quiera.', 'Cuando x se acerca a a.'];
      const diapositiva = (x, titulo, color) => {
        const raiz = nodo({
          padre: g,
          clase: 'abs',
          html: `<div style="width:760px;height:470px;border-radius:12px;overflow:hidden;background:#fff;box-shadow:0 0 0 1px rgba(28,31,38,.08),0 24px 60px -18px rgba(28,31,38,.35)">
            <div style="height:64px;background:#346e34;color:#fff;font-size:28px;font-weight:600;display:flex;align-items:center;padding-left:32px">Límite de una función</div>
            <div class="items" style="padding:44px 50px"></div></div>`,
          estilo: { left: `${x}px`, top: '330px' },
        });
        const rot = nodo({ padre: g, clase: 'rotulo-hoja', html: `<span style="display:inline-block;width:14px;height:14px;border-radius:50%;background:${color};margin-right:12px;vertical-align:2px"></span>${titulo}`, estilo: { left: `${x}px`, top: '266px' } });
        const items = puntos.map((p) =>
          nodo({ padre: raiz.querySelector('.items'), html: `<div style="font-size:30px;line-height:1.4;margin-bottom:18px;display:flex;gap:16px"><span style="color:#346e34">▸</span>${p}</div>` }),
        );
        return { raiz, rot, items };
      };
      const tPartes = G.palabra('por-partes', 'por partes');
      const tEntera = G.palabra('entera', 'entera');
      const a = diapositiva(W / 2 - 800, 'Diapositivas', '#2d5fa0');
      const b = diapositiva(W / 2 + 40, 'Sin pausas', '#3c876e');
      entra(a.raiz, e.ini + 0.3, 40);
      entra(a.rot, e.ini + 0.4, 14);
      // Por partes: cada punto en su momento, y el contador de páginas.
      a.items.forEach((it, i) => anim(it, [[0, { o: i === 0 ? 1 : 0 }], [tPartes + 0.6 * i, { o: i === 0 ? 1 : 0 }], [tPartes + 0.6 * i + 0.3, { o: 1 }]]));
      const paginas = nodo({ padre: g, clase: 'abs', html: '', estilo: { left: `${W / 2 - 800}px`, top: '818px', fontSize: '24px', fontWeight: 600, color: 'var(--apagado)' } });
      E.tarea((t) => {
        const n = t < tPartes ? 1 : Math.min(3, 1 + Math.floor((t - tPartes) / 0.6 + 0.5));
        paginas.textContent = `${n} de 3 · una página por paso`;
      });
      entra(paginas, tPartes - 0.2, 10);
      entra(b.raiz, tEntera - 0.8, 40);
      entra(b.rot, tEntera - 0.7, 14);
      const unaPagina = nodo({ padre: g, clase: 'abs', html: 'Una sola página, entera', estilo: { left: `${W / 2 + 40}px`, top: '818px', fontSize: '24px', fontWeight: 600, color: 'var(--apagado)' } });
      entra(unaPagina, tEntera - 0.2, 10);
      visible(g, e.ini, e.fin + 0.05);
    },
  });
};
