program Generator;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  Gen: TGenerator<Integer>;
  Iter: Integer;
  Routine: TSymmetricArgsRoutine;

begin
  Routine := procedure(const Args: array of const)
  var
    Start, Stop, Step, Cur: Integer;

  begin
    Start := Args[0].AsInteger;
    Step  := Args[1].AsInteger;
    Stop  := Args[2].AsInteger;
    Cur := Start;
    while Cur <= Stop do
    begin
      // Here we yield data out of routine context
      TGenerator<Integer>.Yield(Cur);
      Inc(Cur, Step);
    end;
  end;

  Gen := TGenerator<Integer>.Create(Routine, [10, 3, 18]);

  // enum generator values across for-in loop
  for Iter in Gen do
    WriteLn(Format('Iter = %d', [Iter]));

  ReadLn;
end.
