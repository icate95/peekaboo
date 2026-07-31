// Guardaroba di Peekaboo — le sagome e i vestiti del fantasmino.
//
// L'idea: non cambia solo faccia, cambia *taglio*. Ogni stato d'animo ha una
// silhouette diversa. Disegni originali, nello spirito minimale dei poster
// "ghost fashion" ma senza ricalcarne nessuno.
//
// Usato sia dal fantasmino vero (index.html) sia dalla galleria di anteprima
// (gallery.html): un file solo, cosi' l'anteprima non mente mai.

(function (root) {
  "use strict";

  /** Cupola + orlo ondulato: la base da cui derivano quasi tutte le sagome. */
  function ghostBody({top = 48, halfW = 28, hem = 64, waves = 4, dip = 12} = {}) {
    const L = 42 - halfW, R = 42 + halfW, step = (R - L) / waves;
    let d = `M${L} ${top} A${halfW} ${halfW} 0 0 1 ${R} ${top} L${R} ${hem}`;
    for (let i = 0; i < waves; i++)
      d += ` q${(-step / 2).toFixed(1)} ${dip} ${(-step).toFixed(1)} 0`;
    return d + " Z";
  }

  /** Contorno a nuvoletta: tanti archi attorno a un centro. */
  function scallop(cx, cy, r, bumps) {
    let d = "";
    for (let i = 0; i <= bumps; i++) {
      const a = (i / bumps) * Math.PI * 2 - Math.PI / 2;
      const x = (cx + Math.cos(a) * r).toFixed(1);
      const y = (cy + Math.sin(a) * r).toFixed(1);
      d += i === 0 ? `M${x} ${y}`
                   : ` A${(r * .44).toFixed(1)} ${(r * .44).toFixed(1)} 0 0 1 ${x} ${y}`;
    }
    return d + " Z";
  }

  const WARDROBE = {
    regular:   {label: "normale", when: "tutti i giorni",
                d: ghostBody()},

    slim:      {label: "affusolata", when: "sta lavorando",
                d: ghostBody({halfW: 21, top: 46, hem: 66, waves: 4, dip: 10})},

    relaxed:   {label: "rilassata", when: "ha risposto",
                d: ghostBody({halfW: 31, top: 50, hem: 62, waves: 3, dip: 14})},

    puffy:     {label: "gonfia", when: "si sta annoiando",
                d: scallop(42, 48, 27, 11)},

    rara:      {label: "a balze", when: "annoiata da un pezzo",
                d: ghostBody({halfW: 27, top: 48, hem: 60, waves: 5, dip: 10}),
                deco: `<path d="M17 56 q6 5 12 0 q6 5 12 0 q6 5 12 0 q6 5 12 0"/>
                       <path d="M17 64 q6 5 12 0 q6 5 12 0 q6 5 12 0 q6 5 12 0"/>`},

    maxi:      {label: "lunga", when: "la finestra è alta",
                d: ghostBody({halfW: 20, top: 40, hem: 74, waves: 3, dip: 8})},

    reverse:   {label: "al contrario", when: "non disturbare",
                d: ghostBody(), cls: "reverse"},

    invisible: {label: "invisibile", when: "non disturbare, discreta",
                d: ghostBody(), cls: "invisible"},

    trench:    {label: "tre in un cappotto", when: "troppe sessioni sul progetto",
                d: "M20 34 A22 22 0 0 1 64 34 L64 72 q-11 8 -22 0 q-11 8 -22 0 Z",
                deco: `<path d="M42 22 v50" stroke-dasharray="3 3"/>
                       <path d="M26 40 h32"/>
                       <circle cx="31" cy="52" r="2.4" fill="currentColor" stroke="none"/>
                       <circle cx="53" cy="52" r="2.4" fill="currentColor" stroke="none"/>
                       <circle cx="31" cy="64" r="2.4" fill="currentColor" stroke="none"/>
                       <circle cx="53" cy="64" r="2.4" fill="currentColor" stroke="none"/>`},
  };

  /** Quale taglio indossare, viste le circostanze. */
  function pickShape(d, opts) {
    opts = opts || {};
    if (d && d.dnd) return opts.dndLook === "invisible" ? "invisible" : "reverse";
    if (!d) return "regular";
    if (d.mood === "crowded") return "trench";
    // se la finestra è molto alta, si allunga per riempirla
    if ((opts.height || 0) > 760 && d.mood !== "sleeping") return "maxi";

    switch (d.mood) {
      case "working":  return "slim";
      case "replied":  return "relaxed";
      case "waiting":  return "regular";
      case "sleeping": return (d.forgotten || 0) > 4 ? "rara" : "puffy";
      default:         return "regular";
    }
  }

  // ---------------------------------------------------------------- vestiti
  // Accessori nello stesso tratto: linea scura, campiture piatte, niente
  // sfumature. Si appoggiano sopra alla sagoma.

  /** Corona di fiori: generata, sarebbe illeggibile scritta a mano. */
  function flowerCrown() {
    const petals = ["#ffb3c8", "#ffd75e", "#b8e3ff", "#d9b8ff", "#a8e6c0"];
    let out = "";
    for (let i = 0; i < 5; i++) {
      const x = 25 + i * 8.5, y = 27 - Math.abs(i - 2) * 1.6, c = petals[i];
      for (let p = 0; p < 5; p++) {
        const a = (p / 5) * Math.PI * 2;
        out += `<circle cx="${(x + Math.cos(a) * 2.9).toFixed(1)}"
                        cy="${(y + Math.sin(a) * 2.9).toFixed(1)}" r="2.1"
                        fill="${c}" stroke="var(--outline)" stroke-width="1.1"/>`;
      }
      out += `<circle cx="${x}" cy="${y}" r="1.5" fill="#fff3c4"
                      stroke="var(--outline)" stroke-width="1"/>`;
    }
    return out;
  }

  const SKINS = {
    santa: {label: "Babbo Natale", when: "dicembre", svg: `
      <path d="M27 28 C28 12 40 6 52 9 C58 10.5 59.5 15 55.5 18 L46 28 Z"
            fill="#e0384a" stroke="var(--outline)" stroke-width="2" stroke-linejoin="round"/>
      <rect x="22" y="25" width="40" height="8" rx="4"
            fill="#fdfdfd" stroke="var(--outline)" stroke-width="2"/>
      <circle cx="56" cy="15" r="5" fill="#fdfdfd" stroke="var(--outline)" stroke-width="2"/>`},

    winter: {label: "berretto", when: "gennaio → inizio febbraio", svg: `
      <path d="M24 30 Q24 12 42 12 Q60 12 60 30 Z"
            fill="#6fb7e8" stroke="var(--outline)" stroke-width="2" stroke-linejoin="round"/>
      <circle cx="35" cy="20" r="1.7" fill="#fdfdfd"/>
      <circle cx="47" cy="18" r="1.7" fill="#fdfdfd"/>
      <circle cx="41" cy="25" r="1.7" fill="#fdfdfd"/>
      <rect x="21" y="27" width="42" height="7" rx="3.5"
            fill="#fdfdfd" stroke="var(--outline)" stroke-width="2"/>
      <circle cx="42" cy="9" r="4.6" fill="#fdfdfd" stroke="var(--outline)" stroke-width="2"/>`},

    hearts: {label: "cuoricini", when: "san Valentino", svg: `
      <g class="floaty">
        <path d="M62 16 c0-2.4 3-3.2 4.2-1.2 1.2-2 4.2-1.2 4.2 1.2 0 2.6-4.2 5.4-4.2 5.4S62 18.6 62 16z"
              fill="#ff8fb0" stroke="var(--outline)" stroke-width="1.4"/>
      </g>
      <g class="floaty" style="animation-delay:1.1s">
        <path d="M15 24 c0-1.8 2.3-2.4 3.2-.9 .9-1.5 3.2-.9 3.2.9 0 2-3.2 4.1-3.2 4.1S15 26 15 24z"
              fill="#ffb3c8" stroke="var(--outline)" stroke-width="1.2"/>
      </g>`},

    bunny: {label: "orecchie", when: "Pasqua", svg: `
      <ellipse cx="33" cy="12" rx="4.4" ry="11" transform="rotate(-12 33 12)"
               fill="var(--ghost)" stroke="var(--outline)" stroke-width="2"/>
      <ellipse cx="51" cy="12" rx="4.4" ry="11" transform="rotate(12 51 12)"
               fill="var(--ghost)" stroke="var(--outline)" stroke-width="2"/>
      <ellipse cx="33" cy="13" rx="1.9" ry="6.5" transform="rotate(-12 33 13)" fill="#ffb3c8"/>
      <ellipse cx="51" cy="13" rx="1.9" ry="6.5" transform="rotate(12 51 13)" fill="#ffb3c8"/>`},

    flowers: {label: "corona di fiori", when: "aprile → maggio", svg: `<g id="crown"></g>`},

    sunglasses: {label: "occhiali da sole", when: "giugno → agosto", svg: `
      <rect x="22.5" y="38" width="18" height="11.5" rx="4.5"
            fill="#1c2027" stroke="var(--outline)" stroke-width="1.6"/>
      <rect x="43.5" y="38" width="18" height="11.5" rx="4.5"
            fill="#1c2027" stroke="var(--outline)" stroke-width="1.6"/>
      <path d="M40.5 42 h3" stroke="var(--outline)" stroke-width="2.2" stroke-linecap="round"/>
      <path d="M26 41 l6 3" stroke="#ffffff" stroke-width="1.6" opacity=".5" stroke-linecap="round"/>
      <g class="twinkle">
        <path d="M66 20 l1.6 4 4 1.6 -4 1.6 -1.6 4 -1.6 -4 -4 -1.6 4 -1.6 z" fill="#ffd75e"/>
      </g>`},

    witch: {label: "cappello da strega", when: "Halloween", svg: `
      <path d="M44 2 L57 26 L31 26 Z" fill="#2c2742"
            stroke="var(--outline)" stroke-width="2" stroke-linejoin="round"/>
      <path d="M35 18 h16 l1.5 5 h-19 z" fill="#7d5cc6"/>
      <ellipse cx="42" cy="27" rx="23" ry="5.5" fill="#2c2742"
               stroke="var(--outline)" stroke-width="2"/>`},
  };

  /** Calendario dei vestiti: mese e giorno decidono l'abito. */
  function skinForDate(d) {
    const m = d.getMonth() + 1, day = d.getDate();
    if (m === 12) return "santa";
    if (m === 1 || (m === 2 && day < 10)) return "winter";
    if (m === 2 && day >= 10 && day <= 18) return "hearts";
    if (m === 3 && day >= 25) return "bunny";
    if (m === 4 && day <= 10) return "bunny";
    if (m === 4 || m === 5) return "flowers";
    if (m >= 6 && m <= 8) return "sunglasses";
    if ((m === 10 && day >= 21) || (m === 11 && day <= 2)) return "witch";
    return "";
  }

  root.Wardrobe = {ghostBody, scallop, WARDROBE, pickShape,
                   SKINS, skinForDate, flowerCrown};
})(window);
