program Symmetric;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  S: TSymmetric<Integer>;
  Proc: TSymmetricRoutine<Integer>;

begin
  Proc := procedure(const Input: Integer)
  var
    Internal: Integer;
  begin
    WriteLn('Input value: ', Input);
    try
      Internal := Input;
      while True do
      begin
        Yield;  // return to caller context
        Inc(Internal);
        WriteLn('Internal = ', Internal);
      end
    finally
      WriteLn('Execution is terminated...')
    end
  end;

  S := TSymmetric<Integer>.Create(Proc, 10);

  // Manually call to Switch is not thread safe so this call is not declared
  // in Symmetric interface
  with IRawGreenlet(S) do
  begin
    Switch;
    Switch;
    Switch;
  end;
  S.Kill;
  Readln;
end.
