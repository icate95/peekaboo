# 👻 Companion

Un fantasmino che vive sulla tua scrivania e ti dice, a colpo d'occhio, quante
sessioni di [Claude Code](https://claude.com/claude-code) hai in esecuzione,
di cosa si stanno occupando e quali stanno aspettando te.

Nasce da un problema concreto: quando hai dieci terminali aperti, non sai più
quale sta lavorando, quale ha finito da mezz'ora e quale è fermo perché aspetta
un tuo "sì". Il fantasmino te lo dice senza che tu debba cercare.

Gira **tutto in locale**. Nessuna rete, nessun account, nessun dato che esce dal
tuo Mac: legge solo i file di stato che Claude Code scrive già in `~/.claude`.

---

## Cosa vedi

Una finestra senza bordi, sempre sopra le altre app, che puoi trascinare dove
vuoi. Dentro, le sessioni sono **raggruppate per progetto**, una bubble ciascuna:

```
╭─ COMPANION ──────────── ●2 ●1 ●14 ✕ ╮
╰─────────────────────────────────────╯
╭─ donne di montagna ───────────  2/8 ╮
│  ● zoho orders      esegue: sync…  4s │
│  ● fix prodotti     ha risposto    1h │
╰─────────────────────────────────────╯
╭─ huniverse-v2 ────────────────  1/8 ╮
│  ● ai next step     aspetta il tuo   │
│                     ok su Bash    2m │
╰─────────────────────────────────────╯
                 .-""""-.
                /  o  o  \
                |   \_/   |
                 \~^~^~^~/
```

Più un'icona **👻 nella barra in alto**, con lo stesso elenco in un menu a
tendina e il numero di sessioni che ti stanno aspettando.

### I quattro stati

| | Stato | Significato |
|---|---|---|
| 🟢 | **al lavoro** | sta elaborando o eseguendo un tool |
| 🟡 | **aspetta te** | ti ha chiesto un permesso o un input e si è fermata |
| 🔵 | **ha risposto** | ha finito e attende la tua prossima mossa |
| ⚪️ | **dorme** | ferma da più di 45 minuti |

Il fantasmino stesso cambia colore, espressione e velocità di fluttuazione in
base alla cosa più urgente in corso: fluttua piano quando tutto dorme, sfoggia
un punto esclamativo quando qualcuno ti aspetta.

### Troppe sessioni sullo stesso progetto

Oltre **3 sessioni sveglie** sullo stesso progetto, il box si accende di rosa e
il fantasmino si intristisce. Non è un errore: è un promemoria che oltre quella
soglia le sessioni tendono a pestarsi i piedi invece di aiutarti.

La soglia si cambia con `CROWD_LIMIT` in `server.py`.

### Click su una bubble

Cliccando una bubble, il terminale che ospita quella sessione viene portato in
primo piano, con la tab giusta già selezionata. Funziona con **Terminal.app** e
**iTerm2**.

Al primo click macOS chiede il permesso: *Impostazioni di sistema › Privacy e
sicurezza › Automazione*. Va concesso, altrimenti il click non ha effetto.

---

## Installazione

Servono solo cose che il Mac ha già: Python 3 e Swift (via Xcode Command Line
Tools, `xcode-select --install`).

```bash
git clone <url-del-repo> companion
cd companion
./run.sh
```

`run.sh` compila il guscio nativo la prima volta, avvia il server locale e apre
il fantasmino. Per chiuderlo: la ✕ sulla barra del fantasmino, oppure
*👻 › Esci* nella barra in alto.

### L'hook (consigliato)

Senza hook, "aspetta te" è una **stima**: se un tool è fermo da oltre due minuti,
il companion assume che ci sia un prompt di permesso a schermo. Funziona, ma
sbaglia sui comandi lunghi (build, test, deploy).

Claude Code però ha un hook `Notification` che scatta **esattamente** quando una
sessione ha bisogno di te. Collegandolo, il giallo diventa un segnale certo:

```bash
./install-hook.sh
```

Modifica `~/.claude/settings.json` aggiungendo una voce, dopo averne salvato una
copia in `settings.json.backup-companion`. Le sessioni già aperte prendono
l'hook al prossimo riavvio. Per tornare indietro:

```bash
./install-hook.sh --remove
```

Le bubble in stima si distinguono dalle certe: hanno il pallino vuoto invece che
pieno. Quando l'hook è installato, il companion smette del tutto di tirare a
indovinare.

---

## Come fa a saperlo

Claude Code tiene già tutto quello che serve in `~/.claude`, e il companion si
limita a leggerlo:

**`~/.claude/sessions/<pid>.json`** — una riga per sessione viva, con `pid`,
`sessionId`, `cwd`, lo `status` (`busy` / `idle`), il momento dell'ultimo
aggiornamento e il `name` che Claude si autogenera (*"fix prodotti"*,
*"ai next step"*). Quel nome diventa il titolo della bubble.

**`~/.claude/projects/<progetto>/<sessionId>.jsonl`** — il transcript completo.
Il companion ne legge solo la coda (~180 KB) e ricava cosa sta succedendo ora:
se c'è un `tool_use` senza il `tool_result` corrispondente, la sessione sta
usando quel tool, e la riga diventa *"esegue: …"*, *"scrive config.ts"*,
*"cerca «pattern»"*. Altrimenti mostra l'ultima frase dell'assistente.

**`~/.claude/companion-waiting/<sessionId>.flag`** — scritto dall'hook. La
presenza del file accende il giallo; il server lo cancella da solo appena la
sessione riprende a lavorare.

Le sessioni il cui processo non esiste più vengono ignorate, così i file di stato
rimasti indietro non sporcano l'elenco.

---

## Architettura

Due pezzi, volutamente separati:

| File | Ruolo |
|---|---|
| `server.py` | Legge `~/.claude`, deduce gli stati, espone `/api/sessions` e `/api/focus` su `127.0.0.1`. Nessuna dipendenza fuori dalla libreria standard. |
| `Ghost.swift` | Guscio nativo: `NSWindow` senza bordi e trasparente, sempre in primo piano, più l'icona nella barra. Dentro, una `WKWebView`. |
| `ui/index.html` | Tutta la grafica: fantasmino in SVG animato con CSS, bubble, gruppi. Nessun asset esterno, nessuna libreria. |
| `hooks/companion-notify.sh` | L'hook `Notification`: tocca un file quando una sessione ti chiama. |

La divisione serve a una cosa pratica: **la grafica si modifica senza
ricompilare**. Cambia `ui/index.html`, chiudi e riapri la finestra, fatto. Swift
si ricompila solo se tocchi `Ghost.swift`, e `run.sh` se ne accorge da solo.

Il server sta in ascolto **solo su `127.0.0.1`**, e `/api/focus` accetta soltanto
pid che corrispondono a una sessione Claude viva — non è un canale per eseguire
comandi arbitrari.

### Perché non è un widget macOS

I widget WidgetKit si ridisegnano a snapshot, su una timeline decisa dal sistema,
di solito ogni parecchi minuti: niente animazione, niente aggiornamento continuo.
In più girano in sandbox, quindi leggere `~/.claude` richiede entitlement e app
group, e serve un progetto Xcode firmato. Una finestra flottante dà molto di più
con molta meno impalcatura.

---

## Personalizzazione

| Cosa | Dove |
|---|---|
| Colori degli stati | `ui/index.html`, blocco `:root` |
| Forma, occhi, bocca del fantasmino | `ui/index.html`, l'`<svg>` e la mappa `MOUTH` |
| Frasi che dice | `ui/index.html`, funzione `render()` |
| Soglia "troppe sessioni" | `server.py`, `CROWD_LIMIT` |
| Quando una sessione "dorme" | `server.py`, `SLEEP_AFTER_S` |
| Dimensione e posizione iniziale | `Ghost.swift`, `buildWindow()` |
| Porta del server | variabile `COMPANION_PORT` (default 8787) |

---

## Limiti noti

- **Solo macOS.** Il guscio è AppKit e il "porta in primo piano" è AppleScript.
  Il server, però, è portabile: la UI funziona in qualsiasi browser su
  `http://127.0.0.1:8787`.
- **Il click sul terminale copre Terminal.app e iTerm2.** Ghostty, WezTerm,
  Alacritty e simili non espongono il tty via AppleScript, quindi lì la bubble
  resta cliccabile ma non porta da nessuna parte.
- Le sessioni **non interattive** (`claude -p`, task in background) compaiono
  nell'elenco ma non hanno un terminale da aprire.

---

## Licenza

MIT — vedi [LICENSE](LICENSE).
