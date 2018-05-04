program SelectN;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  Routine: TSymmetricRoutine<Integer>;
  Index: Integer;

begin

  Routine := procedure(const Timeout: Integer)
  begin
    GreenSleep(Timeout);
  end;

  Greenlets.Select([
    TSymmetric<Integer>.Spawn(Routine, 1000),
    TSymmetric<Integer>.Spawn(Routine, 100),
    TSymmetric<Integer>.Spawn(Routine, 10000)
  ], Index);

  WriteLn(Format('Greenlet with index = %d is terminated first', [Index]));

  ReadLn;

end.
