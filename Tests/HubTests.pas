unit HubTests;

interface
uses
  {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections,  System.Rtti{$ENDIF},
  Classes,
  SyncObjs,
  Greenlets,
  SysUtils,
  Hub,
  GInterfaces,
  AsyncThread,
  TestFramework;

type

  TIntfTestObject = class(TInterfacedObject)
    Tag: Integer;
  public
    procedure IncrementTag;
  end;

  TTestObject = class
    Tag: Integer;
    CtxHub: TCustomHub;
  public
    procedure IncrementTag;
  end;

  TSignalNotifier = class(TInterfacedObject)
  strict private
    FEvent: TEvent;
  public
    constructor Create(Event: TEvent);
    procedure Notify;
  end;

  TEmptyNotifier = class(TInterfacedObject)
  public
    procedure Notify;
  end;

  TFakeSingleThreadHub = class(TSingleThreadHub)
  strict private
    FAfterSwap: TEvent;
    FCanServe: TEvent;
  protected
    procedure AfterSwap; override;
    function ServeMultiplexor(TimeOut: LongWord): TSingleThreadHub.TMultiplexorEvent; override;
  public
    constructor Create;
    destructor Destroy; override;
    property OnAfterSwap: TEvent read FAfterSwap;
    property OnCanServe: TEvent read FCanServe;
  end;

  TPingPongThread = class(TThread)
  strict private
    FPartner: TPingPongThread;
    FMyValue: PInteger;
    FOtherValue: PInteger;
    FTimeout: Integer;
    FOnRun: TEvent;
    class procedure EmptyTask(Arg: Pointer); static;
  protected
    procedure Execute; override;
  public
    constructor Create(MyValue, OtherValue: PInteger; Timeout: Integer);
    destructor Destroy; override;
    procedure Run(Partner: TPingPongThread);
  end;

  THubTests = class(TTestCase)
  private
    FHub: TSingleThreadHub;
    FSignal: TEvent;
    FTag: Integer;
    FFakeSTHub: TFakeSingleThreadHub;
    class procedure EventCb(Hnd: THandle; Data: Pointer; const Aborted: Boolean); static;
    class procedure EventCbEmpty(Hnd: THandle; Data: Pointer; const Aborted: Boolean); static;
    class procedure IntervalCb(Id: THandle; Data: Pointer); static;
    class procedure IOCb(Fd: THandle; const Op: TIOOperation; Data: Pointer;
      ErrorCode: Integer; NumOfBytes: LongWord); static;
    procedure SignalByTask;
    class procedure PulseSignal(Arg: Pointer); static;
    function LoopExitCond: Boolean;
    procedure EmptyTask;
    procedure SyncEventLostUpdateEmulation;
    procedure SetTagTo99;
    procedure SetTagTo100;
    procedure TestSynchronize;
    procedure TestQueue;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EventNotify;
    procedure TimerNotify;
    procedure IntervalNotify;
    procedure FileReadWrite;
    procedure FileReadWriteWithPos;
    procedure EnqueueTask;
    procedure MainThreadTask;
    procedure ServeTimeout;
    procedure Loop;
    procedure DestroyWhileQueueNotEmpty;
    procedure SyncEventLostUpdate1;
    procedure SyncEventLostUpdate2;
    procedure BrokenSynchronize;
    procedure BrokenQueue;
    procedure PingPongThread;
  end;

implementation
uses Winapi.Windows, GreenletsImpl;


procedure THubTests.BrokenQueue;
var
  T: TAnyMethodThread;
  Stop: TTime;
begin
  Stop := Now + TimeOut2Time(1000);
  T := TAnyMethodThread.Create(TestQueue);
  try
    while Stop > Now do begin
      Check(DefHub.Serve(Time2TimeOut(Stop-Now)));
      if FTag = 99 then
        Break
    end;
    Check(FTag = 99);
  finally
    T.WaitFor;
    T.Free;
    FFakeSTHub.Free;
  end;
end;

procedure THubTests.BrokenSynchronize;
var
  T: TAnyMethodThread;
  Stop: TTime;
begin
  Stop := Now + TimeOut2Time(1000);
  T := TAnyMethodThread.Create(TestSynchronize);
  try
    while Stop > Now do begin
      Check(DefHub.Serve(Time2TimeOut(Stop-Now)));
      if FTag = 99 then
        Break
    end;
    Check(FTag = 99);
  finally
    T.WaitFor;
    T.Free;
    FFakeSTHub.Free;
  end;
end;

procedure THubTests.DestroyWhileQueueNotEmpty;
var
  Ntfy: TEmptyNotifier;
  Hub: THub;
begin
  Ntfy := TEmptyNotifier.Create;
  Ntfy._AddRef;
  Hub := TSingleThreadHub.Create;
  try
    Hub.EnqueueTask(Ntfy.Notify);
    Hub.EnqueueTask(Ntfy.Notify);
    Check(Ntfy.RefCount = 3, 'check1');
    FreeAndNil(Hub);
    Check(Ntfy.RefCount = 1, 'check2');
  finally
    if Assigned(Hub) then
      Hub.Free;
    while Ntfy.RefCount > 0 do
      Ntfy._Release;
  end;
end;

procedure THubTests.EmptyTask;
begin
  //
end;

procedure THubTests.EnqueueTask;
var
  Test1: TTestObject;
  Test2: TIntfTestObject;
  OldHub: TCustomHub;
begin
  Test1 := TTestObject.Create;
  Test2 := TIntfTestObject.Create;
  Test2._AddRef;
  OldHub := Hub.GetCurrentHub;
  try
    Check(OldHub <> FHub);
    FHub.EnqueueTask(Test1.IncrementTag);
    CheckTrue(FHub.Serve(0));
    CheckTrue(Test1.Tag = 1);
    CheckTrue(Test1.CtxHub = FHub);

    Check(OldHub <> FHub);
    FHub.EnqueueTask(Test2.IncrementTag);
    CheckTrue(Test2.RefCount = 2);
    CheckTrue(FHub.Serve(0));
    CheckTrue(Test2.Tag = 1);

    Check(OldHub <> FHub);
    FHub.EnqueueTask(PulseSignal, FSignal);
    CheckTrue(FHub.Serve(0));
    CheckTrue(FSignal.WaitFor(1000) = wrSignaled);
  finally
    Test1.Free;
    Test2._Release;
  end;
end;

class procedure THubTests.EventCb(Hnd: THandle; Data: Pointer; const Aborted: Boolean);
begin
  THubTests(Data).FSignal.SetEvent
end;

class procedure THubTests.EventCbEmpty(Hnd: THandle; Data: Pointer;
  const Aborted: Boolean);
begin
 //
end;

procedure THubTests.EventNotify;
var
  Ev: TEvent;
  Cnt: Integer;
begin
  Ev := TEvent.Create(nil, False, False, '');
  try
    Cnt := 100;
    FHub.AddEvent(Ev.Handle, EventCb, Self);
    while FSignal.WaitFor(0) <> wrSignaled  do begin
      FHub.Serve(0);
      Dec(Cnt);
      if Cnt = 1 then
        Ev.SetEvent;
    end;
    Check(Cnt = 0);
    Check(FSignal.WaitFor(0) = wrSignaled);
  finally
    Ev.Free;
  end;
end;

procedure THubTests.FileReadWrite;
var
  F: THandle;
  Buf1, Buf2: AnsiString;
begin
  F := CreateFile('test.txt', GENERIC_ALL, 0, nil, CREATE_ALWAYS,
    FILE_FLAG_OVERLAPPED or FILE_ATTRIBUTE_NORMAL, 0);
  Buf1 := 'hallo world';
  try
    FHub.Write(F, Pointer(Buf1), Length(Buf1), IOCb, Self);
    while FSignal.WaitFor(0) <> wrSignaled do
      FHub.Serve(0);
    FSignal.ResetEvent;
    SetLength(Buf2, Length(Buf1));
    FHub.Read(F, Pointer(Buf2), Length(Buf2), IOCb, Self, 0);
    while FSignal.WaitFor(0) <> wrSignaled do
      FHub.Serve(0);
    Check(Buf1 = Buf2);
  finally
    CloseHandle(F);
    DeleteFile('test.txt')
  end;
end;

procedure THubTests.FileReadWriteWithPos;
var
  F: THandle;
  Buf1, Buf2: AnsiString;
begin
  F := CreateFile('test.txt', GENERIC_ALL, 0, nil, CREATE_ALWAYS,
    FILE_FLAG_OVERLAPPED or FILE_ATTRIBUTE_NORMAL, 0);
  Buf1 := 'hallo world';
  try
    FHub.Write(F, Pointer(Buf1), Length(Buf1), IOCb, Self);
    while FSignal.WaitFor(0) <> wrSignaled do
      FHub.Serve(0);
    FSignal.ResetEvent;
    SetLength(Buf2, Length(Buf1));
    FHub.Read(F, Pointer(Buf2), Length(Buf2), IOCb, Self, 1);
    while FSignal.WaitFor(0) <> wrSignaled do
      FHub.Serve(0);
    Check(Copy(Buf2, 1, Length(Buf1)-1) = Copy(Buf1, 2, Length(Buf1)-1));
  finally
    CloseHandle(F);
    DeleteFile('test.txt')
  end;
end;

class procedure THubTests.IntervalCb(Id: THandle; Data: Pointer);
begin
  THubTests(Data).FSignal.SetEvent
end;

procedure THubTests.IntervalNotify;
var
  Ev: TEvent;
  Timeout: THandle;
  Stamp: TTime;
begin
  Ev := TEvent.Create(nil, False, False, '');
  try
    FHub.AddEvent(FSignal.Handle, EventCb, Self);
    Timeout := FHub.CreateTimeout(IntervalCb, Self, 300);
    Stamp := Now;
    while FSignal.WaitFor(0) <> wrSignaled do begin
      FHub.Serve(0);
    end;
    FHub.DestroyTimeout(Timeout);
    Check(FSignal.WaitFor(0) = wrSignaled);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 290), 'timerange cond 1');
    Check(Stamp < EncodeTime(0, 0, 0, 310), 'timerange cond 2');
  finally
    FHub.RemEvent(FSignal.Handle);
    Ev.Free;
  end;
end;

class procedure THubTests.IOCb(Fd: THandle; const Op: TIOOperation;
  Data: Pointer; ErrorCode: Integer; NumOfBytes: LongWord);
begin
  THubTests(Data).FSignal.SetEvent
end;

procedure THubTests.Loop;
begin
  FHub.Loop(LoopExitCond);
  Check(FTag > 1000);
end;

function THubTests.LoopExitCond: Boolean;
begin
  Inc(FTag);
  Result := FTag > 1000;
  FHub.EnqueueTask(EmptyTask);
end;

procedure THubTests.MainThreadTask;
var
  T: TAnyMethodThread;
  Stop: TTime;
begin
  Stop := Now + TimeOut2Time(3000);
  T := TAnyMethodThread.Create(SignalByTask);
  try
    CheckSynchronize(0);
    while (FSignal.WaitFor(0) <> wrSignaled) and (Now < Stop) do begin
      CheckTrue(FHub.Serve(Time2TimeOut(Stop - Now)));
    end;
    CheckTrue(Now <= Stop);
    CheckTrue(FSignal.WaitFor(0) = wrSignaled);
  finally
    T.Free;
  end;
end;

class procedure THubTests.PulseSignal(Arg: Pointer);
begin
  TEvent(Arg).SetEvent;
end;

procedure THubTests.PingPongThread;
const
  TEST_COUNT = 100000;
var
  T1, T2: TPingPongThread;
  Counter1, Counter2: Integer;
  {$IFDEF DEBUG}
  Start: TTime;
  {$ENDIF}
begin
  Counter1 := TEST_COUNT;
  Counter2 := TEST_COUNT;
  T1 := TPingPongThread.Create(@Counter1, @Counter2, 5000);
  T2 := TPingPongThread.Create(@Counter2, @Counter1, 5000);
  try
    {$IFDEF DEBUG}Start := Now;{$ENDIF}
    T1.Run(T2);
    T2.Run(T1);
    T1.WaitFor;
    T2.WaitFor;
  finally
    T1.Free;
    T2.Free;
  end;
  Check(Counter1 = 0, Format('Counter1 = %d', [Counter1]));
  Check(Counter2 = 0, Format('Counter2 = %d', [Counter2]));
  {$IFDEF DEBUG}
  DebugString(Format('Counter1 = %d', [Counter1]));
  DebugString(Format('Counter2 = %d', [Counter2]));
  DebugString(Format('Counter = %d, Timeout = %d', [TEST_COUNT + TEST_COUNT, Time2Timeout(Now-Start)]));
  {$ENDIF}
end;

procedure THubTests.ServeTimeout;
const
  cEvents: TSingleThreadHub.TMultiplexorEvents =
    [Low(TSingleThreadHub.TMultiplexorEvent)..High(TSingleThreadHub.TMultiplexorEvent)] - [meWinMsg];
var
  Stamp: TTime;
  Ret: TSingleThreadHub.TMultiplexorEvent;

  function PrintRet: string;
  begin
    case Ret of
      meError:  Result := 'meError';
      meEvent:  Result := 'meEvent';
      meSync:   Result := 'meSyns';
      meIO:     Result := 'meIO';
      meWinMsg: Result := 'meWinMsg';
      meTimer:  Result := 'meTimer';
      meWaitTimeout: Result := 'meWaitTimeout';
    end;
  end;

begin
  Stamp := Now;
  Ret := FHub.Wait(500, cEvents);
  Check(Ret = meWaitTimeout, PrintRet);
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 490), 'timeout 1 = ' + IntToStr(Time2TimeOut(Stamp)));
  Check(Stamp <= EncodeTime(0, 0, 0, 510), 'timeout 2 = ' + IntToStr(Time2TimeOut(Stamp)))
end;

procedure THubTests.SetTagTo100;
begin
  FTag := 100;
end;

procedure THubTests.SetTagTo99;
begin
  FTag := 99
end;

procedure THubTests.SetUp;
begin
  inherited;
  FSignal := TEvent.Create(nil, True, False, '');
  FHub := TSingleThreadHub.Create;
  FTag := 0;
end;

procedure THubTests.SignalByTask;
var
  Ntfy: TSignalNotifier;
begin
  Sleep(1000);
  Ntfy := TSignalNotifier.Create(FSignal);
  Ntfy._AddRef;
  TThread.Queue(TThread.CurrentThread, Ntfy.Notify);
end;

procedure THubTests.SyncEventLostUpdate1;
var
  T: TAnyMethodThread;
begin
  FFakeSTHub := TFakeSingleThreadHub.Create;
  T := TAnyMethodThread.Create(SyncEventLostUpdateEmulation);
  try
    CheckTrue(FFakeSTHub.Wait(INFINITE, TSingleThreadHub.ALL_EVENTS - [meWinMsg]) = meSync);
    CheckTrue(FFakeSTHub.Serve(0));
    Check(FTag = 99);
    CheckTrue(FFakeSTHub.Wait(INFINITE, TSingleThreadHub.ALL_EVENTS - [meWinMsg]) = meSync);
    CheckTrue(FFakeSTHub.Serve(0));
    Check(FTag = 100);
  finally
    T.WaitFor;
    T.Free;
    FFakeSTHub.Free;
  end;
end;

procedure THubTests.SyncEventLostUpdate2;
var
  Event: TEvent;
  Res: TSingleThreadHub.TMultiplexorEvent;
begin
  Event := TEvent.Create(nil, True, False, '');
  try
    FHub.AddEvent(Event.Handle, EventCbEmpty, nil);
    Res := FHub.Wait(100, TSingleThreadHub.ALL_EVENTS - [meWinMsg, meSync]);
    Check(Res = meWaitTimeout, 'problem 1');

    Event.SetEvent;
    Res := FHub.Wait(100, TSingleThreadHub.ALL_EVENTS - [meWinMsg, meSync]);
    Check(Res = meEvent, 'problem 2');
  finally
    Event.Free;
  end;
end;

procedure THubTests.SyncEventLostUpdateEmulation;
begin
  FFakeSTHub.OnAfterSwap.ResetEvent;
  FFakeSTHub.EnqueueTask(SetTagTo99);
  FFakeSTHub.OnCanServe.SetEvent;
  FFakeSTHub.OnAfterSwap.WaitFor(INFINITE);
  FFakeSTHub.OnCanServe.ResetEvent;
  FFakeSTHub.EnqueueTask(SetTagTo100);
  FFakeSTHub.OnCanServe.SetEvent;
end;

procedure THubTests.TearDown;
begin
  inherited;
  FSignal.Free;
  FHub.Free;
end;

procedure THubTests.TestQueue;
begin
  TThread.Queue(nil, SetTagTo99);
end;

procedure THubTests.TestSynchronize;
begin
  TThread.Synchronize(nil, SetTagTo99);
end;

procedure THubTests.TimerNotify;
var
  Ev: TEvent;
  Timer: THandle;
  Stamp: TTime;
begin
  Ev := TEvent.Create(nil, False, False, '');
  FHub.AddEvent(FSignal.Handle, EventCb, Self);
  try
    Timer := FHub.CreateTimer(IntervalCb, Self, 300);
    Stamp := Now;
    while FSignal.WaitFor(0) <> wrSignaled do begin
      FHub.Serve(0);
    end;
    FHub.DestroyTimer(Timer);
    Check(FSignal.WaitFor(0) = wrSignaled);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 290), 'timerange cond 1');
    Check(Stamp < EncodeTime(0, 0, 0, 310), 'timerange cond 2');
  finally
    Ev.Free;
  end;
end;

{ TIntfTestObject }

procedure TIntfTestObject.IncrementTag;
begin
  Inc(Tag)
end;

{ TTestObject }

procedure TTestObject.IncrementTag;
begin
  Inc(Tag);
  CtxHub := Hub.GetCurrentHub;
end;

{ TSignalNotifier }

constructor TSignalNotifier.Create(Event: TEvent);
begin
  inherited Create;
  FEvent := Event;
end;

procedure TSignalNotifier.Notify;
begin
  FEvent.SetEvent;
  Self._Release;
end;

{ TEmptyNotifier }

procedure TEmptyNotifier.Notify;
begin
  //
end;

{ TFakeSingleThreadHub }

procedure TFakeSingleThreadHub.AfterSwap;
begin
  inherited;
  FAfterSwap.SetEvent
end;

constructor TFakeSingleThreadHub.Create;
begin
  inherited Create;
  FAfterSwap := TEvent.Create(nil, True, False, '');
  FCanServe := TEvent.Create(nil, True, False, '');
end;

destructor TFakeSingleThreadHub.Destroy;
begin
  FAfterSwap.Free;
  FCanServe.Free;
  inherited;
end;

function TFakeSingleThreadHub.ServeMultiplexor(
  TimeOut: LongWord): TSingleThreadHub.TMultiplexorEvent;
begin
  FCanServe.WaitFor(INFINITE);
  Result := inherited ServeMultiplexor(TimeOut)
end;

{ TPingPongThread }

constructor TPingPongThread.Create(MyValue, OtherValue: PInteger; Timeout: Integer);
begin
  FMyValue := MyValue;
  FOtherValue := OtherValue;
  FTimeout := Timeout;
  FOnRun := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TPingPongThread.Destroy;
begin
  FOnRun.Free;
  inherited;
end;

class procedure TPingPongThread.EmptyTask(Arg: Pointer);
begin
  //
end;

procedure TPingPongThread.Execute;
var
  Stop: TTime;
begin
  Stop := Now + TimeOut2Time(FTimeout);
  FOnRun.WaitFor(FTimeout);
  while ((FMyValue^ > 0) or (FOtherValue^ > 0)) and (Stop > Now) do begin
    DefHub(FPartner).EnqueueTask(EmptyTask, nil);
    if FMyValue^ > 0 then begin
      DefHub.Serve(Time2TimeOut(Stop - Now));
      Dec(FMyValue^);
    end;
  end;
end;

procedure TPingPongThread.Run(Partner: TPingPongThread);
begin
  FPartner := Partner;
  FOnRun.SetEvent;
end;

initialization
  RegisterTest('HubTests', THubTests.Suite);


end.
