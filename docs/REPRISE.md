# REPRISE — point d'entrée après compactage / nouvelle session

> **Règle d'or** : mettre ce fichier à jour à chaque fin de session (état, tests, prochaine étape).
> Tout l'état du projet vit dans le dépôt ; une nouvelle session repart d'ici.

## État actuel (27/11/2026, vérifié ce jour)

Chaîne complète **compilateur Oberon-07 → bytecode `.obc` → VM maison**, stage-0 en C,
plus VM réécrite en Oberon **en threaded code** (dispatch par valeurs procédurales).
**Tests : 112/112** (28 exemples × 4 moteurs : `obvm` C, natif `ob2c`+gcc, `VM.Mod` sur obvm,
`VM.Mod` natif). Groupe A du TODO terminé ✅ : types procéduraux + closures + threaded code
+ records en ligne / `VAR` record / `ARRAY OF RECORD` + conformité Oberon-07 (`WHILE...ELSIF`,
CASE de type, `CAP` — aucun opcode nouveau) (`OP_PROCVAL`=88 / `OP_CALLP`=89,
`CLOSURE_TAG`, handlers `H_OP_*`, `telem`/`ElemCells` dans VM.Mod).

```
oberon/
  README.md  journal.md  TODO.md          docs de haut niveau
  docs/REPRISE.md (ce fichier)  LANGAGE.md (référence du dialecte)  AUTOHEBERGEMENT.md (vision)
  lib/            bibliothèque : MathLib.Mod, Strings.Mod (+ .obc recompilés par les tests)
  bootstrap/      stage-0 100 % C : src/ (obc obvm obdis ob2c, runtime rt.[ch] partagé),
                  build.sh, Makefile, examples/ (22 .Mod), tests/run_tests.sh + expected/
                  binaires : obc.exe obvm.exe obdis.exe ob2c.exe
  selfhost/       VM.Mod (~700 lignes, la VM en Oberon) + VM.obc (recompilé par run_tests.sh)
```

## Commandes essentielles (toutes depuis `bootstrap/`)

```sh
./build.sh                          # rebuild les 4 binaires C
./tests/run_tests.sh                # 88/88 attendu ; « passed: 88  failed: 0 »
./obc.exe examples/Hello.Mod        # compile (.obc à côté du .Mod ; imports compilés aussi)
./obvm.exe examples/Hello.obc       # exécute sur la VM C
./obdis.exe examples/Hello.obc      # désassemble
./obvm.exe ../selfhost/VM.obc examples/Hello.obc   # exécute via VM.Mod (Oberon) sur obvm
# natif : ./ob2c.exe examples/Hello.obc -o /tmp/H.c && gcc -O2 -Isrc -o /tmp/h /tmp/H.c \
#          src/rt.c src/ob.c src/model.c src/module.c -lm && /tmp/h examples/Hello.obc
```

Chemin de recherche des imports (dans obc, obvm, ob2c **et** VM.Mod) : `D/M.obc`, `D/M.Mod`,
`D/../lib/…`, `D/../../lib/…` — c'est comme ça que `lib/` est trouvable depuis `bootstrap/examples` et `selfhost/`.

## Invariants à ne PAS régresser

- **Opcodes append-only** dans `bootstrap/src/ob.h` (derniers = `OP_PROCVAL` 88, `OP_CALLP` 89 ; `OP_DISPOSE` 87 ; `OP_JUMPTABLE` 86). **Piège** : `OP_PROCVAL` = **trois opérandes u32** (12 octets : lmod, proc, steps), pas u8+u32.
- Valeur procédurale simple = cellule taguée `TAG_PROC=0x03` : [tag][gid 8 bits][proc 32 bits] (`MK_PROC`/`PROC_GID`/`PROC_IDX`). **Closure** = ref heap nue vers objet `CLOSURE_TAG=0x40000001` : `[tag][gid][proc][nframes][par frame: nlocals, cellules...]` ; matérialisée à `OP_CALLP`, réécrite au `OP_RET` (Frame.extra/cref ; helpers `rtProcVal`/`rtCallP`/`rtLeaveFrame` dans rt.c partagés obvm/ob2c ; idem VM.Mod avec fextra/fcref).
- `OP_PROCVAL` steps = `0xFFFFFFFF` → valeur simple ; sinon snapshot de `steps` slinks. **Piège lexer** : `lexSave`/`lexRestore` = pushback de **tokens** (hist/pb dans lexer.c), PAS de fseek (pas fiable en mode texte Windows).
- Threaded code VM.Mod : slot opcode = valeur proc handler (`PROCC(handlers[op])`), opérandes = 1 octet/cellule (**y compris `n` de JUMPTABLE : 4 cellules**). Casts prédéfinis `PROCV`/`PROCC` (identité). Dispatch : `h := PROCV(code[cofs+pc]); INC(pc); h();`.
- Kinds de types : `TK_LONGINT`=10, **`TK_PROC`=11** (les deux côtés C et VM.Mod doivent d'accord).
- Records : variables record **en ligne** OK (`VAR pt: Point`, payload cellules inline) ; `hdr` designator = 2 (record heap via pointeur) / 0 (inline/élément) ; `ARRAY OF Record` : header `total` = **cellules** (`total × payload`), index × `ElemCells` avant `OP_ELEM_ADDR`. Params record valeur refusés (VAR uniquement).
- Cellules 64 bits ; adresses taggées (octet haut : 0x00 pile / 0x01 global / 0x02 tas).
- **Adresse globale = gid absolu** résolu à la création (pas l'index d'import local) — sinon les `VAR`
  cross-module lisent le mauvais module. Idem dans `VM.Mod`. Max 256 modules.
- Tas : **free-list first-fit + découpe** (bloc libre = `[0, taille, suivant]`) dans `rt.c` et `VM.Mod` ;
  `OP_DISPOSE` met NIL dans le slot (double DISPOSE = no-op).
- `Type.visited` = **stamp `gTypeStamp`** incrémenté par `writeModule` (pas un simple flag booléen).
- Procédure corps = `procs[0]` ; les pointeurs `Proc*` deviennent invalides après `addProc` (realloc) → utiliser des **indices**.
- Constantes `TK_LONGINT`/`TK_OP` identiques des deux côtés C et VM.Mod (TK_ARRAY=7, RECORD=8, POINTER=9).
- Mots-clés **sensibles à la casse** en majuscules (`In` ≠ `IN`) ; `HALT` est un ident prédéfini.

## Dialecte supporté (extensions maison marquées « ext » dans `docs/LANGAGE.md`)

LONGINT 64 bits, procédures-fonctions avec `RETURN expr`, littéraux `'c'`, appels sans `()`,
`FLOOR`, `Out.Byte`/`In.Byte`, module `Files` (I/O binaire fichiers), **open arrays**
(`VAR a: ARRAY OF T`, `LEN(a,0)` = taille réelle), **`NEW`/`DISPOSE` sur POINTER TO ARRAY OF T**,
**conversion implicite INTEGER→REAL** (`7/2 = 3.5`), **`WITH p: T DO … END`** (multi-gardes),
**types procéduraux + closures** (`TYPE P = PROCEDURE(...)[: T]`, `VAR f: P`, `f := Proc`,
`f(args)`, `f = NIL`, `RETURN Proc`, proc imbriquée = closure avec état capturé persistant),
module `SYSTEM`
(BAND/BOR/BXOR/BNOT/LSH/ROT/BIT/ARGC/ARGV/TICKS/EXIT, casts L2I/REALBITS/BITSREAL/I2REAL),
superinstruction `OP_JUMPTABLE` pour les `CASE` denses.

## Prochaine étape — **OC.Mod, le compilateur en Oberon** (groupe A terminé ✅, conformité Oberon-07 faite ✅)

1. OC.Mod émetteur de `.obc` identique au stage-0 (phase `PASS-OC` dans run_tests.sh)
2. Backend C dans OC.Mod + auto-compilation (`oc.obc → oc2.c → gcc`, `diff`),
   `bootstrap/tests/expected/` comme banc de régression
3. `SYSTEM.VAL/ADR/GET/PUT` seulement si besoin réel (sinon PROCV/PROCC suffisent)

Rappel conformité (rapport Oberon-07 officiel, rev. 3.5.2016) : **pas de LOOP/EXIT/WITH** —
remplacés par `WHILE...ELSIF` (boucle gardée de Dijkstra) et le CASE de type ; `WITH` gardé
comme extension chez nous.

Détails : `TODO.md` (cases à cocher) · `journal.md` (faits, datés) · `docs/AUTOHEBERGEMENT.md` (vision).

## Rappels de session (Vibe Desktop)

Pas de `/compact` manuel en Desktop : le compactage est **automatique** au seuil
`auto_compact_threshold` (config `~/.vibe/config.toml`) ; une nouvelle session remet le
contexte à zéro — d'où ce fichier. Pour alléger le contexte : ne pas relire les gros fichiers
en entier, déléguer les recherches larges à des sous-agents, réponses courtes.
