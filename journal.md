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
- open arrays (ARRAY OF T en paramètre formel) : flag isOpen sur Type, "ARRAY OF T" parsé seulement dans les FPSection, LEN(a,0) = taille réelle, littéral chaîne accepté pour ARRAY OF CHAR valeur, VAR open = par référence, sérialisation .obc via sentinelle ndim=0xFFFFFFFF (VM.Mod mis à jour). Tests : OpenArr.Mod + MathLib.SumArr inter-modules. 72/72 (18 ex x 4 moteurs).
- répertoire `lib/` à la racine (nomenclature type "Lib" de Python) : `MathLib.Mod` déplacé depuis bootstrap/examples, nouveau `lib/Strings.Mod` (Len/Equal/Compare/Append/Insert/IntToStr/StrToInt sur chaînes 0X), démo `examples/StringsDemo.Mod`. Chemin de recherche des imports, dans obc ET obvm ET ob2c ET VM.Mod : `D/M.obc`, `D/M.Mod`, `D/../lib/…`, `D/../../lib/…` (couvre bootstrap/examples et selfhost vers la racine). Helper C partagé `findModuleFile()` dans module.c ; `run_tests.sh` nettoie `../lib/*.obc` et enregistre StringsDemo. 76/76 (19 ex × 4 moteurs).
- deux vrais bugs attrapés par StringsDemo :
  - `Type.visited` (garde de récursion de registerTypeDeep) fuirait entre compilations de modules dans le même process obc (compilation imbriquée d'import) → les types de base (CHAR…) n'étaient pas ré-enregistrés dans le .obc du module importateur, `elem=3` pointait hors table, "truncated .obc string". Corrigé par un stamp `gTypeStamp` incrémenté à chaque writeModule.
  - `ADDR_GLOBAL` étiquetait l'adresse avec l'index d'import LOCAL du module créateur, mais `memRead` résolvait via `cur->map` du module EN COURS d'exécution → une adresse globale passée en VAR à un autre module lisait les globales du mauvais module ("LEN of nil" dans Strings.Append). L'adresse stocke maintenant le gid absolu (résolu à la création) ; idem dans VM.Mod (OP_ADDR_GLOBAL, MemRead, MemWrite) ; garde 256 modules (gid sur 1 octet).
  - bug de Strings.Insert : terminateur posé à pos+slen au lieu de n+slen → tronquait la fin ("Oberon!" au lieu de "Oberon!-07").
