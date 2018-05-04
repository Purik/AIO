program GreenletVarArgs;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

var
  G: TGreenlet;
  Routine: TSymmetricArgsRoutine;

begin

  Routine := procedure(const Args: array of const)
  var
    I: Integer;
  begin
    WriteLn('Greenlet context enter');
    for I := Low(Args) to High(Args) do
    begin
      // you can check type of VarArg and cast to type
      if Args[I].IsInteger then
        Write(Format('Arg[%d] = %d; ', [I, Args[I].AsInteger]))
      else if Args[I].IsString  then
        Write(Format('Arg[%d] = "%s"; ', [I, Args[I].AsString]))
      else
        Write(Format('Arg[%d] - unexpected type', [I]))
    end;
    WriteLn;
    WriteLn('Greenlet context leave');
  end;

  G := TGreenlet.Spawn(Routine, [1, 'hello!', 5.6]);
  ReadLn;
end.
