# TODO — compilateur Oberon auto-hébergé

> ⭐ Après un compactage ou une nouvelle session, repartir de [`docs/REPRISE.md`](docs/REPRISE.md).

État au 27/11/2026 : étapes 0–5 faites + tout le groupe A (types procéduraux, closures, threaded code, records en ligne) + conformité Oberon-07 (WHILE...ELSIF, CASE de type, CAP) + builtin SQLite (FFI niveau 1), **116/116 tests** (29 exemples × 4 moteurs :
`obvm` C, natif `ob2c`+gcc, `VM.Mod` sur obvm, `VM.Mod` natif). Voir
[`docs/AUTOHEBERGEMENT.md`](docs/AUTOHEBERGEMENT.md) pour la vision d'ensemble. **Groupe A terminé ✅ — prochain gros morceau : OC.Mod.**

## ✅ Fait

- [x] Étape 0 — toolchain C dans `bootstrap/` (obc/obvm/obdis), 15 tests
- [x] Étape 1 — module `SYSTEM` (bitwise 64 bits, `ARGC/ARGV`, `TICKS`, `EXIT`, casts `L2I/REALBITS/BITSREAL/I2REAL`)
- [x] Étape 2 — computed goto dans `vm.c` (×1,44 vs switch)
- [x] Étape 3 — `ob2c` : `.obc` → C déroulé + gcc (×4 vs obvm sur Bench), runtime `rt.[ch]` partagé
- [x] Étape 4 — `selfhost/VM.Mod` : la VM en Oberon (~700 lignes), phase de tests `PASS-VM`
- [x] Étape 5 — `VM.Mod` transpilé en natif (`vm_native`), phase `PASS-VMN`
- [x] Superinstruction `OP_JUMPTABLE` (CASE dense → saut O(1) ; Queens via VM.Mod natif : 523 ms)
- [x] Bugs stage-0 corrigés : `CASE` multi-labels, constantes `LONGINT` tronquées
- [x] **Répertoire `lib/`** à la racine + chemin de recherche des imports (`D/`, `D/../lib/`, `D/../../lib/`) dans `obc`, `obvm`, `ob2c` **et** `VM.Mod` ; `lib/MathLib.Mod` + nouveau `lib/Strings.Mod` (Len/Equal/Compare/Append/Insert/IntToStr/StrToInt), démo `StringsDemo` — 76/76
- [x] Bug `visited` : flag de registration des types partagé entre compilations → stamp `gTypeStamp` par `writeModule` (sinon types de base manquants dans le .obc d'un module qui importe)
- [x] Bug adresses globales : `ADDR_GLOBAL` stockait l'index d'import local, résolu contre le mauvais module au déréférencement → stocke maintenant le **gid absolu** (résolu à la création), idem dans `VM.Mod` ; garde 256 modules

## 🎯 Prochaine grosse étape : OC.Mod (étape 6, le compilateur en Oberon)

### A. Fondations langage manquantes (dans le stage-0 d'abord) — ✅ toutes faites le 27/11

- [x] **Open arrays** : `PROCEDURE P(VAR a: ARRAY OF CHAR)` (paramètre de taille dynamique, `LEN(a,0)` = taille réelle passée) — fait : flag `isOpen` sur `Type`, sentinelle `0xFFFFFFFF` dans le `.obc`, tests `OpenArr.Mod` + `MathLib.SumArr` (72/72)
- [x] **Bibliothèque `lib/`** : `MathLib` déplacé, `Strings` ajouté, chemin de recherche `D/`, `D/../lib/`, `D/../../lib/` dans obc/obvm/ob2c/VM.Mod (76/76)
- [x] **`NEW`/`DISPOSE` sur pointeurs vers tableaux** : free-list first-fit, `OP_DISPOSE`=87, `p[i]`/`LEN(p)`/passage en param ouvert implicites — `DynArr.Mod`, 80/80
- [x] **`NEW(p)` sur `POINTER TO ARRAY OF T` + `DISPOSE`** — fait : `OP_DISPOSE` (87), free-list first-fit avec découpe dans le tas (rt.c + VM.Mod), `p[i]` implicite, `LEN(p,0)`, passage à params ouverts, `DISPOSE` met NIL (double DISPOSE = no-op). Test `DynArr.Mod` + stress 200k NEW/DISPOSE dans le tas borné de VM.Mod → 80/80
- [x] **Conversion implicite `INTEGER` → `REAL`** — fait : `I2F` émis dans `+ - * /` (mixte), comparaisons, assignation, arguments valeur, `RETURN` ; `7/2 = 3.5` maintenant. Test `RealConv.Mod` → 84/84
- [x] **`WITH p: T DO … END`** — fait : shadowing de la variable (POINTER TO T) dans le corps + check runtime CHECKTYPE ; multi-gardes OK. Test `WithDemo.Mod` (hiérarchie Shape/Circle/Rect, param, multi-gardes, restauration du type après) → 88/88
- [x] **Types procéduraux / variables procédurales** (26/11) — `TYPE P = PROCEDURE(...)[: T]`, `f := Proc`, `f(args)`, `f = NIL`, proc en argument ; `OP_PROCVAL`=88 (3 u32) / `OP_CALLP`=89 ; test `ProcVar.Mod` → 92/92
- [x] **Closures** (26/11) — proc imbriquée comme valeur : snapshot de la chaîne de frames dans un objet heap `CLOSURE_TAG` (OP_PROCVAL steps≠-1), matérialisation + réécriture au RET (Frame.extra/cref, `rtProcVal`/`rtCallP`/`rtLeaveFrame` dans rt.c, idem VM.Mod) ; `RETURN ProcIdent` ; test `Closure.Mod` (MakeAdder + compteur à état) → **96/96**
- [x] **Threaded code dans VM.Mod** (27/11) — dispatch par valeur procédurale (`h := PROCV(code[pc]); h()`), traduction au chargement, handlers `H_OP_*` + `InitHandlers` + `OpLen`, prédéfinis `PROCV`/`PROCC` ; lexer : pushback de tokens (hist/pb) à la place de fseek ; perfs VM.Mod natif ×1,3 sur Queens → **96/96**
- [x] **`VAR` record params + variables record en ligne + `ARRAY OF RECORD`** (27/11) — `VAR pt: Point` (payload en ligne), `q := pt`, `P(VAR p: Point)` avec arg `pt`/`p^`/`a[i]` ; `ARRAY OF Record` : taille heap = `total × payload` (header `total` en cellules, index × elemCells), `NEW`/`DISPOSE` OK ; test `RecVar.Mod` → **100/100**. Paramètres record *valeur* refusés (utiliser `VAR`).
- [x] **Conformité rapport Oberon-07** (27/11, vérifié contre l'EBNF officiel `Oberon07.Report.pdf` rev. 3.5.2016 : `statement = [assignment | ProcedureCall | IfStatement | CaseStatement | WhileStatement | RepeatStatement | ForStatement]` — **pas de LOOP/EXIT/WITH en Oberon-07**) :
  - `WHILE c1 DO S1 {ELSIF c2 DO S2} END` — boucle gardée de Dijkstra (chaque itération exécute la première garde vraie puis reboucle ; sortie si toutes fausses) — test `WhileElsif.Mod`
  - `CASE p OF T1: S1 | T2: S2 ELSE S3 END` (CASE de type, remplace WITH) — `ISTYPE` sur la chaîne d'extension + `CHECKTYPE` + narrowing statique du sélecteur dans la branche — test `TypeCase.Mod`
  - `CAP(c)` prédéfini — expansion inline (opcodes existants, aucun opcode nouveau) — test `CapDemo.Mod`
  - → **112/112** (28 ex × 4 moteurs). `WITH` conservé comme extension (hors rapport mais testé).
- [ ] `SYSTEM.VAL/ADR/GET/PUT` — pas de besoin réel constaté (PROCV/PROCC couvrent les casts) ; à rouvrir si OC.Mod en a besoin

### B. OC.Mod émettant du bytecode d'abord (plus sûr)

- [ ] Porter le lexer en Oberon (`OCS.Mod` ou section de OC.Mod)
- [ ] Porter le parser single-pass en Oberon, émission `.obc` identique au stage-0
- [ ] Tables de symboles (hash simple), gestion des types, scopes
- [ ] Buffers extensibles (code, chaînes) via NEW/DISPOSE sur tableaux
- [ ] Helpers chaînes (concat, compare, insert) — pas de concat native
- [ ] Test : `obc OC.Mod` → `OC.obc` ; `obvm OC.obc Hello.Mod` → `Hello2.obc` ; `obvm Hello2.obc` == sortie de référence
- [ ] Brancher dans la suite de tests (phase `PASS-OC`)

### C. Backend C dans OC.Mod (l'étape 6 finale)

- [ ] Émettre du C à la place du bytecode (pattern `ob2c` : une fonction C par proc, `goto`, `procTab`, `main` embarqué, runtime `rt.c`)
- [ ] Test ultime : OC.Mod se compile lui-même — `oc.c` → gcc → `oc2` → `oc2.c` ; `diff oc.c oc2.c`
- [ ] `bootstrap/tests/expected/` comme banc de régression complet

## 🔌 FFI / accès C et SGBDR (niveau 1 fait ✅)

- [x] **SQLite embarqué** (27/11) — amalgamation vendue `bootstrap/ext/sqlite/` (3.54.1, link **statique**, pas de DLL), builtin `SQLite` ids 60–70 dans `src/sqlite_glue.c`, API `DB/Stmt = LONGINT`, wrappers VM.Mod, test `SqlDemo.Mod` → **116/116** sur les 4 moteurs. Docs : LANGAGE.md §6.
- [ ] **FFI générique** (niveau 2) : `SYSTEM.LOADLIB/SYMBOL` + opcode `OP_CALLC` (appel de pointeur de fonction C, args registres x64 + pile) — pour n'importe quelle DLL. Limites : pas de callback C→Oberon, flottants en XMM (passer les bits via REALBITS ou wrapper C mince).
- [ ] **Sockets + protocole natif** (niveau 3) : builtin `Net` (winsock `ws2_32.dll` : Socket/Connect/Send/Recv/Close) puis `lib/Pg.Mod` en **pur Oberon** (protocole wire PostgreSQL v3 : startup, auth md5 puis SCRAM-SHA-256 — SHA-256/HMAC/PBKDF2 en Oberon, simple query 'Q', parse DataRow/RowDescription) et `lib/MariaDB.Mod` (protocole MySQL). Zéro dépendance C côté client.
- [ ] Déclaration `FOREIGN "sym" LIB "dll"` dans le dialecte pour OC.Mod (émettre `extern` + link en C) — seulement si besoin réel, les builtins couvrent le reste.

## 🧹 Polish / plus tard

- [ ] Monter les tailles heap de `VM.Mod` (CONST) pour les grosses compilations
- [ ] GC ou free-list propre (aujourd'hui `NEW` n'est jamais libéré)
- [ ] `WITH`, `DISPOSE` prédéfini, `MIN/MAX`
- [ ] `&`/`OR` court-circuitants (option `AND`/`OR` à la Wirth-2 ?)
- [ ] Benchmarks officiels VM.Mod natif vs obvm dans le README
- [ ] Documentation : porter `docs/LANGAGE.md` à jour à chaque extension

## 📌 Ordre conseillé

1. Open arrays + NEW/DISPOSE tableaux + conversion int→real (A, dans le stage-0, testés)
2. OC.Mod → bytecode (B), testé via obvm/VM.Mod
3. OC.Mod → C (C), auto-compilation
4. Polish
