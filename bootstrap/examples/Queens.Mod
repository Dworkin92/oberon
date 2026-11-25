MODULE Queens;
IMPORT Out;

CONST N = 8;
VAR col: ARRAY N OF BOOLEAN;      (* col[i]: column i free *)
    diag1: ARRAY 2 * N - 1 OF BOOLEAN; (* row+col *)
    diag2: ARRAY 2 * N - 1 OF BOOLEAN; (* row-col+N-1 *)
    count: INTEGER;
    row: INTEGER;

PROCEDURE Try(colIdx: INTEGER);
VAR j: INTEGER;
BEGIN
  IF colIdx = N THEN
    INC(count)
  ELSE
    FOR j := 0 TO N - 1 DO
      IF col[j] & diag1[row + j] & diag2[row - j + N - 1] THEN
        col[j] := FALSE; diag1[row + j] := FALSE; diag2[row - j + N - 1] := FALSE;
        INC(row);
        Try(colIdx + 1);
        DEC(row);
        col[j] := TRUE; diag1[row + j] := TRUE; diag2[row - j + N - 1] := TRUE
      END
    END
  END
END Try;

BEGIN
  count := 0; row := 0;
  FOR row := 0 TO N - 1 DO col[row] := TRUE END;
  row := 0;
  FOR row := 0 TO 2 * N - 2 DO diag1[row] := TRUE; diag2[row] := TRUE END;
  row := 0;
  Try(0);
  Out.String("solutions for "); Out.Int(N, 0); Out.String(" queens: "); Out.Int(count, 0); Out.Ln
END Queens.
