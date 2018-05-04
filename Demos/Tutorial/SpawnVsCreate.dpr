program SpawnVsCreate;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  S1, S2: TSymmetric<string>;
  Proc: TSymmetricRoutine<string>;

begin

  Proc := procedure(const Name: string)
  begin
    try
      while True do
      begin
        WriteLn(Format('Greenlet "%s" is called!', [Name]));
        Yield;
      end
    finally
      WriteLn(Format('Greenlet "%s" is terminated!', [Name]));
    end
  end;

  S1 := TSymmetric<string>.Create(Proc, 'greenlet 1');
  S2 := TSymmetric<string>.Spawn(Proc, 'greenlet 2');

  Assert(IRawGreenlet(S1).GetState = gsReady);
  Assert(IRawGreenlet(S2).GetState = gsExecute);
  S2.Kill;
  Assert(IRawGreenlet(S2).GetState = gsKilled);
  IRawGreenlet(S1).Switch;
  Assert(IRawGreenlet(S1).GetState = gsExecute);
  ReadLn;

end.
