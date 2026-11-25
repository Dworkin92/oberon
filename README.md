# Oberon-07 → Bytecode → VM

Un **compilateur Oberon-07** complet (projet) écrit en C, qui traduit les modules
`.Mod` en **bytecode binaire** (`.obc`), exécuté par sa propre **machine
virtuelle** (`obvm`).

> 📖 **Référence du langage** (grammaire EBNF, types, statements, modules
> `Out`/`In`/`Files`, extensions, limitations) : [`docs/LANGAGE.md`](docs/LANGAGE.md)
>
> 🗺️ **Feuille de route d'auto-hébergement** (module `SYSTEM`, dispatch rapide
> par computed goto / variables procédurales, superinstructions, VM puis
> compilateur écrits en Oberon) : [`docs/AUTOHEBERGEMENT.md`](docs/AUTOHEBERGEMENT.md)

## Arborescence

```
 oberon/
   README.md                ce fichier
   journal.md               journal de bord
   docs/
     LANGAGE.md             référence du dialecte Oberon supporté
     AUTOHEBERGEMENT.md     feuille de route : VM/compilateur auto-hébergés en Oberon
   lib/                     bibliothèque de modules réutilisables (MathLib, Strings, ...)
   bootstrap/               stage-0 : la chaîne d'outils 100 % C
     src/                   obc / obvm / obdis / ob2c + runtime partagé rt.[ch]
     build.sh, Makefile
     examples/              programmes de démo (.Mod)
     tests/                 run_tests.sh + sorties de référence (VM, C natif, VM.Mod)
     obc.exe obvm.exe obdis.exe ob2c.exe
   selfhost/
     VM.Mod                 la VM écrite en Oberon (étape 4), compilée par bootstrap/obc
```

## VM auto-hébergée (`selfhost/VM.Mod`)

La machine virtuelle est réécrite **en Oberon** (`selfhost/VM.Mod`, ~700 lignes) :
elle lit un `.obc`, reconstruit modules/tas/pile/frames et interprète le bytecode,
avec les builtins guest (`Out`/`In`/`Files`/`SYSTEM`) réimplémentés en Oberon via
ceux de l'hôte. Trois façons d'exécuter un programme (toutes testées, 51/51) :

```sh
cd bootstrap
./obvm.exe examples/Queens.obc                    # 1. VM C (stage-0)
./ob2c.exe examples/Queens.obc -o /tmp/Q.c && gcc -O2 -Isrc -o /tmp/q /tmp/Q.c src/rt.c src/ob.c src/model.c src/module.c -lm && /tmp/q examples/Queens.obc   # 2. C natif
./obvm.exe ../selfhost/VM.obc examples/Queens.obc  # 3. VM.Mod (Oberon) tournant sur obvm
# 4. VM.Mod transpilé en C natif (étape 5) : la suite de tests le fait via tests/out/vm_native.exe
```

```
bootstrap/examples/Hello.Mod ──[obc]──> Hello.obc ──[obvm]──> exécution (VM)
                               │        │
                               │        └──[ob2c]──> Hello.c ──[gcc]──> exécution (natif)
                               └──[obdis]──> désassemblage lisible
```

## Outils (depuis `bootstrap/`)

| Outil | Rôle |
|---|---|
| `obc.exe <file.Mod> [-o file.obc]` | Compilateur Oberon-07 → bytecode. Compile récursivement les modules importés (`M.Mod` → `M.obc`) s'ils n'ont pas encore de `.obc`. |
| `obvm.exe <file.obc>` | La VM : charge le module + ses imports, exécute le corps du module. Code de sortie = `HALT(n)`. |
| `obdis.exe <file.obc>` | Désassembleur : tables (types, globales, chaînes, procédures) + code de chaque procédure. |
| `ob2c.exe <file.obc> [-o file.c]` | **Backend C** : transpile le bytecode en C linéaire (une fonction C par procédure, `goto` pour les sauts, table `procTab` pour les appels). Compiler depuis la racine : `gcc -O2 -Ibootstrap/src file.c bootstrap/src/rt.c bootstrap/src/ob.c bootstrap/src/model.c bootstrap/src/module.c -lm` ; exécuter : `./a.out file.obc [args...]`. |

## Backend C natif (`ob2c`)

`ob2c` déroule chaque procédure du `.obc` en **C linéaire** (pile explicite,
`goto L<n>` pour les sauts) ; le `main` généré charge le `.obc` via le runtime
partagé (`rt.c`) puis appelle directement la procédure corps du module — plus
de boucle d'interprétation. La suite de tests valide les deux chemins
(`PASS` = VM, `PASS-C` = natif gcc) : **32/32**.

Benchmark `bootstrap/examples/Bench.Mod` (boucle arithmétique 20M itérations, `SYSTEM.TICKS`) :

| Exécution | Temps |
|---|---|
| `obvm` build switch pur (`-DOB_NO_COMPUTED_GOTO`) | ~3067 ms |
| `obvm` computed goto (défaut) | ~2133–2344 ms |
| **natif `ob2c` + `gcc -O2`** | **~587 ms (×4 vs obvm)** |

## Construction

```sh
cd bootstrap && ./build.sh         # ou: make (dans bootstrap/)
./bootstrap/tests/run_tests.sh     # depuis la racine : compile et exécute tous les exemples (VM + C natif)
```

## Exemple

```oberon
MODULE Hello;
IMPORT Out;
BEGIN
  Out.String("Hello, World!"); Out.Ln
END Hello.
```

```sh
cd bootstrap
./obc.exe examples/Hello.Mod     # compiler le module Oberon et ses dépendances
./obvm.exe examples/Hello.obc    # exécuter le module dans la VM
./obdis.exe examples/Hello.obc   # voir le bytecode
./ob2c.exe examples/Hello.obc -o /tmp/Hello.c && gcc -O2 -Isrc -o /tmp/hello /tmp/Hello.c src/rt.c src/ob.c src/model.c src/module.c -lm && /tmp/hello examples/Hello.obc   # version native C
```
```

## Architecture

```
bootstrap/src/
  ob.h / ob.c      types communs, cellules 64 bits, buffer, opcodes, erreurs
  lexer.[ch]       scanner Oberon (mots-clés en casse exacte, commentaires (* *) imbriqués)
  model.[ch]       types, objets/symboles, tables de portée, assignabilité
  module.[ch]      structure Module + sérialisation binaire .obc (chargeur partagé compilateur/VM)
  parser.[ch]      compilateur "single-pass" façon Wirth : analyse + sémantique + émission de code
  rt.[ch]          runtime partagé : loader, tas, mémoire taggée, pile (push/pop inline), builtins Out/In/Files/SYSTEM
  vm.c             la boucle d'interprétation (dispatch par computed goto)
  obc.c            CLI compilateur
  obvm.c           CLI VM
  obdis.c          CLI désassembleur
  ob2c.c           CLI transpiler .obc -> C (backend natif)
```

### Modèle d'exécution de la VM

- **Cellule = 64 bits** : entier 32 bits, double (REAL), booléen, caractère,
  ensemble (32 bits), ou référence heap (index d'objet, `0` = NIL).
- **Pile de valeurs** + **pile de frames** (base, lien statique, pc, module).
  Les paramètres sont les premiers slots de la frame ; les variables locales
  suivent. L'accès aux variables des procédures englobantes se fait par
  **liens statiques** (champ `steps` de `CALL`).
- **Adressage tagué** (octet de poids fort) : `0x00` = pile, `0x01` = global
  (module, offset), `0x02` = heap. Les paramètres `VAR` passent des adresses
  taguées ; `LOAD_AT`/`STORE_AT` déréférencent.
- **Tas (heap)** : objets avec en-tête. Tableau : `[-ndim, dim0..dimN, total, données...]` ;
  record : `[tag, taille, champs...]` (tag = type runtime, pour `IS`/guard).
  `NEW` alloue un record. Pas de GC (v1).
- **Modules** : chaque module a son segment de globales ; les accès inter-modules
  passent par une table de mapping (id local → id global) résolue au chargement.
- **Dispatch** : *computed goto* (`&&label`, extension GCC) sous `__GNUC__`, sinon
  `switch` — mesuré ~×1,44 plus rapide sur `bootstrap/examples/Bench.Mod` (20M itérations,
  `SYSTEM.TICKS`) ; `-DOB_NO_COMPUTED_GOTO` permet de recompiler le `switch` pour comparer.

### Jeu d'instructions de la VM (extraits)

| Catégorie | Opcodes |
|---|---|
| Constantes | `CONST_I`, `CONST_R`, `CONST_S` (pool de chaînes) |
| Variables | `LOAD/STORE/ADDR_LOCAL` (ld, off), `LOAD/STORE/ADDR_GLOBAL` (mod, off), `LOAD_AT`, `STORE_AT`, `TO_ADDR`, `AADD` (adressage 64 bits) |
| Arithmétique | `IADD ISUB IMUL IDIV IMOD INEG IABS IODD`, `FADD FSUB FMUL FDIV FNEG FABS FFLOOR`, `I2F F2I` (DIV/MOD arrondis vers −∞, conforme Oberon) |
| Comparaisons | `ILT..INE` (entiers), `FLT..FNE` (réels), `EQ NE` (générique), `AND OR NOT` |
| Ensembles | `SET_UNION SET_DIFF SET_INTER SET_MEMBER` (`IN`), `SHL/SHR` (INCL/EXCL) |
| Contrôle | `JMP JZ JNZ`, `CALL mod proc steps`, `RET`, `DUP DROP SWAP`, `JUMPTABLE` (superinstruction : `CASE` dense → saut O(1) via table, jump table gcc en natif) |
| Objets | `NEW`, `ALLOC_ARRAY`, `ELEM_ADDR`, `LEN`, `ISTYPE`, `CHECKTYPE`, `COPY`, `COPY_STR` |

Détail complet : `bootstrap/src/ob.h` (enum des opcodes) et `obdis.exe` pour les voir en clair.

### Format `.obc` (binaire, little-endian)

```
"OBC7" | u32 version=1 | str nomModule
| u32 nimports, str imports...
| u32 globalSize | u32 nGlobals, par globale: str nom, u32 offset, u32 typeIdx, u8 exported
| u32 nTypes, par type: u8 kind, str nom, u8 exported,
    ARRAY: u32 ndim, u32 dims[], u32 elemIdx
    RECORD: u32 payload, u32 baseIdx(-1), u32 nFields, (str nom, u32 typeIdx, u32 offset)...
    POINTER: u32 toIdx
| u32 nProcs, par proc: str nom, u8 exported, u8 isBody, u32 nParams,
    (str nom, u32 typeIdx, u8 isVar)... , u32 nlocals, u8 hasResult, u32 resultTypeIdx,
    u32 codeLen, octets code
| u32 nStrings, str...
```
(`str` = u32 longueur + octets. La proc 0 est toujours le corps du module.)

## Sous-ensemble Oberon-07 supporté

- Modules, `IMPORT` (avec alias `A := M`), déclarations `CONST`/`TYPE`/`VAR`/procédures, corps `BEGIN ... END`.
- Types : `INTEGER` `REAL` `BOOLEAN` `CHAR` `SET` `LONGINT` (64 bits), `ARRAY n, m OF T` (multidimensionnel), `RECORD (Base) ... END` avec extension, `POINTER TO Record` (références avant déclarées OK).
  - Extensions : `LONGINT` (littéral entier hors plage 32 bits devient automatiquement `LONGINT`, `INTEGER` se promeut en `LONGINT` dans les expressions et à l'assignation) ; I/O octet brut `Out.Byte(b)` / `In.Byte(VAR b)` (b = -1 à la fin d'entrée) — la VM passe stdin/stdout en mode binaire.
  - Module **`Files`** (builtin) pour les fichiers binaires/texte :
    `File` (handle opaque), `Open(name): File`, `Create(name): File`, `Close(f)`,
    `ReadByte(f): INTEGER` (-1 à la fin), `WriteByte(f, b)`,
    `Read(f, buf, len): INTEGER`, `Write(f, buf, len)` (buf = `ARRAY OF CHAR` ou littéral chaîne),
    `Eof(f): BOOLEAN`, `Length(f): LONGINT`, `Pos(f): LONGINT`, `Set(f, pos)`,
    `Delete(name): BOOLEAN`, `Exists(name): BOOLEAN`.
- Procédures imbriquées, récursion, paramètres valeur et `VAR`, **procédures fonction** (extension : `PROCEDURE F(...): T` + `RETURN expr`).
- Statements : assignation, appel, `IF/ELSIF/ELSE`, `CASE` (int ou char, plages `a..b`), `WHILE`, `REPEAT/UNTIL`, `FOR ... TO ... BY`, `RETURN`.
- Expressions : arithmétique, comparaisons, `IN`, `IS`, gardes de type `p(T)`, `~`, ensembles `{1, 2..5}`, littéraux chaîne `"..."` et caractère `'c'` (extension) / `41X`.
- Prédéfinis : `ABS ODD LEN ORD CHR ENTIER FLOOR INC DEC INCL EXCL COPY NEW HALT`, modules `Out` (`Int Real Char String Long Byte Ln`), `In` (`Int Real Char Line Byte`) et `SYSTEM` (`BAND BOR BXOR BNOT LSH ROT BIT ARGC ARGV TICKS EXIT` — interface OS bas niveau, voir [`docs/AUTOHEBERGEMENT.md`](docs/AUTOHEBERGEMENT.md)).
- Mots-clés en **majuscules** (conforme au rapport Oberon), commentaires `(* ... *)` imbriqués.

### Limitations (v1)

- Pas de `WITH`, pas de `DISPOSE`, pas de GC (`NEW` n'est jamais libéré).
- Records uniquement via pointeurs (`VAR r: Rec` est refusé ; utiliser `POINTER TO Rec` + `NEW`).
- Tableaux d'éléments scalaires/pointeurs uniquement (pas de `ARRAY OF Record` en ligne).
- Open arrays (`ARRAY OF T`) uniquement en paramètres formels ; `LEN(a, 0)` donne la taille réelle passée (ex. `bootstrap/examples/OpenArr.Mod`).
- `INTEGER` = 32 bits, `LONGINT` = 64 bits, `SET` = 32 éléments, `CHAR` = point de code.
- `Out.Real` utilise le format `%g`.
- Prévu pour la suite (voir [`docs/AUTOHEBERGEMENT.md`](docs/AUTOHEBERGEMENT.md)) : `LONGINT` + le module `Files` (et bientôt `SYSTEM`) suffisent à lire/écrire des `.obc` depuis un programme Oberon.

## Bibliothèque (`lib/`)

Modules réutilisables importables depuis n'importe quel programme. **Chemin de recherche** de `IMPORT M` (dans l'ordre) :
1. `M.obc` puis `M.Mod` dans le répertoire du fichier qui importe ;
2. idem dans `<dir>/../lib` ;
3. idem dans `<dir>/../../lib` (le `lib/` de la racine du projet — couvre `bootstrap/examples/` et `selfhost/`).

Si seul `M.Mod` est trouvé, il est compilé à la volée en `M.obc` à côté du source. La même recherche est faite par le compilateur (`obc`), la VM C (`obvm`), `ob2c` et la VM en Oberon (`VM.Mod`). Contenu actuel : `MathLib` (math + `SumArr` sur tableau ouvert), `Strings` (chaînes 0X-terminées : `Len/Equal/Compare/Append/Insert/IntToStr/StrToInt`), demo dans `bootstrap/examples/StringsDemo.Mod`.

## Exemples (`bootstrap/examples/`)

`Hello`, `Factorial` (récursion), `Arrays` (tri à bulles, tableau 2D, `LEN`), `Records` (listes chaînées, `NEW`, extension de record, `IS`/garde), `Sets` (`INCL/EXCL/IN/opérations`), `Control` (`WHILE/REPEAT/FOR BY/CASE`), `UseMath` + `MathLib` (import, symboles exportés `*`, variable globale exportée), `Nested` (procédures imbriquées + liens statiques + `VAR`), `Primes` (crible), `Echo` (entrée clavier), `Sem` (sémantique DIV/MOD/ENTIER/FLOOR/chaînes/HALT), `Longint` (64 bits), `Bytes` (I/O octet brut), `FilesDemo` (module `Files` : créer/écrire/lire/seek/supprimer un fichier binaire), `SysDemo` (module `SYSTEM` : arguments programme `ARGC/ARGV`, opérateurs bit à bit 64 bits `BAND/BOR/BXOR/BNOT/LSH/ROT/BIT`, horloge `TICKS`), `StringsDemo` (bibliothèque `lib/Strings`), `UseMath` importe `MathLib` via `lib/`.
