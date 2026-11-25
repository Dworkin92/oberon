# Feuille de route — auto-hébergement (VM et compilateur écrits en Oberon)

Ce document consigne les décisions de conception pour passer de la chaîne
d'outils C actuelle (**stage-0**) à une VM puis un compilateur écrits en
Oberon eux-mêmes. Pour le dialecte lui-même, voir [`LANGAGE.md`](LANGAGE.md) ;
pour l'architecture du stage-0, voir le `README.md`.

## Vue d'ensemble

```
stage-0 (actuel, C)   obc / obvm / obdis en C — 15 tests au vert
   │
   ├─► étape 1 : module SYSTEM + opérateurs bitwise dans le stage-0
   ├─► étape 2 : computed goto dans la VM C (dispatch rapide)
   ├─► étape 3 : backend C minimal (`ob2c` : .obc → C déroulé, gcc) ✅
   ├─► étape 4 : VM.Mod écrit en Oberon, exécuté par obvm (C) ✅
   ├─► étape 5 : VM.Mod transpilé en C par `ob2c` + gcc ✅
   └─► étape 6 : compilateur écrit en Oberon, émettant directement du C
                 (s'auto-compile : oc.Mod → oc.obc → oc.c → gcc → oc2)
```

L'étape 6 rend le transpiler séparé de l'étape 3 obsolète : un compilateur
qui émet du C directement n'a pas besoin d'un transpiler à côté.
`gcc` reste le substrat final, en bas de la pile.

## 1. Interface avec l'OS : le module `SYSTEM`

> ✅ **Implémenté dans le stage-0** : builtins 40–50 dans `bootstrap/src/vm.c`, module
> `SYSTEM` dans `bootstrap/src/parser.c`, arguments programme via `vmSetArgs`
> (`bootstrap/src/obvm.c` : tout ce qui suit le `.obc` sur la ligne de commande),
> test `bootstrap/examples/SysDemo.Mod` (16 tests au vert).

`VM.Mod` (la VM écrite en Oberon) a besoin de lire des fichiers binaires
(déjà couvert par `Files`), d'écrire sur stdout (`Out`), de lire ses
arguments de ligne de commande, de mesurer le temps, et de manipuler des
bits (décoder les opcodes et les adresses taggées). D'où un petit module
builtin `SYSTEM` :

| Fonction | Sert à | En stage-0 (C) | Après transpilation en C |
|---|---|---|---|
| `SYSTEM.BAND(a, b)`, `SYSTEM.BOR`, `SYSTEM.BXOR`, `SYSTEM.BNOT` (`LONGINT`) | décoder opcode + tag d'adresse, manipuler les en-têtes du tas | builtin C (nouveaux ids) | fonction C / builtin gcc |
| `SYSTEM.LSH(x, n)`, `SYSTEM.ROT(x, n)` (`LONGINT`) | composer/décomposer les adresses taggées (octet de poids fort), parcourir le bytecode | builtin C | fonction C |
| `SYSTEM.BIT(x, n): BOOLEAN` | tester un bit (flags, type d'opcode) | builtin C | fonction C |
| `SYSTEM.ARGC: INTEGER`, `SYSTEM.ARGV(i, VAR s)` | récupérer le `.obc` à exécuter, les arguments du compilateur | builtin C sur `main(argc, argv)` | `main(argc, argv)` |
| `SYSTEM.TICKS: LONGINT` | benchmarks : coût du dispatch, VM Oberon vs VM C | `clock()` | `clock()` |
| `SYSTEM.EXIT(code)` | code de retour propre | `exit(code)` | `exit(code)` |

**Choix délibéré : pas de `GET`/`PUT`/`ADR`/`VAL`.** La mémoire de `VM.Mod`
est un simple `ARRAY OF LONGINT` ; les pointeurs taggés (octet de poids fort)
restent un détail interne du stage-0 C. Surface minimale = moins de risques.
Si un besoin apparaît plus tard, on pourra les rajouter.

**Signaux : gérés par l'hôte, pas par le langage.** `obvm` (C) installera un
handler `SIGINT`/`SIGTERM` → message « interrompu » + `exit(130)`. Aucune
surface dans le dialecte pour l'instant (on verra si `SYSTEM.ONINT` se
justifie à l'usage).

## 2. Dispatch rapide — trois niveaux

1. **VM C (stage-0)** ✅ : *computed goto* de GCC — chaque `case OP_X` est
   doublé d'une étiquette (`OPLABEL(OP_X)` → `L_OP_X`), la table
   `dispatchTab[OP_COUNT]` vit dans `vmRun` (`&&label` n'est autorisé que
   dans la fonction qui définit le label), et la boucle fait
   `goto *dispatchTab[op]` sous `#if defined(__GNUC__) && !defined(OB_NO_COMPUTED_GOTO)`.
   **Mesuré** (`bootstrap/examples/Bench.Mod`, boucle arithmétique 20M itérations,
   `SYSTEM.TICKS`) : **2133 ms en computed goto vs 3067 ms en switch pur**
   (`-DOB_NO_COMPUTED_GOTO`), soit **×1,44 (−31 %)** ; `acc` identique des deux
   côtés, 16 tests au vert. Le `switch` reste le fallback portable.
2. **`VM.Mod` en Oberon** : au chargement, pré-décoder le bytecode en
   `POINTER TO ARRAY OF OpRec`, avec
   `TYPE OpHandler = PROCEDURE (VAR st: State);`
   `OpRec = RECORD h: OpHandler; arg, arg2: LONGINT END`.
   Le dispatch devient `code[pc].h(st)` : un **appel indirect via une
   variable procédurale** — Oberon-07 a les variables procédurales nativement,
   c'est notre *computed goto* à nous ( « threaded code » ). Plus de `CASE`
   géant dans la boucle chaude.
3. **Superinstructions** : le format `.obc` a un champ `version` et les
   opcodes sont **ajoutés en fin d'enum** (comme `OP_AADD` déjà fait) pour
   ne jamais renumber ni réutiliser. Les superinstructions reçoivent donc de
   nouveaux opcodes en fin de liste, et les anciens `.obc` continuent de
   charger.
   - ✅ **`OP_JUMPTABLE` (86)** — première superinstruction, pour le dispatch :
     un `CASE` dense (≥ 8 labels, plage ≤ 1024) compile en `JUMPTABLE n base
     default targets[]` au lieu d'une chaîne de comparaisons. `obvm` saute en
     O(1), `ob2c` émet un vrai `switch` C (jump table gcc). Mesuré sur Queens
     via `VM.Mod` : natif 805 → **523 ms**, sur obvm 1986 → **1183 ms**.
   - Candidats restants (à affiner avec un profiler) :

   | Superinstruction | Sémantique | Gain |
   |---|---|---|
   | `GLOAD_ADD (mod, off)` | `TOS += global[mod, off]` | `x := g + y` en 2 dispatches au lieu de 3 |
   | `LLOAD_ADD off` | `TOS += local[off]` | idem pour les locales |
   | `INC_G (mod, off)` / `INC_L off` | variable `+= 1` en un opcode | `INC(x)` très fréquent |
   | `CALL_STMT (mod, proc, steps)` | appel sans résultat | évite le slot de résultat |
   | `DJNZ off, target` | `local[off] -= 1 ; if ≠ 0 then jump` | spécialise `FOR ... BY -1` et les `WHILE` à compteur |

   Le même jeu d'opcodes devra être émis par le compilateur Oberon de
   l'étape 6 et compris par `obdis` : la source de vérité reste `bootstrap/src/ob.h`
   aujourd'hui, plus tard un module `OP` partagé en Oberon.

## 3. Contrat de stabilité du format `.obc`

- Magic `"OBC7"` + `u32 version` : on bump la version si le format change de
  façon incompatible.
- Opcodes **append-only** : jamais de renumérotation.
- Le loader est partagé compilateur/VM (`bootstrap/src/module.c`) ; le futur compilateur
  Oberon devra lire/écrire ce format depuis Oberon, via `Files` — d'où le
  format documenté en détail dans le `README.md`.

## 4. Plan d'exécution

| Étape | Livrable | Validé par |
|---|---|---|
| 0 ✅ | toolchain C `obc`/`obvm`/`obdis` | `bootstrap/tests/run_tests.sh` |
| 1 ✅ | module `SYSTEM` + opérateurs bitwise + casts dans le stage-0 (builtins 40–54) | `SysDemo` : args, bitwise 64 bits, casts, `TICKS`, `EXIT` |
| 2 ✅ | computed goto dans `vm.c` (`OPLABEL` + `dispatchTab` dans `vmRun`) | 16 tests au vert ; `Bench` : 2133 ms vs 3067 ms en switch (×1,44) |
| 3 ✅ | `ob2c` : `.obc` → C déroulé (une fonction/proc, `goto`, `procTab`), runtime extrait dans `rt.c`, `push/pop` en `static inline` | toute la suite de tests en natif (`PASS-C`, 32/32) ; `Bench` : **587 ms natif vs 2133–2344 ms obvm (×4)** |
| 4 ✅ | `selfhost/VM.Mod` (~700 lignes Oberon) : loader `.obc`, tas/pile/frames, mémoire taggée, builtins guest réimplémentés en Oberon via le `SYSTEM` du host (casts 51–54) | phase `PASS-VM` de la suite : **51/51** (17 exemples × VM / C natif / VM.Mod) ; Queens : 74 ms obvm vs ~2 s VM.Mod-sur-obvm (~27×) |
| 5 ✅ | `VM.Mod` transpilé par `ob2c` + gcc (`vm_native`) | phase `PASS-VMN` : **68/68** (17 ex. × 4 moteurs) ; Queens : 805 ms VM.Mod natif vs 1986 ms VM.Mod-sur-obvm vs 74 ms obvm |
| 6 | compilateur en Oberon émettant du C | il se compile lui-même (`oc.obc` → `oc.c` → gcc → `oc2`), `bootstrap/tests/expected/` comme banc de régression |
