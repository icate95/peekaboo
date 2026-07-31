# 👻 Peekaboo

Un fantasmino che vive sulla tua scrivania e ti dice, a colpo d'occhio, quante
sessioni di [Claude Code](https://claude.com/claude-code) hai in esecuzione,
di cosa si stanno occupando e quali stanno aspettando te.

Nasce da un problema concreto: quando hai dieci terminali aperti, non sai più
quale sta lavorando, quale ha finito da mezz'ora e quale è fermo perché aspetta
un tuo "sì". Peekaboo te lo dice senza che tu debba cercare.

Gira **tutto in locale**. Nessuna rete, nessun account, nessun dato che esce dal
tuo Mac: legge solo i file di stato che Claude Code scrive già in `~/.claude`.

---

## Cosa vedi

Una colonna senza bordi, sempre sopra le altre app, che di default occupa tutta
l'altezza dello schermo. Dentro, le sessioni sono **raggruppate per progetto**,
una bubble ciascuna, ognuna con il suo fantasmino piccolo del colore del proprio
stato:

```
╭─ PEEKABOO ───────────── ●2 ●1 ●14  ☾ ⚙ ⇕ ✕ ╮
╰────────────────────────────────────────────╯
╭─ donne di montagna ────────────────── 2/8 ╮
│  👻 zoho orders       esegue: sync…    4s │
│  👻 fix prodotti      ha risposto      1h │
╰────────────────────────────────────────────╯
╭─ huniverse-v2 ─────────────────────── 1/8 ╮
│  👻 ai next step      aspetta il tuo ok 2m│
╰────────────────────────────────────────────╯
        👻   👻  👻   👻  👻      ← lo sciame
              .-""""-.
             / ●    ● \
             |   \__/  |
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

Il fantasmino grande riflette la cosa più urgente in corso: cambia colore,
espressione e velocità di fluttuazione, sfoggia un punto esclamativo quando
qualcuno ti aspetta e si addormenta quando tutto tace.

### Lo sciame

Attorno al fantasmino grande fluttuano i fantasmini piccoli, **uno per
sessione**, colorati per stato — e quelli che dormono dormono davvero, con gli
occhi chiusi. Si disattiva dalle impostazioni.

### Troppe sessioni sullo stesso progetto

Oltre **3 sessioni sveglie** sullo stesso progetto, il box si accende di rosa e
il fantasmino si intristisce. Non è un errore: è un promemoria che oltre quella
soglia le sessioni tendono a pestarsi i piedi invece di aiutarti. La soglia si
cambia dalle impostazioni.

### Sessioni dimenticate

Le sessioni ferme da più di 24 ore vengono marcate: passandoci sopra compare una
✕ che le chiude (con conferma al secondo click). Claude riceve un SIGTERM, quindi
esce in modo pulito e il transcript resta — la sessione si può sempre riprendere
con `claude --resume`.

### Click su una bubble

Cliccando una bubble, il terminale che ospita quella sessione viene portato in
primo piano, con la tab giusta già selezionata. Funziona con **Terminal.app** e
**iTerm2**.

Al primo click macOS chiede il permesso: *Impostazioni di sistema › Privacy e
sicurezza › Automazione*. Va concesso, altrimenti il click non ha effetto.

---

## Dove sta e come si comporta

**Su quale schermo.** Se ne hai più di uno, lo scegli dalle impostazioni: il menu
elenca gli schermi con nome e risoluzione. Peekaboo sta su **uno solo**.

**Disposizione.** Quattro preset, tutti su una colonna laterale (destra o
sinistra, a scelta): colonna intera, metà alta, metà bassa, oppure *libera* —
e in quel caso la trascini dove vuoi. Se la sposti a mano, passa automaticamente
a "libera": non ti riporta dove dice lei.

**Si smaterializza mentre lavori.** Quando l'app attiva è un'altra — cioè quando
stai scrivendo da qualche altra parte — il fantasmino sbiadisce e ti lascia
vedere quello che c'è sotto. Appena il mouse si avvicina, torna pieno.

> Rilevare i *tasti* premuti richiederebbe il permesso Accessibilità, lo stesso
> che serve a un keylogger. L'app attiva è un segnale equivalente e gratuito.

**Non è un box.** La finestra resta un rettangolo — macOS non ne ha di altra
forma — ma i click **passano attraverso** ovunque non ci sia niente disegnato:
puoi cliccare le finestre sotto attraverso lo spazio vuoto attorno al fantasmino.
La UI comunica al guscio nativo i rettangoli "solidi", che fa da filtro.

**Gli occhi seguono il mouse**, ovunque sia sullo schermo.

**Microfono e telecamera.** Se accendi il microfono, il fantasmino tira fuori un
microfono e canticchia; se accendi la telecamera, finisce sotto i riflettori su
un tappeto rosso. Il rilevamento non chiede nessun permesso: chiede al sistema se
il dispositivo sta girando, senza mai aprire un flusso.

**Click sul fantasmino.** Se c'è una sessione che ti aspetta, ti porta lì. Se non
c'è, fa una capriola.

---

## Vestiti e temi

Peekaboo si cambia d'abito da solo secondo il calendario:

| Periodo | Vestito |
|---|---|
| dicembre | cappello di Babbo Natale |
| gennaio → 9 febbraio | berretto invernale |
| 10 → 18 febbraio | cuoricini |
| fine marzo → inizio aprile | orecchie da coniglio |
| aprile → maggio | corona di fiori |
| giugno → agosto | occhiali da sole |
| 21 ottobre → 2 novembre | cappello da strega |

Dalle impostazioni si può bloccare un vestito fisso o toglierlo del tutto.

Ci sono anche tre **temi**: `morbido` (lo stile kawaii predefinito), `pixel`
(spigoli vivi e occhi quadrati) e `minimale` (solo la sagoma, niente faccia).

---

## Installazione

Servono solo cose che il Mac ha già: Python 3 e Swift (via Xcode Command Line
Tools, `xcode-select --install`).

```bash
git clone <url-del-repo> peekaboo
cd peekaboo
./run.sh
```

`run.sh` costruisce `Peekaboo.app` la prima volta, avvia il server locale e apre
il fantasmino. Per chiuderlo: la ✕ sulla barra, oppure *👻 › Esci* nella barra in
alto.

### Comandi

| | |
|---|---|
| `./run.sh` | avvia tutto |
| `./build.sh` | ricostruisce solo `Peekaboo.app` |
| `./install-hook.sh` | collega l'hook (vedi sotto) |
| `./install-hook.sh --remove` | scollega l'hook |
| `⌥⌘G` | mostra o nasconde il fantasmino, da qualsiasi app |

### L'hook (consigliato)

Senza hook, "aspetta te" è una **stima**: se un tool è fermo da oltre due minuti,
Peekaboo assume che ci sia un prompt di permesso a schermo. Funziona, ma sbaglia
sui comandi lunghi (build, test, deploy).

Claude Code però ha un hook `Notification` che scatta **esattamente** quando una
sessione ha bisogno di te. Collegandolo, il giallo diventa un segnale certo:

```bash
./install-hook.sh
```

Modifica `~/.claude/settings.json` aggiungendo una voce, dopo averne salvato una
copia in `settings.json.backup-peekaboo`. Le sessioni già aperte prendono l'hook
al prossimo riavvio.

Le bubble in stima si distinguono dalle certe (te lo dice il tooltip). Quando
l'hook è installato, Peekaboo smette del tutto di tirare a indovinare.

---

## Impostazioni

Il pannello si apre con la ⚙. Tutto viene salvato in
`~/Library/Application Support/Peekaboo/settings.json`.

| Voce | Cosa fa |
|---|---|
| Schermo | su quale monitor vive, se ne hai più di uno |
| Disposizione | colonna intera, metà alta, metà bassa, libera |
| Lato e larghezza | destra o sinistra, e quanto è larga |
| Si smaterializza | sbiadisce mentre lavori in un'altra app |
| Click attraverso | i click passano dove non c'è niente disegnato |
| Occhi seguono il mouse | accende o spegne lo sguardo |
| Tema | morbido, pixel, minimale |
| Vestito | automatico (stagionale), nessuno, o uno fisso |
| Fantasmini attorno | accende o spegne lo sciame |
| Reazioni e commenti | il fantasmino salta se lo clicchi e commenta la giornata |
| Notifiche | una per tipo: aspetta te, ha risposto, dimenticate, suono |
| Soglie | quante sessioni sono troppe, dopo quanto dorme, dopo quanto è dimenticata |
| Avvio all'accensione | installa un LaunchAgent che lo lancia al login |
| Sempre in primo piano | se toglierlo, si comporta come una finestra normale |

La ☾ nella barra attiva il **Non disturbare** per un'ora: niente notifiche,
niente commenti. Si spegne da sola.

---

## Come fa a saperlo

Claude Code tiene già tutto quello che serve in `~/.claude`, e Peekaboo si limita
a leggerlo:

**`~/.claude/sessions/<pid>.json`** — una riga per sessione viva, con `pid`,
`sessionId`, `cwd`, lo `status` (`busy` / `idle`), il momento dell'ultimo
aggiornamento e il `name` che Claude si autogenera (*"fix prodotti"*,
*"ai next step"*). Quel nome diventa il titolo della bubble.

**`~/.claude/projects/<progetto>/<sessionId>.jsonl`** — il transcript completo.
Peekaboo ne legge solo la coda (~180 KB) e ricava cosa sta succedendo ora: se c'è
un `tool_use` senza il `tool_result` corrispondente, la sessione sta usando quel
tool, e la riga diventa *"esegue: …"*, *"scrive config.ts"*, *"cerca «pattern»"*.
Altrimenti mostra l'ultima frase dell'assistente.

**`~/.claude/peekaboo-waiting/<sessionId>.flag`** — scritto dall'hook. La presenza
del file accende il giallo; il server lo cancella da solo appena la sessione
riprende a lavorare.

Le sessioni il cui processo non esiste più vengono ignorate, così i file di stato
rimasti indietro non sporcano l'elenco.

---

## Architettura

| File | Ruolo |
|---|---|
| `server.py` | Legge `~/.claude`, deduce gli stati, tiene le impostazioni, espone le API su `127.0.0.1`. Nessuna dipendenza fuori dalla libreria standard. |
| `Peekaboo.swift` | Guscio nativo: finestra senza bordi e trasparente, icona nella barra, notifiche di sistema, scorciatoia globale. Dentro, una `WKWebView`. |
| `ui/index.html` | Tutta la grafica: fantasmino in SVG animato con CSS, sciame, bubble, vestiti, pannello impostazioni. Nessun asset esterno, nessuna libreria. |
| `build.sh` | Costruisce `Peekaboo.app` con Info.plist e firma ad-hoc. |
| `hooks/peekaboo-notify.sh` | L'hook `Notification`: tocca un file quando una sessione ti chiama. |

La divisione serve a una cosa pratica: **la grafica si modifica senza
ricompilare**. Cambia `ui/index.html`, chiudi e riapri la finestra, fatto. Swift
si ricompila solo se tocchi `Peekaboo.swift`, e `run.sh` se ne accorge da solo.

### Perché serve un vero `.app`

Non è un vezzo. Senza bundle le notifiche di sistema non funzionano
(`UNUserNotificationCenter` richiede un bundle identifier), l'avvio automatico è
fragile, e il permesso Automazione viene attribuito al terminale invece che a
Peekaboo — quindi verrebbe richiesto di nuovo a ogni ricompilazione.

### Sicurezza

Il server sta in ascolto **solo su `127.0.0.1`**, e gli endpoint che agiscono
(`/api/focus`, `/api/close`) accettano soltanto pid che corrispondono a una
sessione Claude viva. Non è un canale per eseguire comandi arbitrari.

### Perché non è un widget macOS

I widget WidgetKit si ridisegnano a snapshot, su una timeline decisa dal sistema,
di solito ogni parecchi minuti: niente animazione, niente aggiornamento continuo.
In più girano in sandbox, quindi leggere `~/.claude` richiede entitlement e app
group. Una finestra flottante dà molto di più con molta meno impalcatura.

---

## Personalizzazione

| Cosa | Dove |
|---|---|
| Colori degli stati | `ui/index.html`, blocco `:root` |
| Forma, occhi, bocca | `ui/index.html`, l'`<svg id="big">` e la mappa `MOUTH` |
| Vestiti e calendario | `ui/index.html`, `SKINS` e `skinForDate()` |
| Frasi che dice | `ui/index.html`, `POKES` e la funzione `render()` |
| Valori predefiniti | `server.py`, `DEFAULTS` |
| Dimensione e posizione iniziale | `Peekaboo.swift`, `defaultFrame()` |
| Scorciatoia da tastiera | `Peekaboo.swift`, `installHotkey()` |
| Porta del server | variabile `PEEKABOO_PORT` (default 8787) |

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
- La firma è **ad-hoc**: va bene per uso locale, ma per distribuire l'app fuori
  dal tuo Mac servirebbe una firma con Developer ID e la notarizzazione Apple.

---

## Licenza

MIT — vedi [LICENSE](LICENSE).
