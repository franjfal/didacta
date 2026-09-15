/// Lo que la barra sabe escribir: paletas de matemáticas y de símbolos.
///
/// La barra tenía los entornos de Didacta y nada más, y escribir una fórmula
/// seguía siendo teclear `\frac{}{}` sin equivocarse de llave. Esto es la otra
/// mitad: lo que se pulsa en lugar de escribirse.
///
/// Cada cosa se escribe **alrededor de lo que esté marcado**: con un trozo
/// seleccionado, `\sqrt{}` lo mete dentro de la raíz; sin nada marcado, deja
/// el cursor donde va el contenido. Es la misma regla que los envoltorios de
/// entorno, y es lo que hace que la barra sirva mientras se escribe y no solo
/// al empezar.
///
/// Los símbolos llevan su glifo como rótulo --se busca «≤», no «\leq»-- y
/// escriben la orden de LaTeX, que es lo que va al fichero. Ninguno de los dos
/// es el otro: el fichero no lleva Unicode y la paleta no lleva órdenes.
library;

/// Algo que la barra escribe.
class TexSnippet {
  const TexSnippet(this.label, this.before, {this.after = '', this.tooltip});

  /// Lo que se ve en la paleta: el glifo, o un nombre corto.
  final String label;

  /// Lo que se escribe delante de lo marcado.
  final String before;

  /// Y lo que se escribe detrás. Vacío en un símbolo suelto.
  final String after;

  /// Qué es, para quien no reconozca el glifo.
  final String? tooltip;

  bool get wraps => after.isNotEmpty;
}

/// Un grupo de la paleta.
class TexPalette {
  const TexPalette(this.name, this.items);

  final String name;
  final List<TexSnippet> items;
}

/// Las estructuras: lo que tiene huecos que rellenar.
const TexPalette texMathPalette = TexPalette('Matemáticas', [
  TexSnippet(r'$x$', r'$', after: r'$', tooltip: 'Fórmula en la línea'),
  TexSnippet(r'\[x\]', '\\[\n', after: '\n\\]', tooltip: 'Fórmula aparte'),
  TexSnippet('a/b', r'\frac{', after: '}{}', tooltip: 'Fracción'),
  TexSnippet('√', r'\sqrt{', after: '}', tooltip: 'Raíz'),
  TexSnippet('xⁿ', '^{', after: '}', tooltip: 'Exponente'),
  TexSnippet('xₙ', '_{', after: '}', tooltip: 'Subíndice'),
  TexSnippet('∑', r'\sum_{', after: '}^{}', tooltip: 'Sumatorio'),
  TexSnippet('∏', r'\prod_{', after: '}^{}', tooltip: 'Producto'),
  TexSnippet('∫', r'\int_{', after: '}^{}', tooltip: 'Integral'),
  TexSnippet('lím', r'\lim_{', after: '}', tooltip: 'Límite'),
  TexSnippet('‖x‖', r'\|', after: r'\|', tooltip: 'Norma'),
  TexSnippet('|x|', '|', after: '|', tooltip: 'Valor absoluto'),
  TexSnippet(
    'matriz',
    '\\begin{pmatrix}\n',
    after: '\n\\end{pmatrix}',
    tooltip: 'Matriz entre paréntesis',
  ),
  TexSnippet(
    'casos',
    '\\begin{cases}\n',
    after: '\n\\end{cases}',
    tooltip: 'Definición por casos',
  ),
]);

/// Los símbolos, por familias. El rótulo es el glifo; lo que se escribe es la
/// orden.
const List<TexPalette> texSymbolPalettes = [
  TexPalette('Griegas', [
    TexSnippet('α', r'\alpha '),
    TexSnippet('β', r'\beta '),
    TexSnippet('γ', r'\gamma '),
    TexSnippet('δ', r'\delta '),
    TexSnippet('ε', r'\varepsilon '),
    TexSnippet('θ', r'\theta '),
    TexSnippet('λ', r'\lambda '),
    TexSnippet('μ', r'\mu '),
    TexSnippet('π', r'\pi '),
    TexSnippet('ρ', r'\rho '),
    TexSnippet('σ', r'\sigma '),
    TexSnippet('φ', r'\varphi '),
    TexSnippet('ω', r'\omega '),
    TexSnippet('Γ', r'\Gamma '),
    TexSnippet('Δ', r'\Delta '),
    TexSnippet('Θ', r'\Theta '),
    TexSnippet('Λ', r'\Lambda '),
    TexSnippet('Π', r'\Pi '),
    TexSnippet('Σ', r'\Sigma '),
    TexSnippet('Φ', r'\Phi '),
    TexSnippet('Ω', r'\Omega '),
  ]),
  TexPalette('Relaciones', [
    TexSnippet('≤', r'\leq '),
    TexSnippet('≥', r'\geq '),
    TexSnippet('≠', r'\neq '),
    TexSnippet('≈', r'\approx '),
    TexSnippet('≡', r'\equiv '),
    TexSnippet('∼', r'\sim '),
    TexSnippet('≅', r'\cong '),
    TexSnippet('∝', r'\propto '),
    TexSnippet('≪', r'\ll '),
    TexSnippet('≫', r'\gg '),
  ]),
  TexPalette('Conjuntos', [
    TexSnippet('∈', r'\in '),
    TexSnippet('∉', r'\notin '),
    TexSnippet('⊂', r'\subset '),
    TexSnippet('⊆', r'\subseteq '),
    TexSnippet('∪', r'\cup '),
    TexSnippet('∩', r'\cap '),
    TexSnippet('∖', r'\setminus '),
    TexSnippet('∅', r'\emptyset '),
    TexSnippet('ℝ', r'\mathbb{R}'),
    TexSnippet('ℕ', r'\mathbb{N}'),
    TexSnippet('ℤ', r'\mathbb{Z}'),
    TexSnippet('ℚ', r'\mathbb{Q}'),
    TexSnippet('ℂ', r'\mathbb{C}'),
  ]),
  TexPalette('Lógica y flechas', [
    TexSnippet('→', r'\to '),
    TexSnippet('⇒', r'\Rightarrow '),
    TexSnippet('⇔', r'\Leftrightarrow '),
    TexSnippet('↦', r'\mapsto '),
    TexSnippet('∀', r'\forall '),
    TexSnippet('∃', r'\exists '),
    TexSnippet('¬', r'\neg '),
    TexSnippet('∧', r'\wedge '),
    TexSnippet('∨', r'\vee '),
    TexSnippet('∴', r'\therefore '),
  ]),
  TexPalette('Operadores', [
    TexSnippet('·', r'\cdot '),
    TexSnippet('×', r'\times '),
    TexSnippet('±', r'\pm '),
    TexSnippet('∓', r'\mp '),
    TexSnippet('∞', r'\infty '),
    TexSnippet('∂', r'\partial '),
    TexSnippet('∇', r'\nabla '),
    TexSnippet('…', r'\dots '),
    TexSnippet('∘', r'\circ '),
    TexSnippet('⊕', r'\oplus '),
  ]),
];
