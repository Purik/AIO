program BeginEndThread;

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

var
  F1, F2, F3: TAsymmetric<Integer, string>;
  ThreadedFibo: TAsymmetricRoutine<Integer, string>;

begin


  ThreadedFibo := function(const N: Integer): string
  var
    Thread1, Thread2, Thread3: LongWord;
    Fibo: Integer;
  begin
    Thread1 := TThread.CurrentThread.ThreadID;
    // Switch to New thread
    BeginThread;
    Thread2 := TThread.CurrentThread.ThreadID;
    // calculation in context of other thread
    Fibo := Fibonacci(N);

    // return to caller thread
    // It is usefull if you have initiated process in MainThread for example
    // and after that you wish return to Main thread and Paint results on GUI
    EndThread;
    Thread3 := TThread.CurrentThread.ThreadID;

    Result := Format('Fibo(%d) = %d;  Thread1=%d, Thread2=%d, Thread3=%d',
      [N, Fibo, Thread1, Thread2, Thread3]);
  end;


  F1 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 10);
  F2 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 20);
  F3 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 30);

  Join([F1, F2, F3]);

  Writeln(Format('F1.GetResult = "%s"', [F1.GetResult]));
  Writeln(Format('F2.GetResult = "%s"', [F2.GetResult]));
  Writeln(Format('F3.GetResult = "%s"', [F3.GetResult]));

  Readln;

end.
