program HowTo.LocalContexts;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  Classes,
  System.SysUtils;

function GetAddress: string;
begin
  Result := GetEnvironment.GetStrValue('Connection.Address')
end;

begin

  try
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
