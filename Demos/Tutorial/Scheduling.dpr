program Scheduling;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  Classes,
  System.SysUtils;

function Fibonacci(N: Integer): Integer;
begin
  if N < 0 then
    raise Exception.Create('The Fibonacci sequence is not defined for negative integers.');
  case N of
    0: Result:= 0;
    1: Result:= 1;
    else
      Result := Fibonacci(N - 1) + Fibonacci(N - 2);
  end;
end;

function ThreadedFibo(const N: Integer): string;
begin
  Result := Format('Thread %d. Fibonacci(%d) = %d',
    [TThread.CurrentThread.ThreadID, N, Fibonacci(N)])
end;

var
  F1, F2, F3: TAsymmetric<string>;
  OtherThread: TGreenThread;

begin

  OtherThread := TGreenThread.Create;
  try
    F1 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 10);
    F2 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 20);
    F3 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 30);

    Writeln(Format('F1.GetResult = "%s"', [F1.GetResult]));
    Writeln(Format('F2.GetResult = "%s"', [F2.GetResult]));
    Writeln(Format('F3.GetResult = "%s"', [F3.GetResult]));

    Readln;

  finally
    OtherThread.Free
  end;

end.
