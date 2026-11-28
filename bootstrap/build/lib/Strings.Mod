MODULE Strings;
(* String helpers on 0X-terminated char arrays (open array params).
   Convention: every string is an ARRAY OF CHAR terminated by 0X. *)

PROCEDURE Len*(s: ARRAY OF CHAR): INTEGER;
VAR n: INTEGER;
BEGIN
  n := 0;
  WHILE (n < LEN(s, 0)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Len;

PROCEDURE Equal*(a, b: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
  RETURN a[i] = b[i]
END Equal;

(* lexicographic: -1 / 0 / 1 *)
PROCEDURE Compare*(a, b: ARRAY OF CHAR): INTEGER;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
  IF a[i] = b[i] THEN RETURN 0 END;
  IF ORD(a[i]) < ORD(b[i]) THEN RETURN -1 END;
  RETURN 1
END Compare;

(* append src at the end of dst, truncated to dst's capacity *)
PROCEDURE Append*(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i, j, cap: INTEGER;
BEGIN
  cap := LEN(dst, 0);
  i := Len(dst);
  j := 0;
  WHILE (j < LEN(src, 0)) & (src[j] # 0X) & (i < cap - 1) DO
    dst[i] := src[j]; INC(i); INC(j)
  END;
  dst[i] := 0X
END Append;

(* insert src at pos in dst, truncated to dst's capacity *)
PROCEDURE Insert*(VAR dst: ARRAY OF CHAR; pos: INTEGER; src: ARRAY OF CHAR);
VAR i, j, n, cap, slen: INTEGER;
BEGIN
  cap := LEN(dst, 0); n := Len(dst); slen := Len(src);
  IF pos < 0 THEN pos := 0 END;
  IF pos > n THEN pos := n END;
  i := n; (* shift tail right by slen *)
  WHILE i > pos DO
    DEC(i);
    j := i + slen;
    IF j <= cap - 1 THEN dst[j] := dst[i] END
  END;
  j := 0; (* copy src *)
  WHILE (j < slen) & (pos + j <= cap - 1) DO dst[pos + j] := src[j]; INC(j) END;
  i := n + slen; (* new length, capped *)
  IF i > cap - 1 THEN i := cap - 1 END;
  dst[i] := 0X
END Insert;

PROCEDURE IntToStr*(x: INTEGER; VAR dst: ARRAY OF CHAR);
VAR i, n: INTEGER; neg: BOOLEAN; tmp: ARRAY 16 OF CHAR;
BEGIN
  n := 0; neg := x < 0;
  IF neg THEN x := -x END;
  IF x = 0 THEN tmp[0] := '0'; n := 1
  ELSE
    WHILE x > 0 DO tmp[n] := CHR(x MOD 10 + ORD('0')); INC(n); x := x DIV 10 END
  END;
  IF neg THEN tmp[n] := '-'; INC(n) END;
  i := 0; (* reverse into dst *)
  WHILE (n > 0) & (i < LEN(dst, 0) - 1) DO
    DEC(n); dst[i] := tmp[n]; INC(i)
  END;
  dst[i] := 0X
END IntToStr;

(* parse a decimal integer; returns FALSE on bad input *)
PROCEDURE StrToInt*(s: ARRAY OF CHAR; VAR x: INTEGER): BOOLEAN;
VAR i, v: INTEGER; neg: BOOLEAN;
BEGIN
  i := 0; v := 0; neg := FALSE;
  IF (i < LEN(s, 0)) & (s[i] = '-') THEN neg := TRUE; INC(i) END;
  IF (i < LEN(s, 0)) & (s[i] # 0X) THEN
    WHILE (i < LEN(s, 0)) & (s[i] # 0X) DO
      IF (s[i] >= '0') & (s[i] <= '9') THEN
        v := v * 10 + (ORD(s[i]) - ORD('0')); INC(i)
      ELSE RETURN FALSE END
    END;
    IF neg THEN v := -v END;
    x := v; RETURN TRUE
  END;
  RETURN FALSE
END StrToInt;

END Strings.
