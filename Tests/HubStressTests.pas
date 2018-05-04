unit HubStressTests;

interface
uses Hub, Utils, SysUtils;

procedure DecrementIntValue(IntValuePtr: Pointer);

function NonHubStressTest(Iterations: Integer): LongWord;
procedure AtomicExchangeIntValue(Iterations: Integer);
procedure DefHubLoopServe(Iterations: Integer);
procedure DefHubLoopWait(Iterations: Integer);
function DefHubLoopStressTestWorker1(Iterations: Integer): LongWord;
function DefHubLoopStressTestWorker5(Iterations: Integer): LongWord;
function DefHubLoopStressTestWorker10(Iterations: Integer): LongWord;
procedure LongServe(Iterations: Integer);

procedure ThreadHubStressTest(Iterations: Integer; WorkersCount: Integer);
procedure ThreadDecGlobalTest(Iterations: Integer; WorkersCount: Integer);
procedure ThreadDecLocalTest(Iterations: Integer; WorkersCount: Integer);

procedure ThreadTaskQueueTest(Iterations: Integer; Window: Integer);
procedure ThreadTaskStdQueueTest(Iterations: Integer; Window: Integer);

implementation
uses Classes, SyncObjs;

type
  TAsyncHubThread = class(TThread)
  strict private
    FHub: TSingleThreadHub;
    FStartEv: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property Hub: TSingleThreadHub read FHub;
    procedure Run;
  end;

  THubThread = class(TThread)
  strict private
    FHub: TSingleThreadHub;
    FValue: PInteger;
    FPartnerHub: THub;
    FStartEv: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(ValuePtr: PInteger);
    destructor Destroy; override;
    property PartnerHub: THub read FPartnerHub write FPartnerHub;
    property Hub: TSingleThreadHub read FHub;
    procedure Run;
  end;

  TDecGlobalIntThread = class(TThread)
  strict private
    FValue: PInteger;
    FStartEv: TEvent;
    FStopValue: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ValuePtr: PInteger; StopValue: Integer = 0);
    destructor Destroy; override;
    procedure Run;
  end;

  TDecLocalIntThread = class(TThread)
  strict private
    FStartValue: Integer;
    FStartEv: TEvent;
    FStopValue: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(StartValue: Integer; StopValue: Integer = 0);
    destructor Destroy; override;
    procedure Run;
  end;

  TDecStdQueueThread = class(TThread)
  strict private
    FValue: Integer;
    FStopValue: Integer;
    FStartEv: TEvent;
    FWindow: Integer;
    procedure Decrement;
  protected
    procedure Execute; override;
  public
    constructor Create(StartValue: Integer; Window: Integer;
      StopValue: Integer = 0);
    destructor Destroy; override;
    procedure Run;
  end;

procedure DecrementIntValue(IntValuePtr: Pointer);
begin
  Dec(PInteger(IntValuePtr)^)
end;

procedure RaiseAbort(Null: Pointer);
begin
  Abort;
end;

function NonHubStressTest(Iterations: Integer): LongWord;
var
  Value: Integer;
begin
  Value := Iterations;
  Writeln(Format('Iterations: %d | No hub', [Iterations]));
  StartTime;
  while Value > 0 do begin
    DecrementIntValue(@Value);
  end;
  Result := StopTime;
  Writeln(Format('Result: %d msec', [Result]));
end;

procedure AtomicExchangeIntValue(Iterations: Integer);
var
  Value: Integer;
  Timeout: LongWord;
begin
  Value := Iterations;
  Writeln(Format('Iterations: %d', [Iterations]));
  StartTime;
  while Value > 0 do begin
    AtomicExchange(Value, Value-1)
  end;
  Timeout := StopTime;
  Writeln(Format('Result: %d msec', [Timeout]));
end;

procedure DefHubLoopServe(Iterations: Integer);
var
  Value: Integer;
  Timeout: LongWord;
  Hub: THub;
begin
  Hub := DefHub;
  Value := Iterations;
  Writeln(Format('Iterations: %d', [Iterations]));
  StartTime;
  while Value > 0 do begin
    Hub.Serve(0);
    Dec(Value);
  end;
  Timeout := StopTime;
  Writeln(Format('Result: %d msec', [Timeout]));
end;

procedure DefHubLoopWait(Iterations: Integer);
var
  Value: Integer;
  Timeout: LongWord;
  Hub: TSingleThreadHub;
begin
  Hub := DefHub;
  Value := Iterations;
  Writeln(Format('Iterations: %d', [Iterations]));
  StartTime;
  while Value > 0 do begin
    Hub.Wait(0);
    Dec(Value);
  end;
  Timeout := StopTime;
  Writeln(Format('Result: %d msec', [Timeout]));
end;

function DefHubLoopStressTestWorker1(Iterations: Integer): LongWord;
var
  Value: Integer;
  Hub: TSingleThreadHub;
begin
  Hub := DefHub;
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, 1]));
  Value := Iterations;
  StartTime;
  while Value > 0 do begin
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.Serve(INFINITE)
  end;
  Result := StopTime;
  Writeln(Format('Result: %d msec', [Result]));
end;

function DefHubLoopStressTestWorker5(Iterations: Integer): LongWord;
var
  Value: Integer;
  Hub: TSingleThreadHub;
begin
  Hub := DefHub;
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, 5]));
  Value := Iterations;
  StartTime;
  while Value > 0 do begin
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.Serve(INFINITE)
  end;
  Result := StopTime;
  Writeln(Format('Result: %d msec', [Result]));
end;

function DefHubLoopStressTestWorker10(Iterations: Integer): LongWord;
var
  Value: Integer;
  Hub: TSingleThreadHub;
begin
  Hub := DefHub;
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, 10]));
  Value := Iterations;
  StartTime;
  while Value > 0 do begin
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.EnqueueTask(DecrementIntValue, @Value);
    Hub.Serve(INFINITE)
  end;
  Result := StopTime;
  Writeln(Format('Result: %d msec', [Result]));
end;

procedure LongServe(Iterations: Integer);
var
  I: Integer;
  Hub: TSingleThreadHub;
begin
  Writeln(Format('Iterations: %d', [Iterations]));
  Hub := DefHub;
  StartTime;
  for I := 1 to Iterations do
    Hub.Serve(0);
  Writeln(Format('Result: %d msec', [StopTime]));
end;

procedure ThreadTaskStdQueueTest(Iterations: Integer; Window: Integer);
var
  T: TDecStdQueueThread;
  Timeout: LongWord;
begin
  Assert(Window > 0);
  Writeln(Format('Iterations: %d | Window: %d', [Iterations, Window]));
  T := TDecStdQueueThread.Create(Iterations, Window);
  try
    Sleep(100);
    StartTime;
    T.Run;
    T.WaitFor;
    Timeout := StopTime;
    Writeln(Format('Result: %d msec', [Timeout]));
  finally
    T.WaitFor;
    T.Free
  end;
end;

procedure ThreadTaskQueueTest(Iterations: Integer; Window: Integer);
var
  T: TAsyncHubThread;
  Value, Barrier, I: Integer;
  Timeout: LongWord;
begin
  Assert(Window > 0);
  Value := Iterations;
  Writeln(Format('Iterations: %d | Window: %d', [Iterations, Window]));
  T := TAsyncHubThread.Create;
  try
    Sleep(100);
    StartTime;
    T.Run;
    while True do begin
      Barrier := Value - Window;
      for I := 1 to Window do
        T.Hub.EnqueueTask(DecrementIntValue, @Value);
      while Value > Barrier do ;
      if Barrier <= 0 then
        Break
    end;
    Timeout := StopTime;
    Writeln(Format('Result: %d msec', [Timeout]));
  finally
    T.Hub.EnqueueTask(RaiseAbort, nil);
    T.WaitFor;
    T.Free
  end;
end;

procedure ThreadDecLocalTest(Iterations: Integer; WorkersCount: Integer);
var
  T: array of TDecLocalIntThread;
  I: Integer;
  Timeout: LongWord;
begin
  Assert(WorkersCount > 1);
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, WorkersCount]));
  SetLength(T, WorkersCount);
  for I := 0 to High(T) do begin
    T[I] := TDecLocalIntThread.Create(Iterations);
  end;
  Sleep(100);
  StartTime;
  for I := 0 to High(T) do begin
    T[I].Run
  end;
  for I := 0 to High(T) do begin
    T[I].WaitFor;
    T[I].Free
  end;
  Timeout := StopTime;
  Writeln(Format('Result: %d msec', [Timeout]));
end;

procedure ThreadDecGlobalTest(Iterations: Integer; WorkersCount: Integer);
var
  T: array of TDecGlobalIntThread;
  I: Integer;
  Value: Integer;
  Timeout: LongWord;
begin
  Assert(WorkersCount > 1);
  Value := Iterations;
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, WorkersCount]));
  SetLength(T, WorkersCount);
  for I := 0 to High(T) do begin
    T[I] := TDecGlobalIntThread.Create(@Value);
  end;
  Sleep(100);
  StartTime;
  for I := 0 to High(T) do begin
    T[I].Run
  end;
  while Value > 0 do ;
  Timeout := StopTime;
  for I := 0 to High(T) do begin
    T[I].WaitFor;
    T[I].Free
  end;
  Writeln(Format('Result: %d msec', [Timeout]));
end;

procedure ThreadHubStressTest(Iterations: Integer; WorkersCount: Integer);
var
  T: array of THubThread;
  I: Integer;
  PartnerHub: THub;
  Value: Integer;
  Timeout: LongWord;
begin
  Assert(WorkersCount > 1);
  Value := Iterations;
  Writeln(Format('Iterations: %d | Workers: %d', [Iterations, WorkersCount]));
  SetLength(T, WorkersCount);
  for I := 0 to High(T) do begin
    T[I] := THubThread.Create(@Value);
  end;
  for I := 0 to High(T) do begin
    PartnerHub := T[(I+1) mod Length(T)].Hub;
    T[I].PartnerHub := PartnerHub;
  end;
  Sleep(100);
  StartTime;
  for I := 0 to High(T) do begin
    T[I].Run
  end;
  while Value > 0 do ;

  Timeout := StopTime;
  for I := 0 to High(T) do begin
    T[I].Hub.Pulse;
    T[I].WaitFor;
    T[I].Free
  end;
  Writeln(Format('Result: %d msec', [Timeout]));

end;

{ THubThread }

constructor THubThread.Create(ValuePtr: PInteger);
begin
  FValue := ValuePtr;
  FHub := TSingleThreadHub.Create;
  FStartEv := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor THubThread.Destroy;
begin
  FHub.Free;
  FStartEv.Free;
  inherited;
end;

procedure THubThread.Execute;
begin
  FStartEv.WaitFor(INFINITE);
  while FValue^ > 0 do begin
    FPartnerHub.EnqueueTask(DecrementIntValue, FValue);
    FHub.Serve(INFINITE)
  end
end;

procedure THubThread.Run;
begin
  FStartEv.SetEvent
end;

{ TDecGlobalIntThread }

constructor TDecGlobalIntThread.Create(ValuePtr: PInteger; StopValue: Integer = 0);
begin
  FValue := ValuePtr;
  FStopValue := StopValue;
  FStartEv := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TDecGlobalIntThread.Destroy;
begin
  FStartEv.Free;
  inherited;
end;

procedure TDecGlobalIntThread.Execute;
begin
  FStartEv.WaitFor(INFINITE);
  inherited;
  while FValue^ > FStopValue do
    Dec(FValue^)
end;

procedure TDecGlobalIntThread.Run;
begin
  FStartEv.SetEvent;
end;

{ TDecLocalIntThread }

constructor TDecLocalIntThread.Create(StartValue, StopValue: Integer);
begin
  FStartValue := StartValue;
  FStopValue := StopValue;
  FStartEv := TEvent.Create(nil, True, False, '');
  inherited Create(False)
end;

destructor TDecLocalIntThread.Destroy;
begin
  FStartEv.Free;
  inherited;
end;

procedure TDecLocalIntThread.Execute;
var
  Value: Integer;
begin
  FStartEv.WaitFor(INFINITE);
  inherited;
  Value := FStartValue;
  while Value > FStopValue do
    Dec(Value);
end;

procedure TDecLocalIntThread.Run;
begin
  FStartEv.SetEvent
end;

{ TAsyncHubThread }

constructor TAsyncHubThread.Create;
begin
  FHub := TSingleThreadHub.Create;
  FStartEv := TEvent.Create(nil, True, False, '');
  inherited Create(False)
end;

destructor TAsyncHubThread.Destroy;
begin
  FStartEv.Free;
  FHub.Free;
  inherited;
end;

procedure TAsyncHubThread.Execute;
begin
  inherited;
  FStartEv.WaitFor(INFINITE);
  while True do begin
    FHub.Serve(INFINITE)
  end;
end;

procedure TAsyncHubThread.Run;
begin
  FStartEv.SetEvent
end;

{ TDecStdQueueThread }

constructor TDecStdQueueThread.Create(StartValue, Window: Integer;
  StopValue: Integer);
begin
  FValue := StartValue;
  FStopValue := StopValue;
  FWindow := Window;
  FStartEv := TEvent.Create(nil, True, False, '');
  inherited Create(False)
end;

procedure TDecStdQueueThread.Decrement;
begin
  Dec(FValue)
end;

destructor TDecStdQueueThread.Destroy;
begin
  FStartEv.Free;
  inherited;
end;

procedure TDecStdQueueThread.Execute;
var
  Barrier, I: Integer;
begin
  inherited;
  FStartEv.WaitFor(INFINITE);
  while True do begin
    Barrier := FValue - FWindow;
    for I := 1 to FWindow do
      Queue(nil, Decrement);
    while FValue > Barrier do ;
    if Barrier <= 0 then
      Break
  end;
end;

procedure TDecStdQueueThread.Run;
begin
  FStartEv.SetEvent
end;

end.
