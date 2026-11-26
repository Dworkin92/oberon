# Journal de création d'un compilateur Oberon

## 23/11/2026

- création de la v1 du compilateur, d'une VM et d'un désassemnleur
- le langage est un sous-ensemble d'Oberon, plus grand que la version 0 de Wirth selon Mirage
- 12 tests OK

## 24/11/2026

- création des LONGINT, et Bytes
- ajout du module Files et des fonctions adéquate pour lire et écrire dans des fichiers
- ids 40–50 dans bootstrap/src/vm.c:callBuiltin : BAND/BOR/BXOR/BNOT (ET/OU/XOR/complément 64 bits), LSH (gauche si n≥0, droit logique sinon), ROT (rotation mod 64), BIT (test de bit → BOOLEAN), ARGC, ARGV(i, VAR s), TICKS (ms via clock()), EXIT(code)
- computed goto
- ajout d'un backend oberon -> C.
- 16 tests OK


# reste à faire 

- Back-end C minimal dans le compilateur Oberon (juste de quoi faire tourner Hello) pour valider le runtime C ;
- VM en Oberon (VM.Mod), d'abord exécutée par obvm C, puis transpilée ;
- Compilateur en Oberon avec back-end C, et le test ultime : il se compile lui-même (oc.obc → oc2.c → oc2.exe), avec bootstrap/tests/expected/ comme banc de régression.

À votre rythme — le livrable actuel (obc/obvm/obdis + 12 tests qui passent) est une base saine pour tout ça. Bonne exploration !
## 24/11/2026 (suite)

- réorganisation : tout le stage-0 C part dans `bootstrap/` (src, build.sh, Makefile, examples, tests, binaires) ; la racine accueille `docs/` et bientôt `selfhost/`
- module `SYSTEM` : casts ajoutés (ids 51–54) : `L2I` (LONGINT→INTEGER), `REALBITS`, `BITSREAL`, `I2REAL` — nécessaires pour écrire la VM en Oberon (les cellules guest sont des LONGINT)
- étape 3 : `ob2c` — transpiler `.obc` → C déroulé (une fonction C par proc, `goto`, `procTab`), runtime extrait dans `bootstrap/src/rt.[ch]` partagé obvm/code généré. Bench : 587 ms natif vs 2133–2344 ms obvm (×4). Suite de tests double : PASS + PASS-C (32/32)
- étape 4 : `selfhost/VM.Mod` — la VM écrite en Oberon (~700 lignes) : loader .obc, tas, pile, frames, mémoire taggée, builtins guest réimplémentés en Oberon. 3e phase de tests PASS-VM : 51/51 (17 exemples × VM / C natif / VM.Mod)
- deux vrais bugs du stage-0 découverts et corrigés grâce à VM.Mod :
  - `CASE` multi-labels (`0, 1:`) ne matchait jamais (mauvais patch des JZ) → codegen refait en JNZ-vers-corps ; régression `examples/CaseLabels.Mod` (expected Control.txt mise à jour)
  - les constantes `LONGINT` étaient émises en `CONST_I` tronqué (`CONST M = 4294967295` → -1) → émission `CONST_L` quand le type est LONGINT
- perfs : Queens 74 ms en obvm direct, ~2 s via VM.Mod sur obvm (~27×, normal en interprété-dans-interprété avec CASE linéaire)
- étape 5 : VM.Mod transpilé en C natif (ob2c + gcc) -> 4e phase de tests PASS-VMN, 68/68 au total (17 exemples x 4 moteurs : obvm, C natif, VM.Mod sur obvm, VM.Mod natif)
- superinstruction OP_JUMPTABLE (86) : CASE dense (>=8 labels) -> table de saut O(1) ; ob2c émet un switch C (jump table gcc). Bugs attrapés au passage : corps ELSE qui tombait dans le dispatch, cible default non marquée dans ob2c. CaseLabels.Mod couvre les deux chemins (chaîne + table). 68/68. Queens via VM.Mod : natif 523 ms (vs 805 avant), sur obvm 1183 ms (vs 1986), obvm direct 87 ms.

## 25/11/2026

- open arrays (ARRAY OF T en paramètre formel) : flag isOpen sur Type, "ARRAY OF T" parsé seulement dans les FPSection, LEN(a,0) = taille réelle, littéral chaîne accepté pour ARRAY OF CHAR valeur, VAR open = par référence, sérialisation .obc via sentinelle ndim=0xFFFFFFFF (VM.Mod mis à jour). Tests : OpenArr.Mod + MathLib.SumArr inter-modules. 72/72 (18 ex x 4 moteurs).
- répertoire `lib/` à la racine (nomenclature type "Lib" de Python) : `MathLib.Mod` déplacé depuis bootstrap/examples, nouveau `lib/Strings.Mod` (Len/Equal/Compare/Append/Insert/IntToStr/StrToInt sur chaînes 0X), démo `examples/StringsDemo.Mod`. Chemin de recherche des imports, dans obc ET obvm ET ob2c ET VM.Mod : `D/M.obc`, `D/M.Mod`, `D/../lib/…`, `D/../../lib/…` (couvre bootstrap/examples et selfhost vers la racine). Helper C partagé `findModuleFile()` dans module.c ; `run_tests.sh` nettoie `../lib/*.obc` et enregistre StringsDemo. 76/76 (19 ex × 4 moteurs).
- deux vrais bugs attrapés par StringsDemo :
  - `Type.visited` (garde de récursion de registerTypeDeep) fuirait entre compilations de modules dans le même process obc (compilation imbriquée d'import) → les types de base (CHAR…) n'étaient pas ré-enregistrés dans le .obc du module importateur, `elem=3` pointait hors table, "truncated .obc string". Corrigé par un stamp `gTypeStamp` incrémenté à chaque writeModule.
  - `ADDR_GLOBAL` étiquetait l'adresse avec l'index d'import LOCAL du module créateur, mais `memRead` résolvait via `cur->map` du module EN COURS d'exécution → une adresse globale passée en VAR à un autre module lisait les globales du mauvais module ("LEN of nil" dans Strings.Append). L'adresse stocke maintenant le gid absolu (résolu à la création) ; idem dans VM.Mod (OP_ADDR_GLOBAL, MemRead, MemWrite) ; garde 256 modules (gid sur 1 octet).
  - bug de Strings.Insert : terminateur posé à pos+slen au lieu de n+slen → tronquait la fin ("Oberon!" au lieu de "Oberon!-07").
- item crucial n°2 : NEW(p) sur POINTER TO ARRAY OF T + DISPOSE avec free-list.
  - nouvel opcode OP_DISPOSE = 87 (append-only ; u8 mod + u32 typeidx du type pointeur). Sémantique : pop slot addr, libère l'objet (taille calculée depuis le type pointé), stocke NIL dans le slot (double DISPOSE = no-op).
  - tas avec free-list first-fit + découpe (bloc libre : heap[h]=0, heap[h+1]=taille, heap[h+2]=suivant) dans rt.c (heapAlloc/heapFree/heapObjSize/rtNew/rtDispose) et dans VM.Mod (HeapAlloc/HeapFree/ObjSize). OP_NEW dispatch selon le kind du pointee : record (tag+payload, comme avant) ou array (allocArrayObj, qui réutilise la free-list). Garde "double DISPOSE" si heap[ref]=0.
  - ob2c émet des appels aux fonctions rt (rtNew/rtDispose) au lieu du code inline.
  - parser : POINTER TO ARRAY n OF T (et POINTER TO type-tableau nommé) accepté dans parseType ; NEW accepte record ou tableau fixe (open array refusé) ; nouveau prédéfini DISPOSE (param VAR anyPointer) ; indexation implicite p[i] (deref implicite), LEN(p,0), et p accepted comme argument value/VAR là où ARRAY OF T ouvert est attendu (typeAssignable + parseCallArgs).
  - test DynArr.Mod (NEW/LEN/Sum via VAR open/NIL après DISPOSE/réutilisation/double DISPOSE/type nommé) enregistré dans run_tests.sh → 80/80 (20 ex × 4 moteurs). Stress : 200k NEW/DISPOSE passent dans le tas borné à 1M cellules de VM.Mod → la free-list recycle bien.
- item crucial n°3 : conversion implicite INTEGER -> REAL (ext). typeAssignable accepte INT->REAL ; le parser émet OP_I2F aux points de conversion : opérandes mixtes de + - * (via SWAP/I2F/SWAP pour convertir celui sous le sommet), / (division réelle : 7/2 = 3.5, les deux opérandes INT convertis), comparaisons mixtes (FEQ/FLT/...), assignation scalaire, arguments valeur (y compris builtins Out.Real(5,0)), RETURN d'une fonction REAL. DIV/MOD restent strictement entiers ; LONGINT non converti implicitement en REAL. Test RealConv.Mod (r:=3, 7/2, 1+2.5, 2.5*4, -3+0.5, Half(7), Show(5), 2<2.5, 2=2.0, 3.5>=3) → 84/84 (21 ex × 4 moteurs). Aucun changement VM (OP_I2F existait déjà).
- WITH p: T DO … END (ext) : nouveau case S_WITH dans parseStatement. Pour chaque garde : check statique (variable POINTER TO Record, type de garde = pointé ou extension), check runtime OP_CHECKTYPE à l'entrée (échoue « type guard failed »), puis shadowing : un Obj fantôme de même stockage (level/offset/isVarParam) mais de type POINTER TO T est empilé dans la portée courante pour la durée du corps, dépilé après le END (pile withShadows). Multi-gardes `WITH a: T, b: U DO` supportées. Aucun changement VM (OP_CHECKTYPE existait). Test WithDemo.Mod (Circle/Rect sur Shape, param de proc, multi-gardes, type restauré après le WITH) + test négatif (garde fausse → runtime error) → 88/88 (22 ex × 4 moteurs).
- doc de reprise `docs/REPRISE.md` créée (point d'entrée compact après compactage/nouvelle session : état 88/88 vérifié, commandes, arborescence, invariants à ne pas régresser, prochaine étape) ; pointeurs ajoutés dans README.md et TODO.md. Règle : la mettre à jour à chaque fin de session.

## 26/11/2026

- **types procéduraux / variables procédurales** (groupe A, premier item) — portés dans les 4 moteurs, test `ProcVar.Mod` → **92/92** (23 ex × 4).
  - modèle : nouveau kind `TK_PROC` (=11, après TK_LONGINT=10 — piège : VM.Mod avait d'abord mis 10) avec liste de paramètres (Obj chain) + `result` ; égalité **structurelle** (VAR-ness + types + résultat) ; `NIL` assignable à une var procédurale.
  - sérialisation `.obc` : `writeType`/`registerTypeDeep`/loader C gèrent TK_PROC (nparams, par param typeidx+var, result) ; loader de VM.Mod saute le payload (kind 11) sinon désync « too many procs ».
  - parser : `PROCEDURE [Formals] [: T]` dans `parseType` ; `f := ProcIdent` (ou `M.Proc`) via `tryEmitProcValue` (lexSave/lexRestore, contrôle de signature, refus des procédures imbriquées — pas encore de closures) ; appel indirect `f(args)` en statement et en expression (args d'abord, valeur proc au sommet) ; argument procédural dans `parseArgsList` ; comparaison `f = NIL` / `f = g` autorisée.
  - nouveaux opcodes append-only : `OP_PROCVAL` = 88 (u32 lmod, u32 procIdx — **deux u32**, pas u8+u32 : bug attrapé en instrumentant VM.Mod, pidx lu décalé de 24 bits) et `OP_CALLP` = 89 (pop valeur proc, appel indirect, args en dessous). Valeur proc = cellule taguée `TAG_PROC=0x03` : [tag 8 bits][gid 8 bits][proc 32 bits] (`MK_PROC`/`PROC_GID`/`PROC_IDX` dans ob.h).
  - VM C (`vm.c`) : les deux opcodes inline (lien statique = frame appelant, suffisant pour les procs de niveau module) ; `ob2c` émet le même code inline + `procTab[g][pidx](vm)` ; `obdis` : noms + opérandes A_PROC2.
  - VM.Mod : constantes 88/89 + branches CASE (décodage via LSH/BAND, `TAG_PROC*2^56 + gid*2^48 + pidx`), loader TK_PROC.
  - erreurs propres : signature incompatible → erreur de compilation « procedure 'One' does not match type 'BinOp' » ; appel de NIL → « runtime error: call of NIL procedure ».
  - procs de niveau module uniquement (slink = frame appelant) ; closures = item suivant, et c'est la porte ouverte vers le **threaded code** dans VM.Mod.
- **closures** (26/11, même jour) — test `Closure.Mod` → **96/96** (24 ex × 4 moteurs).
  - `OP_PROCVAL` passe à **3 opérandes u32** (lmod, procIdx, steps) : `steps = 0xFFFFFFFF` (L2I → -1) = proc de niveau module → valeur taguée 0x03 ; sinon snapshot de la chaîne de `steps` slinks depuis la frame courante jusqu'à la racine dans un objet heap `CLOSURE_TAG = 0x40000001` : `[tag][gid][procIdx][nframes][par frame: nlocals, cellules...]`.
  - `OP_CALLP` : valeur 0x03 → appel direct (slink = frame appelant) ; ref heap `CLOSURE_TAG` → matérialise les frames capturées sur la pile (racine d'abord), pousse la frame du callee avec `extra = n` (frames capturées à dépiler) et `cref` (objet closure).
  - `OP_RET` (`rtLeaveFrame` dans rt.c, partagé obvm et code ob2c) : dépile `1 + extra` frames et **réécrit** les cellules capturées dans l'objet closure → état persistant (compteur : 100, 200, 307 ✓).
  - `Frame` gagne `extra`/`cref` (rt.h) ; `rtEnterBody`, `OP_CALL` et `OP_CALLP` les initialisent à 0.
  - parser : `tryEmitProcValue` accepte toute proc (steps = curLevel - level, sentinel si level 0) ; garde-fou : ident suivi de `(` = appel, pas valeur ; fonction 0-param sans `(` = appel implicite, pas valeur. `RETURN ProcIdent` supporté quand le type de résultat est procédural.
  - **bug lexer attraqué** : `lexSave`/`lexRestore` restauraient `ch` mais pas la position du `FILE*` → le lookahead consommé entre save et restore était perdu (`MakeAdder(5)` devenait `MakeAdder()`). Corrigé avec `ftell`/`fseek` dans `LexState.fpos`.
  - VM.Mod : `fextra`/`fcref`, `scratch`, branches OP_PROCVAL (snapshot via HeapAlloc) / OP_CALLP (matérialisation) / OP_RET (réécriture), init frame 0.
  - ob2c : `OP_PROCVAL` → `rtProcVal(...)`, `OP_CALLP` → `rtCallP` + `procTab[tf->mod][tf->proc](vm)`, `OP_RET` → `rtLeaveFrame(vm); return;`, `OP_CALL` pose extra/cref = 0 ; obdis : OP_PROCVAL = A_CALL (3 u32).
