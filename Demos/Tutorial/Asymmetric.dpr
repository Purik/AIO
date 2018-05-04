program Asymmetric;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

  (*
    Arithmetic progression.
  *)

var
  A: TAsymmetric<Integer, Integer, Integer, string>;
  Func: TAsymmetricRoutine<Integer, Integer, Integer, string>;

begin
  Func := function(const Start, Step, Stop: Integer): string
  var
    Cur, Accum: Integer;
  begin
    WriteLn(Format('Input parameters: Start = %d; Step = %d; Stop = %d', [Start, Step, Stop]));
    Cur := Start;
    Accum := Start;

    while Cur <= Stop do
    begin
      WriteLn(Format('Cur = %d', [Cur]));
      Yield;
      Inc(Cur, Step);
      Inc(Accum, Cur)
    end;
    Result := Format('Result = %d', [Accum]);
  end;

  A := TAsymmetric<Integer, Integer, Integer, string>.Create(Func, 10, 3, 17);
  while IRawGreenlet(A).GetState <> gsTerminated do
    IRawGreenlet(A).Switch;
  // if you call GetResult before asymmetric is terminated, exception will be raised
  WriteLn(Format('A.GetResult = "%s"', [A.GetResult]));
  ReadLn;
end.
