MODULE WhileElsif;
IMPORT Out;

(* Oberon-07: WHILE c1 DO S1 {ELSIF c2 DO S2} END — boucle gardée (forme de Dijkstra) :
   à chaque itération, la première garde vraie est exécutée puis on reboucle sur c1 ;
   la boucle sort quand toutes les gardes sont fausses. Remplace LOOP...EXIT d'Oberon-2. *)

VAR x: INTEGER;

BEGIN
  x := 0;
  WHILE x < 5 DO INC(x)
  ELSIF x < 10 DO INC(x, 10)
  END;
  (* trace : x=0..4 -> branche 1, x=5 ; garde1 fausse, garde2 (5<10) vraie -> x=15 ;
     on reboucle : 15<5 faux, 15<10 faux -> sortie. *)
  Out.Int(x, 0); Out.Ln;   (* 15 *)

  x := 100;
  WHILE x < 5 DO INC(x)
  ELSIF x < 10 DO INC(x, 10)
  END;
  Out.Int(x, 0); Out.Ln    (* 100 : aucune garde vraie -> sortie immédiate *)
END WhileElsif.
