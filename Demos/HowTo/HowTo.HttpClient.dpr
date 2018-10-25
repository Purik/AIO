program HowTo.HttpClient;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils,
  Classes,
  IdIOHandlerStack,
  Generics.Collections,
  IdHTTP;

const
  PARALLEL_NUM = 50;
  STRESS_FACTOR = 100;

var
  Stamp: TDateTime;
  Ms, Sec, Min, Hrs: Word;
  Threads: TList<TThread>;
  Greenlets: TGreenGroup<Integer>;
  G: TSymmetric;
  Th: TThread;
  I: Integer;

procedure PrintTimeout(Start, Stop: TDateTime);
begin
  DecodeTime(Stop-Start, Hrs, Min, Sec, Ms);
  Writeln(Format('Sec: %d,  MSec: %d', [Sec, Ms]));
end;

begin
  Writeln('Workers Count = ' + IntToStr(PARALLEL_NUM));
  Writeln('Using blocking Indy sockets');
  Stamp := Now;
  // Threads with blocking sockets
  Threads := TList<TThread>.Create;
  try
    for I := 0 to PARALLEL_NUM-1 do begin
      Th := TThread.CreateAnonymousThread(procedure
        var
          Client: TIdHTTP;
          Response: string;
          I: Integer;
        begin
          Client := TIdHTTP.Create(nil);
          try
            Client.IOHandler := TIdIOHandlerStack.Create(Client);
            Client.HandleRedirects := True;
            for I := 1 to STRESS_FACTOR do begin
              Response := Client.Get('http://uit.fun/aio');
              Assert(Response <> '');
            end;
          finally
            Client.Free;
          end;
        end
      );
      Threads.Add(Th);
      Th.FreeOnTerminate := False;
      Th.Start;
    end;
    // Join
    for I := 0 to PARALLEL_NUM-1 do begin
      Threads[I].WaitFor;
      Threads[I].Free;
    end;
    PrintTimeout(Stamp, Now);
  finally
    Threads.Free
  end;

  Writeln('Using non-blocking Aio IO handler');
  Stamp := Now;
  for I := 0 to PARALLEL_NUM-1 do begin
    G := TSymmetric.Create(procedure
      var
        Client: TIdHTTP;
        Response: string;
        I: Integer;
      begin
        Client := TIdHTTP.Create(nil);
        try
          //Write('*');
          Client.IOHandler := TAioIdIOHandlerSocket.Create(Client);
          Client.HandleRedirects := True;
          for I := 1 to STRESS_FACTOR do begin
            Response := Client.Get('http://uit.fun/aio');
            Assert(Response <> '');
          end;
        finally
          Client.Free;
        end;
      end
    );
    Greenlets[I] := G;
  end;
  try
    Greenlets.Join(INFINITE, True);
  except
    on E: Exception do begin
      Writeln('Error: ' + E.Message);
    end
  end;
  PrintTimeout(Stamp, Now);
  Readln;
end.
