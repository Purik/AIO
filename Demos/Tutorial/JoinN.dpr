program JoinN;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  Routine: TSymmetricRoutine<Integer, Boolean>;

begin
  Routine := procedure(const Counter: Integer; const RaiseAbort: Boolean)
  var
    I: Integer;
  begin
    for I := 1 to Counter do
      Yield;
    if RaiseAbort then
      Abort;
  end;

  try
    // exception raised in greenlets will be reraised to caller context
    Join([
      TSymmetric<Integer, Boolean>.Spawn(Routine, 100, False),
      TSymmetric<Integer, Boolean>.Spawn(Routine, 1000, False),
      TSymmetric<Integer, Boolean>.Spawn(Routine, 10000, True)
    ], INFINITE, True)
  except on E: Exception do
    WriteLn(Format('Exception %s was raised', [E.ClassName]))
  end;

  ReadLn;
end.
