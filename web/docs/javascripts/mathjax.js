// MathJax, configurado para lo poco que hace falta aquí.
//
// Esta web explica una herramienta de LaTeX, así que alguna fórmula se
// escribe; lo que no hace es componer documentos. La configuración es la
// mínima que Material recomienda, más el enganche de navegación instantánea:
// sin él, al cambiar de página las fórmulas se quedan sin componer, porque
// Material no recarga el documento.
window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"], ["$", "$"]],
    displayMath: [["\\[", "\\]"], ["$$", "$$"]],
    processEscapes: true,
    processEnvironments: true,
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex",
  },
};

document$.subscribe(() => {
  MathJax.startup.output.clearCache();
  MathJax.typesetClear();
  MathJax.texReset();
  MathJax.typesetPromise();
});
