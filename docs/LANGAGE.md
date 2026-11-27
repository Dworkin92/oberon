# Référence du langage Oberon-07 (dialecte implémenté)

Ce document décrit **exactement** le langage accepté par `obc` et exécuté par
`obvm` — un sous-ensemble d'Oberon-07 (rapport de Wirth) avec quelques
extensions marquées **(ext)**.

- Compilateur : `obc.exe fichier.Mod [-o fichier.obc]`
- VM : `obvm.exe fichier.obc`
- Les mots-clés sont en **majuscules** et sensibles à la casse (conforme au
  rapport Oberon). Les identificateurs sont sensibles à la casse.

---

## 1. Structure d'un module

```ebnf
Module       = "MODULE" ident ";" [ ImportList ] DeclarationSequence
               [ "BEGIN" StatementSequence ] "END" ident "." .
ImportList   = "IMPORT" Import { "," Import } ";" .
Import       = [ ident ":=" ] ident .        (* alias := nomRéel *)
DeclarationSequence = { "CONST" { ConstDecl } | "TYPE" { TypeDecl }
                      | "VAR" { VarDecl } | ProcedureDecl } .
ConstDecl    = ident [ "*" ] "=" ConstExpression ";" .
TypeDecl     = ident [ "*" | "-" ] "=" Type ";" .
VarDecl      = ident { "," ident } [ "*" ] ":" Type ";" .
ProcedureDecl= "PROCEDURE" ident [ "*" ] [ FormalParameters ] [ ":" Type ] ";"
               DeclarationSequence [ "BEGIN" StatementSequence ] "END" [ ident ] ";" .
FormalParameters = "(" [ FPSection { ";" FPSection } ] ")" .
FPSection    = [ "VAR" ] ident { "," ident } ":" Type .
```

**Open arrays (paramètres formels)** : dans une liste de paramètres, `ARRAY OF T`
déclare un *open array* (tableau ouvert) : l'argument peut être n'importe quel
`ARRAY ... OF T`, de n'importe quelle taille ; `LEN(a, 0)` retourne la taille réelle
passée. `VAR a: ARRAY OF T` passe par référence (écriture possible). Un littéral
chaîne est accepté comme `ARRAY OF CHAR` (paramètre valeur). Exemple :
`examples/OpenArr.Mod`, et `MathLib.SumArr*(a: ARRAY OF INTEGER)` appelé depuis
un autre module (`UseMath.Mod`).

- `*` après un nom = **exporté** (visible des modules qui importent).
- Le corps `BEGIN ... END` est exécuté au chargement du module (proc 0 du bytecode).
- **Procédures fonction (ext)** : `PROCEDURE F(x: INTEGER): INTEGER; ... RETURN expr END F;`
  (dans Oberon-07 strict, `RETURN` n'a pas d'expression).

## 2. Types

| Type | Description | Taille / représentation VM |
|---|---|---|
| `INTEGER` | entier signé 32 bits (wraparound) | cellule 64 bits, tronqué à 32 bits |
| `LONGINT` **(ext)** | entier signé 64 bits | cellule 64 bits |
| `REAL` | double précision IEEE | 8 octets |
| `BOOLEAN` | `TRUE` / `FALSE` | 0/1 |
| `CHAR` | point de code | entier |
| `SET` | ensemble de 0..31 | masque 32 bits |
| `ARRAY d1, d2, ... OF T` | tableau multidimensionnel (row-major) | objet heap avec en-tête |
| `RECORD (Base) champs END` | record avec extension optionnelle | objet heap, tag de type |
| `POINTER TO Record` | pointeur vers record (`NIL` = 0) | référence heap |
| `PROCEDURE (params) [: T]` **(ext)** | type procédural (variable de procédure) | cellule taguée `0x03` : [tag][gid module][index proc] |

Déclarations de types :

```ebnf
Type = "ARRAY" ConstExpr { "," ConstExpr } "OF" Type
     | "RECORD" [ "(" qualident ")" ] [ FieldList ] "END"
     | "POINTER" "TO" ident          (* référence avant possible *)
     | "PROCEDURE" [ Formals ] [ ":" Type ]   (* type procédural, ext *)
     | qualident .
FieldList = [ ident { "," ident } ":" Type { ";" ident { "," ident } ":" Type } ] .
```

Règles :
- `POINTER TO Node` avant la déclaration de `Node` est accepté (listes chaînées).
- **Variables record en ligne** : `VAR pt: Point;` est accepté (le record occupe `payload` cellules
  en ligne dans la frame / le segment global) ; accès champs `pt.x`, assignation `q := pt`,
  passage en **`VAR` record param** (`PROCEDURE P(VAR p: Point)` — l'argument effectif peut être
  une variable record, `p^`, ou un élément `a[i]` d'un `ARRAY OF Record`). Les **paramètres record
  valeur** sont refusés (utiliser `VAR`).
- **`ARRAY OF Record`** supporté : les éléments record sont stockés en ligne dans l'objet heap
  (taille = `total × payload`, index converti en cellules), `a[i].x`, `a[i] := a[j]`,
  `NEW`/`DISPOSE` sur `POINTER TO ARRAY n OF Record`.
- **Types procéduraux (ext)** : `TYPE Op = PROCEDURE (x, y: INTEGER): INTEGER;` puis
  `VAR f: Op;` — on assigne une procédure de **signature identique** (mêmes types de
  paramètres, mêmes marques `VAR`, même type de résultat) : `f := Add;` (ou `f := M.Add`),
  on copie (`g := f`), on compare à `NIL` (`f = NIL`, `f # NIL`), on appelle indirectement
  `f(3, 4)` (statement ou expression si la signature a un résultat), on passe une procédure
  comme argument là où le paramètre formel est de type procédural, et on peut `RETURN` une
  procédure. Appeler une variable `NIL` → erreur d'exécution « call of NIL procedure ».
  - **Closures (ext)** : une procédure **imbriquée** mise dans une variable capture son
    environnement : à `f := P` (P imbriquée), la chaîne des frames englobantes est copiée
    dans un objet heap (`CLOSURE_TAG`), et chaque appel reconstruit ces frames sur la pile
    puis les réécrit à la sortie (`RETURN`) — l'état capturé est donc persistant et partagé :
    `PROCEDURE MakeCounter(): Maker; VAR c: INTEGER; PROCEDURE Next(...): ...; BEGIN c := 0; RETURN Next END`
    donne un compteur fonctionnel. `OP_PROCVAL` a 3 opérandes (lmod, proc, steps) :
    `steps = 0xFFFFFFFF` → valeur simple taguée `0x03` (proc de niveau module) ;
    sinon snapshot de la chaîne de `steps` liens statiques.

### Assignabilité

- types identiques ; `NIL` → tout pointeur **et toute variable procédurale** ;
- littéral chaîne → `ARRAY OF CHAR` de taille suffisante ;
- `INTEGER` → `LONGINT` (promotion, **(ext)**) ;
- pointeur dérivé → pointeur de base (extension de record) ;
- type procédural : égalité **structurelle** de signature (paramètres et résultat), ou `NIL`.

## 3. Expressions

```ebnf
Expression   = SimpleExpr [ Relation SimpleExpr ] .
Relation     = "=" | "#" | "<" | "<=" | ">" | ">=" | "IN" | "IS" .
SimpleExpr   = [ "+" | "-" ] Term { ("+" | "-" | "OR") Term } .
Term         = Factor { ("*" | "/" | "DIV" | "MOD" | "&") Factor } .
Factor       = number | string | char | "TRUE" | "FALSE" | "NIL"
             | Designator [ "(" Type ")" ]      (* garde de type p(T) *)
             | "(" Expression ")" | "~" Factor
             | Call                              (* procédure fonction (ext) *)
             | "{" [ SetElement { "," SetElement } ] "}" .
SetElement   = SimpleExpr [ ".." SimpleExpr ] .  (* bornes dynamiques OK (ext) *)
Designator   = qualident { "." ident | "[" ExprList "]" | "^" | "(" Type ")" } .
ExprList     = Expression { "," Expression } .
```

Sémantique des opérateurs :

| Opérateur | Types | Sémantique |
|---|---|---|
| `+ - *` | INT/LONGINT/REAL | arithmétique ; `INTEGER`+`LONGINT` → `LONGINT` ; **mixte `INTEGER`/`REAL` → `REAL` (ext)** |
| `+ - *` | SET | union / différence / intersection |
| `/` | INT/REAL | division réelle ; **les opérandes `INTEGER` sont convertis en `REAL` (ext)**, donc `7/2 = 3.5` |
| `DIV MOD` | INT/LONGINT | **division euclidienne vers −∞** : `q = a DIV b`, `r = a MOD b`, `r` du signe de `b`, `a = q*b + r` |
| `& OR ~` | BOOLEAN | et / ou / non (évaluation non court-circuitante) |
| `= #` | nombres, CHAR, BOOLEAN, SET, pointeurs | égalité |
| `< <= > >=` | INT, LONGINT, REAL, CHAR | comparaison |
| `IN` | `x IN s` : x entier/char, s SET | test d'appartenance (0..31) |
| `IS` | `p IS T` | test de type (T = record ou pointeur vers record) |
| `p(T)` | garde | avorte l'exécution si le test échoue |

### Littéraux

- entiers : `123`, hexadécimal `0FFH`, caractère hex `41X` ;
- **(ext)** un littéral entier hors plage 32 bits devient `LONGINT` ;
- réels : `3.14`, `1E3`, `2.5E-2` (point obligatoire avant `E`) ;
- chaînes : `"abc"` (`""` = guillemet littéral) ;
- **(ext)** caractères : `'a'` accepté en plus de `97X`.

## 4. Statements

```ebnf
StatementSequence = [ Statement { ";" Statement } ] .
Statement = [ Designator ( ":=" Expression | [ "(" [ ExprList ] ")" ] )  (* appel sans () si 0 param (ext) *)
           | "IF" Expression "THEN" StatementSequence { "ELSIF" Expression "THEN" StatementSequence }
             [ "ELSE" StatementSequence ] "END"
           | "CASE" Expression "OF" Case { "|" Case } [ "ELSE" StatementSequence ] "END"
           | "WHILE" Expression "DO" StatementSequence { "ELSIF" Expression "DO" StatementSequence } "END"
           | "REPEAT" StatementSequence "UNTIL" Expression
           | "FOR" ident ":=" Expression "TO" Expression [ "BY" ConstExpr ] "DO" StatementSequence "END"
           | "WITH" Guard { "," Guard } "DO" StatementSequence "END"   (* ext *)
           | "RETURN" [ Expression ] ] .
Guard = ident ":" QualType .   (* la variable doit être POINTER TO Record ; le type de garde
                                  doit être le pointé ou une extension ; check runtime (CHECKTYPE) *)
Case = Label { "," Label } ":" StatementSequence .
Label = ConstExpr [ ".." ConstExpr ] | QualType   (* CASE de type si le sélecteur est POINTER TO RECORD *)
```

- `CASE` sur `INTEGER`/`CHAR` : étiquettes = constantes ou plages `a..b` (table de saut `OP_JUMPTABLE` si dense).
- `CASE` de type (Oberon-07, remplace `WITH` retiré du langage) : sélecteur `POINTER TO RECORD`,
  étiquettes = types (record ou pointeur). Runtime : `p IS Tj` dans l'ordre (chaîne d'extension),
  puis `CHECKTYPE` ; dans une branche, le sélecteur a **statiquement** le type de l'étiquette
  (narrowing) — ex. `CASE sh OF Circle: ... sh.r ... END`.
- `WHILE ... {ELSIF ...} END` (Oberon-07) : boucle gardée, forme de Dijkstra — à chaque itération,
  la première garde vraie est exécutée puis on reboucle ; sortie quand toutes les gardes sont fausses.
  Remplace `LOOP...EXIT` (Oberon-2, retiré d'Oberon-07).
- `FOR` : variable de contrôle `INTEGER`, `LONGINT` **(ext)** ou `CHAR` ; `BY` = constante non nulle
  (négative = boucle descendante). La borne `TO` est évaluée une fois.
- `RETURN expr` uniquement dans une procédure fonction.

## 5. Procédures prédéfinies

| Nom | Signature | Sémantique |
|---|---|---|
| `ABS(x)` | INT/LONGINT/REAL → idem | valeur absolue |
| `ODD(x)` | INT/LONGINT → BOOLEAN | `x` impair |
| `LEN(a [, d])` | ARRAY → INTEGER | longueur de la dimension `d` (0 par défaut) |
| `ORD(c)` | CHAR → INTEGER | code du caractère |
| `CAP(c)` | CHAR → CHAR | majuscule (`'a'..'z'` → `'A'..'Z'`, sinon inchangé) |
| `CHR(i)` | INTEGER → CHAR | caractère de code `i` |
| `ENTIER(x)` | REAL → INTEGER | troncature vers zéro |
| `FLOOR(x)` | REAL → INTEGER | **(ext)** partie entière vers −∞ |
| `INC(x [, n])` / `DEC(x [, n])` | VAR INTEGER | `x := x ± n` (n = 1 par défaut) |
| `INCL(s, e)` / `EXCL(s, e)` | VAR SET, INTEGER | `s := s + {e}` / `s - {e}` |
| `COPY(x, y)` | char arrays | copie `x` dans `y` |
| `NEW(p)` | VAR POINTER TO Record **ou** POINTER TO `ARRAY n OF T` **(ext)** | alloue le record / le tableau (tas avec free-list) |
| `DISPOSE(p)` | VAR POINTER (record ou tableau) **(ext)** | libère l'objet (free-list, first-fit avec découpe) et fait `p := NIL` ; `DISPOSE` sur `NIL` est un no-op |
| `HALT(n)` | INTEGER | termine la VM avec code de sortie `n` |

## 6. Modules prédéfinis (builtins)

### `Out` — sortie standard
`Out.Int(x, w)`, `Out.Real(x, w)`, `Out.Char(c)`, `Out.String(s)`,
`Out.Long(x, w)` **(ext, LONGINT)**, `Out.Byte(b)` **(ext, octet brut)**,
`Out.Ln` (appel aussi accepté sans parenthèses).

### `In` — entrée standard
`In.Int(VAR x)`, `In.Real(VAR x)`, `In.Char(VAR c)`, `In.Line(VAR s: ARRAY OF CHAR)`,
`In.Byte(VAR b)` **(ext)** : octet brut, `b = -1` à la fin de l'entrée.

### `Files` — fichiers **(ext)**
```oberon
TYPE File = POINTER TO FileDesc; (* opaque *)
PROCEDURE Open(name: ARRAY OF CHAR): File;        (* lecture, NIL si absent *)
PROCEDURE Create(name: ARRAY OF CHAR): File;      (* écriture (tronque) *)
PROCEDURE Close(f: File);
PROCEDURE ReadByte(f: File): INTEGER;              (* 0..255, -1 à la fin *)
PROCEDURE WriteByte(f: File; b: INTEGER);
PROCEDURE Read(f: File; buf: ARRAY OF CHAR; len: INTEGER): INTEGER;  (* nb lus *)
PROCEDURE Write(f: File; buf: ARRAY OF CHAR; len: INTEGER);
PROCEDURE Eof(f: File): BOOLEAN;
PROCEDURE Length(f: File): LONGINT;
PROCEDURE Pos(f: File): LONGINT;
PROCEDURE Set(f: File; pos: LONGINT);
PROCEDURE Delete(name: ARRAY OF CHAR): BOOLEAN;
PROCEDURE Exists(name: ARRAY OF CHAR): BOOLEAN;
```
`buf` accepte aussi un littéral chaîne pour `Write`. Les tableaux de `CHAR`
stockent un caractère par cellule de 8 octets (les échanges avec les fichiers
sont faits octet par octet côté VM).

### `SYSTEM` — interface bas niveau avec l'OS **(ext)**

```oberon
PROCEDURE BAND(a, b: LONGINT): LONGINT;          (* ET bit à bit *)
PROCEDURE BOR(a, b: LONGINT): LONGINT;           (* OU bit à bit *)
PROCEDURE BXOR(a, b: LONGINT): LONGINT;          (* OU exclusif bit à bit *)
PROCEDURE BNOT(a: LONGINT): LONGINT;             (* complément à 1 *)
PROCEDURE LSH(x: LONGINT; n: LONGINT): LONGINT;  (* décalage gauche si n >= 0, droit logique si n < 0 *)
PROCEDURE ROT(x: LONGINT; n: LONGINT): LONGINT;  (* rotation gauche de n mod 64 (n < 0 -> droite) *)
PROCEDURE BIT(x: LONGINT; n: LONGINT): BOOLEAN;  (* bit n de x *)
PROCEDURE ARGC: INTEGER;                         (* nb d'arguments programme (après le .obc) *)
PROCEDURE ARGV(i: INTEGER; VAR s: ARRAY OF CHAR); (* copie l'argument i dans s *)
PROCEDURE TICKS: LONGINT;                        (* horloge en millisecondes *)
PROCEDURE EXIT(code: INTEGER);                   (* termine avec ce code de retour *)
```

`ARGC` et `TICKS` sont aussi appelables sans parenthèses (`SYSTEM.ARGC`).
Les arguments programme sont ceux passés à `obvm` après le fichier `.obc`
(ex. `obvm prog.obc alpha 42` → `ARGC = 2`, `ARGV(0, s)` donne `"alpha"`) ;
`ARGV` tronque à la capacité du tableau et termine par `0X`.
Conçu pour la VM auto-hébergée (`VM.Mod`, voir `docs/AUTOHEBERGEMENT.md`) :
décoder opcodes et adresses taggées, récupérer le `.obc` à exécuter, profiler.

### `SQLite` — base de données embarquée **(ext, builtin ids 60–70)**

L'amalgamation officielle de SQLite est vendue dans `bootstrap/ext/sqlite/`
(`sqlite3.c`/`sqlite3.h`, compilée une fois en `sqlite3.o` et **linkée statiquement** —
aucune dépendance à une DLL au runtime, les exécutables restent autonomes).
Pas de callback C→Oberon : on utilise la boucle `Prepare`/`Step`/`Column*`
(`Exec` sans callback pour les ordres sans résultat).

```oberon
TYPE DB = LONGINT; Stmt = LONGINT;   (* handles sqlite3* / sqlite3_stmt* *)
PROCEDURE Open(path: ARRAY OF CHAR; VAR db: DB): INTEGER;   (* 0 = SQLITE_OK ; ":memory:" = en RAM *)
PROCEDURE Close(VAR db: DB);                                 (* ferme et remet db à 0 *)
PROCEDURE Exec(db: DB; sql: ARRAY OF CHAR): INTEGER;         (* ordres sans résultat *)
PROCEDURE Prepare(db: DB; sql: ARRAY OF CHAR; VAR st: Stmt): INTEGER;
PROCEDURE Step(st: Stmt): INTEGER;                           (* 100 = ROW, 101 = DONE *)
PROCEDURE ColumnInt(st: Stmt; i: INTEGER): LONGINT;
PROCEDURE ColumnText(st: Stmt; i: INTEGER; VAR buf: ARRAY OF CHAR);
PROCEDURE ColumnDouble(st: Stmt; i: INTEGER): REAL;
PROCEDURE ColumnCount(st: Stmt): INTEGER;
PROCEDURE Finalize(st: Stmt);
PROCEDURE Errmsg(db: DB; VAR buf: ARRAY OF CHAR);
```
Voir `examples/SqlDemo.Mod`. Les chaînes Oberon (un `CHAR` par cellule) sont
converties en `char*` NUL côté C par le builtin.

## 7. Lexique

- **Commentaires** : `(* ... *)`, imbriqués.
- **Identificateurs** : lettre ou `_`, puis lettres/chiffres/`_` ; max 63 caractères significatifs.
- **Mots-clés** (majuscules, réservés) : `ARRAY BEGIN BY CASE CONST DIV DO ELSE ELSIF END
  FOR IF IMPORT IN IS MOD MODULE NIL OF OR POINTER PROCEDURE RECORD REPEAT RETURN THEN
  TO TYPE UNTIL VAR WHILE WITH`.
- `HALT`, `TRUE`, `FALSE`, `ABS`... sont des **identificateurs prédéfinis**, pas des mots-clés.

## 8. Extensions au Oberon-07 strict (récapitulatif)

1. `LONGINT` (64 bits) + promotion `INTEGER` → `LONGINT` + littéraux larges auto-`LONGINT`.
2. Procédures fonction `PROCEDURE F(...): T` + `RETURN expr`.
3. Littéraux caractère `'a'` (en plus de `97X`).
4. Appel de procédure sans paramètres sans parenthèses : `Out.Ln`.
5. `FLOOR`, `Out.Long`, `Out.Byte`, `In.Byte`.
6. Module `Files`.
7. Constructeurs d'ensembles avec bornes dynamiques `{x..y}`.
8. `FOR` sur `LONGINT` et `CHAR`.
9. Module `SYSTEM` : opérateurs bit à bit 64 bits (`BAND/BOR/BXOR/BNOT/LSH/ROT/BIT`),
   arguments programme (`ARGC/ARGV`), horloge (`TICKS`), sortie (`EXIT`), et casts
   `L2I` (LONGINT→INTEGER), `REALBITS` (REAL→bits), `BITSREAL` (bits→REAL), `I2REAL`
   (INTEGER→REAL) — voir [`AUTOHEBERGEMENT.md`](AUTOHEBERGEMENT.md).
10. **Open arrays** en paramètres formels : `ARRAY OF T` accepte tout tableau de `T`,
    `LEN(a, 0)` = taille réelle ; littéraux chaîne acceptés pour `ARRAY OF CHAR`.
- Pointeurs vers tableaux **(ext)** : `VAR p: POINTER TO ARRAY 100 OF INTEGER` (ou `POINTER TO` un type tableau nommé) ; `NEW(p)` alloue, `p[i]` indexe (déréférencement implicite), `LEN(p, 0)` marche, et `p` est accepté comme argument (valeur ou `VAR`) là où un `ARRAY OF T` ouvert est attendu. `DISPOSE(p)` libère et met `p := NIL`.
11. **Types procéduraux / variables procédurales + closures (ext)** : `TYPE P = PROCEDURE (x: INTEGER): INTEGER; VAR f: P;` — `f := MaProc;`, `f(3)`, `f = NIL`, passage en argument, `RETURN MaProc`. Opcodes `OP_PROCVAL` (88, **3 opérandes u32** : lmod, proc, steps) / `OP_CALLP` (89) ; valeur simple = cellule taguée `0x03` [gid 8 bits][proc 32 bits], closure = objet heap `CLOSURE_TAG` (snapshot des frames capturées + réécriture au retour). C'est la base du **threaded code** de la VM en Oberon.
12. **Casts bit-à-bit (ext)** : `PROCV(x: LONGINT): PROCEDURE()` et `PROCC(p: PROCEDURE()): LONGINT` — identités sans code émis, utiles pour stocker des valeurs procédurales dans des `ARRAY OF LONGINT` (threaded code de `VM.Mod`).

## 9. Limitations connues (v1)

- `DISPOSE` existe avec **free-list** (pas de GC) : un bloc libéré est réutilisé par le prochain `NEW`/`ALLOC_ARRAY` de taille compatible (first-fit avec découpe).
- `WITH p: T DO … END` **(ext)** : `p` (variable `POINTER TO Record`) a le type statique `POINTER TO T` dans le corps, avec vérification de type à l'exécution (`CHECKTYPE`, erreur « type guard failed »). Multi-gardes `WITH a: T, b: U DO … END` supportées.
- Paramètres record **valeur** refusés (utiliser `VAR`) ; `SYSTEM.VAL/ADR/GET/PUT` non implémentés (pas de besoin réel constaté — `PROCV`/`PROCC` couvrent le besoin de casts).
- `SET` limité à 32 éléments ; `CHAR` = point de code (32 bits).
- Conversion implicite `INTEGER` → `REAL` **(ext)** : dans `+ - * /`, les comparaisons, l'assignation, les arguments valeur et `RETURN` — un opérande `INTEGER` est converti (`I2F`) quand l'autre côté est `REAL`. `DIV`/`MOD` restent strictement entiers ; `LONGINT` ne se convertit pas en `REAL` implicitement.
- Le signe unaire n'est autorisé qu'en tête de `SimpleExpr` (donc `7 DIV (-2)`, pas `7 DIV -2`).
- `Out.Real` utilise le format `%g`.
- Les signaux (ex. `SIGINT`) sont gérés par l'hôte C (`obvm`), pas par le langage.
- `&` et `OR` **ne court-circuitent pas** (les deux côtés sont toujours évalués) — utiliser des `IF` imbriqués pour garder un indice valide.
- Le 2e argument de `INC`/`DEC` doit être une **constante** (`INC(x)` OK, `INC(x, n)` avec `n` variable refusé).
- Open arrays uniquement en **paramètres formels** (`ARRAY OF T`) ; ailleurs, les tableaux ont une taille fixe exacte (`VAR a: ARRAY 256 OF CHAR`).
- Pas d'indexation partielle : `t[i]` sur un `ARRAY n, m OF T` exige les deux indices.
- Max 16 identificateurs par déclaration (`VAR a, b, ... : T`).
- `RETURN expr` exige un type strictement égal au type de résultat.
- Bornes de `FOR` : expressions dynamiques OK (évaluées une fois), mais `BY` doit être une constante non nulle.
- Types procéduraux : l'appel indirect `f(args)` n'est reconnu que sur un identificateur
  simple (pas sur `a[i](...)` ou `r.f(...)`). Les closures récursives avec état muté capturé
  voient l'état de la capture au début de l'appel externe (pas d'entrelacement de réécriture).
- Modules importés : pour `IMPORT M` depuis un fichier situé dans le répertoire `D`, on cherche dans l'ordre `D/M.obc`, `D/M.Mod`, puis `D/../lib/…`, puis `D/../../lib/…` (le `lib/` de la racine du projet). Si seul `M.Mod` est trouvé, il est compilé à la volée en `M.obc` à côté du source. Même recherche côté exécution (`obvm`, `ob2c`, `VM.Mod`). Voir `lib/` (`MathLib`, `Strings`).

## 10. Exemple complet

```oberon
MODULE Demo;
IMPORT Out, Files;

TYPE
  NodePtr = POINTER TO Node;
  Node = RECORD value: INTEGER; next: NodePtr END;

VAR head: NodePtr; i: INTEGER;

PROCEDURE Push(v: INTEGER);
VAR n: NodePtr;
BEGIN
  NEW(n); n.value := v; n.next := head; head := n
END Push;

BEGIN
  FOR i := 1 TO 3 DO Push(i * 10) END;
  WHILE head # NIL DO
    Out.Int(head.value, 4);
    head := head.next
  END;
  Out.Ln
END Demo.
```

```sh
obc.exe Demo.Mod && obvm.exe Demo.obc     (* affiche:   30  20  10 *)
```
