# REPRISE — point d'entrée après compactage / nouvelle session

> **Règle d'or** : mettre ce fichier à jour à chaque fin de session (état, tests, prochaine étape).
> Tout l'état du projet vit dans le dépôt ; une nouvelle session repart d'ici.

## État actuel (28/11/2026, soir — vérifié)

Chaîne complète **compilateur Oberon-07 → bytecode `.obc` → VM maison**, stage-0 en C,
plus VM réécrite en Oberon **en threaded code**, et **auto-hébergement atteint** :
`selfhost/OCS.Mod` (lexer en Oberon) + **`selfhost/OC.Mod` (le compilateur complet en Oberon,
~2900 lignes, 103 procs)** émet des `.obc` **octet-identiques** au stage-0 C sur les 31 exemples,
**et OC.Mod se compile lui-même : OC.obc → OC2.obc → OC3.obc, point fixe byte-identique** 🎉
(`obvm OC.obc OC.Mod -o OC2.obc`, `cmp OC.obc OC2.obc`).
**Tests : 151/151** = 31 exemples × 4 moteurs (obvm C, natif ob2c+gcc, VM.Mod sur obvm,
VM.Mod natif) + 31 phases **PASS-OC** (cmp du .obc produit par OC.Mod vs stage-0).
Dont `SqlDemo.Mod` (SQLite via **FFI pur Oberon** : `lib/Sqlite.Mod` au-dessus de
`SYSTEM.CALLC/LOADLIB/SYMBOL` ids 80–89, glue C `src/ffi_glue.c`, DLL `sqlite3.dll` chargée à
l'exécution). Sémantique : le body de chaque module chargé tourne au démarrage (dépendances
d'abord) — `rtEnterBody` chaîné, idem ob2c généré et VM.Mod. Groupe A du TODO terminé ✅,
**groupe B (OC.Mod → bytecode) terminé ✅** : types procéduraux + closures + threaded code
+ records en ligne / `VAR` record / `ARRAY OF RECORD` + conformité Oberon-07 (`WHILE...ELSIF`,
CASE de type, `CAP`, **`FORWARD`** ajouté 28/11 — `S_FORWARD`=65 append-only) —
(`OP_PROCVAL`=88 / `OP_CALLP`=89, `CLOSURE_TAG`, handlers `H_OP_*`, `telem`/`ElemCells` dans VM.Mod).
Toolchain : gcc/clang winlibs **16.2.0** (`/c/Local/Tools/mingw64-16.2.0`), préféré dans
build.sh/run_tests.sh/Makefile.

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
./build.sh                          # binaires -> build/bin/ (+ build/lib précompilé, + sqlite3.dll)
./tests/run_tests.sh                # 116/116 attendu ; « passed: 116  failed: 0 » (lent : lancer en arrière-plan)
build/bin/obc.exe examples/Hello.Mod        # compile (.obc à côté du .Mod ; imports compilés aussi)
build/bin/obvm.exe examples/Hello.obc       # exécute sur la VM C
build/bin/obdis.exe examples/Hello.obc      # désassemble
build/bin/obvm.exe ../selfhost/VM.obc examples/Hello.obc   # exécute via VM.Mod (Oberon) sur obvm
# natif : build/bin/ob2c.exe examples/Hello.obc -o /tmp/H.c && gcc -O2 -Isrc -o /tmp/h /tmp/H.c \
#          src/rt.c src/ob.c src/model.c src/module.c src/ffi_glue.c -lm && /tmp/h examples/Hello.obc
#          (toujours ajouter src/ffi_glue.c : le runtime C référence les builtins FFI 80–91)
```

Recherche des imports (dans obc, obvm, ob2c **et** VM.Mod) — premier trouvé gagne :
`D` (dir du fichier), `D/../lib`, `D/../../lib`, puis `OBERON_PATH` = `.` (CWD) en tête +
les entrées de la variable d'environnement (séparateur `;` Windows / `:` POSIX) +
`$OBERON_HOME/lib` en fin si absent. `OBERON_HOME` sinon = dir de l'exe sans le `/bin` final
(`SYSTEM.EXEPATH`/`SYSTEM.GETENV`, builtins 90–91). `build/` = notre OBERON_HOME local
(`build/bin` + `build/lib`) ; installation finale visée : seulement `$OBERON_HOME/bin` + `$OBERON_HOME/lib`.

## Invariants à ne PAS régresser

- **Opcodes append-only** dans `bootstrap/src/ob.h` (derniers = `OP_PROCVAL` 88, `OP_CALLP` 89 ; `OP_DISPOSE` 87 ; `OP_JUMPTABLE` 86). **Piège** : `OP_PROCVAL` = **trois opérandes u32** (12 octets : lmod, proc, steps), pas u8+u32.
- Valeur procédurale simple = cellule taguée `TAG_PROC=0x03` : [tag][gid 8 bits][proc 32 bits] (`MK_PROC`/`PROC_GID`/`PROC_IDX`). **Closure** = ref heap nue vers objet `CLOSURE_TAG=0x40000001` : `[tag][gid][proc][nframes][par frame: nlocals, cellules...]` ; matérialisée à `OP_CALLP`, réécrite au `OP_RET` (Frame.extra/cref ; helpers `rtProcVal`/`rtCallP`/`rtLeaveFrame` dans rt.c partagés obvm/ob2c ; idem VM.Mod avec fextra/fcref).
- `OP_PROCVAL` steps = `0xFFFFFFFF` → valeur simple ; sinon snapshot de `steps` slinks. **Piège lexer** : `lexSave`/`lexRestore` = pushback de **tokens** (hist/pb dans lexer.c), PAS de fseek (pas fiable en mode texte Windows).
- Threaded code VM.Mod : slot opcode = valeur proc handler (`PROCC(handlers[op])`), opérandes = 1 octet/cellule (**y compris `n` de JUMPTABLE : 4 cellules**). Casts prédéfinis `PROCV`/`PROCC` (identité). Dispatch : `h := PROCV(code[cofs+pc]); INC(pc); h();`.
- Kinds de types : `TK_LONGINT`=10, **`TK_PROC`=11** (les deux côtés C et VM.Mod doivent d'accord).
- Records : variables record **en ligne** OK (`VAR pt: Point`, payload cellules inline) ; `hdr` designator = 2 (record heap via pointeur) / 0 (inline/élément) ; `ARRAY OF Record` : header `total` = **cellules** (`total × payload`), index × `ElemCells` avant `OP_ELEM_ADDR`. Params record valeur refusés (VAR uniquement).
- **Taille inline des champs record** : un champ `ARRAY n OF T` occupe `n × ElemCells(T)` cellules
  dans le payload (fonction `typeInlineCells` dans model.c, utilisée par `completeRecord`) —
  ne PAS confondre avec `typeSizeCells` (taille de **slot** de variable : un tableau = 1 réf).
  Bug 28/11 : `Token = RECORD … name: ARRAY 64 OF CHAR; sval: ARRAY 4096 OF CHAR …` avait
  payload=8 → débordement du tas. Corrigé côté C ; VM.Mod lit `payload` depuis le .obc (OK).
- **Indexation d'un tableau en ligne** (champ record ou élément record) : l'adresse est déjà
  le payload → le parser émet `OP_AADD` (payload + index), PAS `OP_ELEM_ADDR` (qui attend une
  réf heap nue) — flag `addrIsPayload` dans `parseDesignator` (parser.c). Bug 28/11 (crash
  `OCS.RecordTok` sur `t.name[i]`).
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

## Prochaine étape — **groupe C : backend C dans OC.Mod** (OC.Mod → bytecode ✅ fait)

1. OC.Mod émettant du **C** à la place du bytecode (pattern `ob2c` : une fonction C par proc,
   runtime `rt.c` partagé) → auto-compilation native : `oc.obc → oc.c → gcc → oc2.exe`,
   puis `oc2.exe` se recompile lui-même, `diff` des .c
2. `bootstrap/tests/expected/` comme banc de régression complet
3. `SYSTEM.VAL/ADR/GET/PUT` seulement si besoin réel (sinon PROCV/PROCC suffisent)

Pièges OC.Mod (ne pas régresser) : **jamais de champ tableau inline de record (t.name) passé
en param open array** — les `name` sont des `StrRef = POINTER TO ARRAY … OF CHAR` ; `&`/`OR`
**non court-circuitants** (ne jamais indexer avec un indice possiblement hors limites dans une
chaîne `&`) ; `INC/DEC` = variable INTEGER + constante seulement ; labels de CASE = constantes
**locales** (pas `OCS.S_*`) ; code émis par blocs chaînés par proc (`CodeBlock`, 4096 octets),
`Patch32` octet par octet ; `OCS.Open` lit déjà le 1er token ; `HALT` = ident (pas mot-clé :
retiré du KwLookup d'OCS pour coller au lexer C) ; littéraux REAL : parseur correctement
arrondi (mantisse exacte + une seule échelle 10^k) pour coller à `strtod`.
Bugs corrigés le 28/11 (ne pas régresser) : `nc` non déclaré dans `LoadMod` (VM.Mod) ;
`RefToStr` (VM.Mod) : sur `NUL` faire `i := total` → `buf[256]` hors limites ; champ record
tableau = `typeInlineCells` (voir invariants) ; indexation tableau inline = `AADD` pas
`ELEM_ADDR` ; FORWARD : à la déclaration réelle, remettre `nparams`/`nlocals`/`code` à zéro.

Rappel conformité (rapport Oberon-07 officiel, rev. 3.5.2016) : **pas de LOOP/EXIT/WITH** —
remplacés par `WHILE...ELSIF` (boucle gardée de Dijkstra) et le CASE de type ; `WITH` gardé
comme extension chez nous.

Détails : `TODO.md` (cases à cocher) · `journal.md` (faits, datés) · `docs/AUTOHEBERGEMENT.md` (vision).

## Rappels de session (Vibe Desktop)

Pas de `/compact` manuel en Desktop : le compactage est **automatique** au seuil
`auto_compact_threshold` (config `~/.vibe/config.toml`) ; une nouvelle session remet le
contexte à zéro — d'où ce fichier. Pour alléger le contexte : ne pas relire les gros fichiers
en entier, déléguer les recherches larges à des sous-agents, réponses courtes.
