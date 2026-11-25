MODULE Echo;
IMPORT Out, In;

VAR n: INTEGER;
    x: REAL;
    name: ARRAY 64 OF CHAR;
    i: INTEGER;

BEGIN
  Out.String("Enter an integer: ");
  In.Int(n);
  Out.String("You entered "); Out.Int(n, 0); Out.String(", square = "); Out.Int(n * n, 0); Out.Ln;
  Out.String("Enter a real: ");
  In.Real(x);
  Out.String("You entered "); Out.Real(x, 10); Out.Ln;
  Out.String("Enter your name: ");
  In.Line(name);
  Out.String("Hello, ");
  i := 0;
  WHILE (i < LEN(name)) & (name[i] # 0X) DO
    Out.Char(name[i]);
    INC(i)
  END;
  Out.String("!"); Out.Ln
END Echo.
