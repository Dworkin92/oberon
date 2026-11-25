# TODO — compilateur Oberon auto-hébergé

État au 25/11/2026 : étapes 0–5 faites, **76/76 tests** (19 exemples × 4 moteurs :
`obvm` C, natif `ob2c`+gcc, `VM.Mod` sur obvm, `VM.Mod` natif). Voir
[`docs/AUTOHEBERGEMENT.md`](docs/AUTOHEBERGEMENT.md) pour la vision d'ensemble.

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

### A. Fondations langage manquantes (dans le stage-0 d'abord)

- [x] **Open arrays** : `PROCEDURE P(VAR a: ARRAY OF CHAR)` (paramètre de taille dynamique, `LEN(a,0)` = taille réelle passée) — fait : flag `isOpen` sur `Type`, sentinelle `0xFFFFFFFF` dans le `.obc`, tests `OpenArr.Mod` + `MathLib.SumArr` (72/72)
- [x] **Bibliothèque `lib/`** : `MathLib` déplacé, `Strings` ajouté, chemin de recherche `D/`, `D/../lib/`, `D/../../lib/` dans obc/obvm/ob2c/VM.Mod (76/76)
- [ ] **`NEW(p)` sur `POINTER TO ARRAY OF T` + `DISPOSE`** (free-list, pas forcément GC) — mémoire dynamique
- [ ] **Conversion implicite `INTEGER` → `REAL`** (émettre `I2F` dans le parser quand un opérande est REAL)
- [ ] `WITH` (confort, contournable avec gardes `p(T)`)
- [ ] Types procéduraux / variables procédurales (threaded code dans `VM.Mod`)
- [ ] `VAR` record params, `ARRAY OF RECORD`
- [ ] `SYSTEM.VAL/ADR/GET/PUT` (à rouvrir seulement si besoin réel)

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
