unit AioIndyTests;

interface
uses
  Greenlets,
  IdHTTP,
  AioIndy,
  TestFramework;

type

  TAioIndyTests = class(TTestCase)
  published
    procedure HttpGet;
  end;

implementation

{ TAioIndyTests }

procedure TAioIndyTests.HttpGet;
var
  Client: TIdHTTP;
  Response: string;
begin
  Client := TIdHTTP.Create(nil);
  try
    Client.IOHandler := AioIndy.TAioIdIOHandlerSocket.Create(Client);
    Client.HandleRedirects := True;
    Response := Client.Get('http://uit.fun/aio');
    CheckEquals('Hello!!!', Response);
  finally
    Client.Free
  end;
end;

initialization
  RegisterTest('AioIndyTests', TAioIndyTests.Suite);

end.
