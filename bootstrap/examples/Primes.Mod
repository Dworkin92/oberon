MODULE Primes;
IMPORT Out;

CONST N = 100;
VAR sieve: ARRAY N OF BOOLEAN;
    i, j, count: INTEGER;

BEGIN
  FOR i := 0 TO N - 1 DO sieve[i] := TRUE END;
  sieve[0] := FALSE; sieve[1] := FALSE;
  i := 2;
  WHILE i * i < N DO
    IF sieve[i] THEN
      j := i * i;
      WHILE j < N DO
        sieve[j] := FALSE;
        j := j + i
      END
    END;
    INC(i)
  END;
  count := 0;
  FOR i := 2 TO N - 1 DO
    IF sieve[i] THEN
      Out.Int(i, 4);
      INC(count)
    END
  END;
  Out.Ln;
  Out.String("primes below "); Out.Int(N, 3); Out.String(": "); Out.Int(count, 3); Out.Ln
END Primes.
