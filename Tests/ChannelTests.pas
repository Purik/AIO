unit ChannelTests;

interface
uses
  {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections,  System.Rtti{$ENDIF},
  Classes,
  SyncObjs,
  Gevent,
  SysUtils,
  GInterfaces,
  Hub,
  GarbageCollector,
  AsyncThread,
  GreenletsImpl,
  ChannelImpl,
  Greenlets,
  TestFramework;

type

  TTestObj = class
    OnDestroy: TNotifyEvent;
  public
    destructor Destroy; override;
  end;

  TIntfTestObj = class(TInterfacedObject)
    OnDestroy: TNotifyEvent;
  public
    destructor Destroy; override;
  end;

  TGCPointerTests = class(TTestCase)
  strict private
    FLog: TStrings;
    procedure LogDestruction(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Objects;
    procedure Interfaces;
  end;

  TContractTests = class(TTestCase)
  const
    BIG_TEST_COUNTER = 2*500000;
  private
  type
    TLightGeventPair = record
      E1: ILightGevent;
      E2: ILightGevent;
    end;
  var
    FLog: TStrings;
    FPing: IRawGreenlet;
    FPong: IRawGreenlet;
    FValue: Integer;
    FLightPair: TLightGeventPair;
    procedure PingSyncLightGevent(const Count: Integer);
    procedure PongSyncLightGevent(const Threaded: Boolean);
    procedure PingFast(const Count: Integer; const Shared: PInteger);
    procedure PongFast(const Shared: PInteger);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure G2GSyncFast;
    procedure G2GLightEvPingPong;
  end;

  TArrayOfInt = array of Integer;
  TIntChannel = TChannel<Integer>;
  TStrChannel = TChannel<string>;
  TObjChannel = TChannel<TObject>;

  TSoftDeadlock = class(EAbort);
  TInternalDeadLock = class(EAbort);

  TChannelTransporter = class
  strict private
    FChannel: TChannel<Integer>;
  public
    property Channel: TChannel<Integer> read FChannel write FChannel;
  end;

  TCaseSetTests = class(TTestCase)
  published
    procedure ConstructorTest;
    procedure AddCase;
    procedure AddCaseSet;
    procedure SubCase;
    procedure SubCaseSet;
    procedure IsEmpty;
    procedure Duplicates;
    procedure InOperator;
  end;

  TCustomChannelTests = class(TTestCase)
  const
    BIG_TEST_COUNTER = 2*500000;
  private
    FLog: TStrings;
    FGlobalChan: TChannel<Integer>;
    FGlobGreenlet: IRawGreenlet;
    procedure Write2IntChannel(const Values: TArrayOfInt; const Ch: TChannel<Integer>);
    procedure Write2IntChannel2(const Values: TArrayOfInt; const Ch: TChannel<Integer>.TWriteOnly);
    procedure Read2IntChannel(const Ch: TChannel<Integer>; const Values: TArrayOfInt);
    procedure Write2IntChannelThreaded(const Count: Integer; const Ch: TChannel<Integer>);
    procedure Read2IntChannelThreaded(const Ch: TChannel<Integer>; const Count: Integer);
    procedure Ping(const Count: Integer; const Ch: TChannel<Integer>);
    procedure Pong(const Ch: TChannel<Integer>);
    procedure Write2IntChannelStress(const Count: Integer; const Ch: TChannel<Integer>);
    procedure Read2IntChannelStress(const Ch: TChannel<Integer>);
    function  SerializeChatMessage(const Sender, Dest, Msg: string): string;
    procedure DeserializeChatMessage(const Raw: string; out Sender, Dest, Msg: string);
    procedure ChatRoutine(const Nick: string; const Ch: TChannel<string>);
    procedure LostUpdateRoutine(const DelayToStart: Integer; const Ch: TChannel<string>);
    procedure Write2ObjChannel(const A: TObject; const Ch: TChannel<TObject>);
    procedure MakeDeadlockChanWrite;
    procedure MakeDeadlockChanRead;
    procedure DeadlockReadonly;
    procedure DeadlockReadChan;
    procedure DeadlockWriteonly;
    procedure DeadlockWriteChan;
    procedure MakeDeadlockReadOnExit;
    procedure MakeDeadlockWriteOnExit;
    procedure LogReadonly(const Ch: TChannel<Integer>.TReadOnly);
    procedure LogReadChan(const Ch: TChannel<Integer>);
    procedure InfiniteRead(const Ch: TChannel<Integer>);
    procedure InfiniteWrite(const Ch: TChannel<Integer>);
    procedure InfiniteClose(const Ch: TChannel<Integer>);
    procedure MakeLeaveLockReadChan;
    procedure MakeLeaveLockWriteChan;
    procedure MakeLeaveLockCloseChan;
    procedure MakeNoDeadLockReadChan1;
    procedure MakeNoDeadLockReadChan2;
    procedure SetInternalDeadlockAndRead(const Ch: TChannel<Integer>.TReadOnly);
    procedure RunInternalDeadlockAndRead;
    procedure WriteAndLog(const Ch: TChannel<Integer>; const Values: TArrayOfInt);
    procedure WriteByStep(const Ch: TChannel<Integer>; const Values: TArrayOfInt;
      const Emitter: IGevent);
    procedure ReadByStep(const Ch: TChannel<Integer>; const Emitter: IGevent);
    procedure ReadTestObj(const Input: TChannel<TTestObj>.TReadOnly);
    procedure WriteTstObj(const Output: TChannel<TTestObj>.TWriteOnly; const Count: Integer);
  protected
    FIntChannel: TChannel<Integer>;
    FStrChannel: TChannel<string>;
    FObjChannel: TChannel<TObject>;
    procedure SetUp; override;
    procedure TearDown; override;
    function GetChanSize: Integer; virtual; abstract;
  published
    procedure IsNull;
    procedure G2G; virtual;
    procedure G2GStress; virtual;
    procedure G2R; virtual;
    procedure R2G; virtual;
    procedure R2GStress; virtual;
    procedure G2RStress; virtual;
    procedure G2GThreaded; virtual;
    procedure G2GPingPong; virtual;
    procedure MultiChat; virtual;
    procedure LostUpdate1; virtual;
    procedure LostUpdate2; virtual;
    procedure BlockProducer;
    procedure GC1; virtual;
    procedure GCStress;
    procedure DeadLockSelf;
    procedure DeadLockRWOnlyChannel;
    procedure DeadlockChannel;
    procedure DeadlockOnExit;
    procedure LeaveLockReadWrite;
    procedure LeaveLockClose;
    procedure SetSelfDeadlockException;
    procedure PendingRead1;
    procedure PendingWrite1;
    procedure CasesForRead;
    procedure SwitchForRead;
    // regress tests
    procedure NoDeadlockOnGlobalChanRefs1;
    procedure NoDeadlockOnGlobalChanRefs2;
    procedure DelayedDeadlockNotify;
  end;

  TSyncChannelTests = class(TCustomChannelTests)
  protected
    procedure SetUp; override;
    function GetChanSize: Integer; override;
  published
    procedure Sane;
  end;

  TSyncNonThreadChannelTests = class(TCustomChannelTests)
  protected
    procedure SetUp; override;
    function GetChanSize: Integer; override;
  published
    procedure G2GThreaded; override;
    procedure Sane;
  end;

  TAsyncChannelTests = class(TCustomChannelTests)
  const
    BUF_SZ = 5;
  protected
    procedure SetUp; override;
    function GetChanSize: Integer; override;
  published
    procedure Sane;
  end;

  TFanOutTests = class(TTestCase)
  private
    FLog: TStrings;
    FCurBufSz: Integer;
    procedure LogIntegers(const Ch: TChannel<Integer>.TReadOnly;
      const ID, LimitCount: Integer);
    procedure InflateChannelInternal(const Ch: TChannel<Integer>);
    procedure DynamicInternal(const Ch: TChannel<Integer>);
    procedure WriteIntegers(const Ch: TChannel<Integer>.TWriteOnly; const Count: Integer);
    procedure LeaveWithChannelInternal;
    procedure WriteIntegersAndLog(const Ch: TChannel<Integer>.TWriteOnly; const Count: Integer);
    procedure SimpleConsumer(const Ch: TChannel<Integer>.TReadOnly);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure InflateSyncChannel;
    procedure InflateSyncChannelNonThread;
    procedure InflateAsyncChannel;
    procedure DynamicSyncChannel;
    procedure DynamicSyncChannelNonThread;
    procedure DynamicAsyncChannel;
    procedure LeaveWithChannelSyncChannel;
    procedure LeaveWithChannelAsyncChannel;
    procedure BlockProducerOnEmptySyncConsumers;
    procedure BlockProducerOnEmptySyncConsumersNonThread;
    procedure BlockProducerOnEmptyAsyncConsumers;
    procedure UpDownConsumersAsync;
    // TODO: добавить тесты на персистентность вентилятора для инстанса канала
  end;

function GetArrayOfInt(const A: array of Integer): TArrayOfInt;

implementation

{ TIntfTestObj }

destructor TIntfTestObj.Destroy;
begin
  if Assigned(Self.OnDestroy) then
    Self.OnDestroy(Self);
  inherited;
end;

function GetArrayOfInt(const A: array of Integer): TArrayOfInt;
var
  I: Integer;
begin
  SetLength(Result, Length(A));
  for I := 0 to High(A) do
    Result[I] := A[I];
end;

{ TTestObj }

destructor TTestObj.Destroy;
begin
  if Assigned(Self.OnDestroy) then
    Self.OnDestroy(Self);
  inherited;
end;

{ TGCPointerTests }

procedure TGCPointerTests.Interfaces;
var
  Ptr: IGCPointer<IInterface>;
  Value, Actual: IInterface;
  ValueInst: TIntfTestObj;
begin
  ValueInst := TIntfTestObj.Create;
  ValueInst.OnDestroy := Self.LogDestruction;
  Value := ValueInst;

  Ptr := TGCPointerImpl<IInterface>.Create(Value);

  Actual := Ptr.GetValue;
  Check(Actual = Value);

  Value := nil;
  Actual := nil;
  Ptr := nil;
  Check(FLog.Count = 1);
  Check(FLog[0] = 'OnDestroy');
end;

procedure TGCPointerTests.LogDestruction(Sender: TObject);
begin
  FLog.Add('OnDestroy')
end;

procedure TGCPointerTests.Objects;
var
  Ptr: IGCPointer<TObject>;
  Value: TTestObj;
begin
  Value := TTestObj.Create;
  Value.OnDestroy := Self.LogDestruction;

  Ptr := TGCPointerImpl<TObject>.Create(Value);

  Check(Ptr.GetValue = Value);

  Ptr := nil;
  Check(FLog.Count = 1);
  Check(FLog[0] = 'OnDestroy');
end;

procedure TGCPointerTests.SetUp;
begin
  inherited;
  FLog := TStringList.Create;
end;

procedure TGCPointerTests.TearDown;
begin
  inherited;
  FLog.Free;
end;

{ TSyncChannelTests }

function TSyncChannelTests.GetChanSize: Integer;
begin
  Result := 0
end;

procedure TSyncChannelTests.Sane;
var
  Intf: IChannel<Integer>;
begin
  Intf := FIntChannel;
  CheckEquals(0, Intf.GetBufSize)
end;

procedure TSyncChannelTests.SetUp;
begin
  inherited;
  FIntChannel := TChannel<Integer>.Make;
  FStrChannel := TChannel<string>.Make;
  FObjChannel := TChannel<TObject>.Make;
end;

{ TAsyncChannelTests }

function TAsyncChannelTests.GetChanSize: Integer;
begin
  Result := BUF_SZ;
end;

procedure TAsyncChannelTests.Sane;
var
  Intf: IChannel<Integer>;
begin
  Intf := FIntChannel;
  CheckEquals(BUF_SZ, Intf.GetBufSize)
end;

procedure TAsyncChannelTests.SetUp;
begin
  inherited;
  FIntChannel := TChannel<Integer>.Make(BUF_SZ);
  FStrChannel := TChannel<string>.Make(BUF_SZ);
  FObjChannel := TChannel<TObject>.Make(BUF_SZ);
end;

{ TCustomChannelTests }

procedure TCustomChannelTests.BlockProducer;
var
  G: IRawGreenlet;
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(GetChanSize);
  G := TSymmetric<TChannel<Integer>, TArrayOfInt>.Spawn(WriteAndLog, Ch, GetArrayOfInt([1, 2, 3, 4, 5, 6, 7, 8]));
  Check(FLog.Count = GetChanSize+1);
end;

procedure TCustomChannelTests.CasesForRead;
var
  W: IRawGreenlet;
  SR: TSwitchResult;
  Emitter: IGevent;
  Check: TCase<Integer>;
  Index: Integer;
begin
  Emitter := TGevent.Create;
  W := TSymmetric<TIntChannel, TArrayOfInt, IGevent>
    .Spawn(WriteByStep, FIntChannel, GetArrayOfInt([1,2]), Emitter);

  Check < FIntChannel.ReadOnly;

  SR := Switch([Check], Index, 100);
  CheckTrue(SR = srTimeout);

  Emitter.SetEvent;
  SR := Switch([Check], Index, 100);
  CheckTrue(SR = srReadSuccess);
  CheckEquals(0, Index);
  CheckEquals(1, Check);
  CheckTrue(1 = Check);
  CheckTrue(Check = 1);

  SR := Switch([Check], Index, 0);
  CheckTrue(SR = srReadSuccess);
  CheckEquals(1, Check);

  Check < FIntChannel.ReadOnly;
  Emitter.SetEvent;
  SR := Switch([Check], Index, 100);
  CheckTrue(SR = srReadSuccess);
  CheckEquals(0, Index);
  CheckEquals(2, Check);

  W.Kill;
  Check < FIntChannel.ReadOnly;
  SR := Switch([Check], Index, 100);
  CheckTrue(SR = srTimeout);
end;

procedure TCustomChannelTests.ChatRoutine(const Nick: string; const Ch: TChannel<string>);
var
  Sender, Dest, Msg, Raw: string;
begin
  for Raw in Ch do begin
    DeserializeChatMessage(Raw, Sender, Dest, Msg);
    if Dest = Nick then begin
      FLog.Add(Format('%s received (%s) from %s', [Nick, Msg, Sender]));
    end
    else begin
      // send back to environment
      Ch.Write(Raw)
    end;
  end;
end;

procedure TCustomChannelTests.DeadlockChannel;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(DeadlockReadChan, TSoftDeadlock, 'Read error');
    CheckException(DeadlockWriteChan, TSoftDeadlock, 'Write error')
  finally
    StdDeadLockException :=  DLE;
  end;
end;


procedure TCustomChannelTests.DeadlockOnExit;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(MakeDeadlockReadOnExit, TSoftDeadlock, 'Read error');
    CheckException(MakeDeadlockWriteOnExit, TSoftDeadlock, 'Write error')
  finally
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.DeadlockReadChan;
var
  G: IRawGreenlet;
  Ch: TChannel<Integer>;
  Val: Integer;

  procedure Internal;
  begin
    Ch := TChannel<Integer>.Make(GetChanSize);
    G := TSymmetric<TChannel<Integer>>.Spawn(LogReadChan, Ch)
  end;

begin
  Internal;
  Ch.Read(Val);
end;

procedure TCustomChannelTests.DeadlockReadonly;
var
  G: IRawGreenlet;
  Val: Integer;
  Ch: TChannel<Integer>;

  procedure Internal;
  begin
    Ch := TChannel<Integer>.Make(GetChanSize);
    G := TSymmetric<TChannel<Integer>.TReadOnly>.Spawn(LogReadonly, Ch.ReadOnly)
  end;

begin
  Internal;
  Ch.Read(Val)
end;

procedure TCustomChannelTests.DeadLockRWOnlyChannel;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(DeadLockReadOnly, TSoftDeadlock);
    CheckException(DeadlockWriteonly, TSoftDeadlock)
  finally
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.DeadLockSelf;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(MakeDeadlockChanWrite, TSoftDeadlock);
    CheckException(MakeDeadlockChanRead, TSoftDeadlock)
  finally
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.DeadlockWriteChan;
var
  G: IRawGreenlet;

  procedure Internal;
  var
    Ch: TChannel<Integer>;
  begin
    Ch := TChannel<Integer>.Make;
    G := TSymmetric<TArrayOfInt, TChannel<Integer>>
      .Spawn(Write2IntChannel, GetArrayOfInt([1,2,3,4,0,9,8,7]), Ch)
  end;

begin
  Internal;
  Join([G], INFINITE, True);
end;

procedure TCustomChannelTests.DeadlockWriteonly;
var
  G: IRawGreenlet;
  var
    Ch: TChannel<Integer>;

  procedure Internal;
  begin
    Ch := TChannel<Integer>.Make(GetChanSize);
    G := TSymmetric<TArrayOfInt, TChannel<Integer>.TWriteOnly>
      .Spawn(Write2IntChannel2, GetArrayOfInt([1,2,3,4,0,9,8,7]), Ch.WriteOnly)
  end;

begin
  Internal;
  Ch.Write(1)
end;

procedure TCustomChannelTests.DelayedDeadlockNotify;
begin
  {проверка на то что оповещение о дедлоках всегда приходит через
   асинхр механизм хаба. Это избавит от лишних Exceptions при закрытии приложения
   когда во всех каналах лавиной начнут срабатывать _Release
  }

end;

procedure TCustomChannelTests.DeserializeChatMessage(const Raw: string;
  out Sender, Dest, Msg: string);
begin
  Sender := Raw.Split([','])[0];
  Dest := Raw.Split([','])[1];
  Msg := Raw.Split([','])[2];
end;

procedure TCustomChannelTests.G2G;
var
  R, W: IRawGreenlet;
begin
  R := TSymmetric<TIntChannel, TArrayOfInt>.Create(Read2IntChannel,
    FIntChannel, GetArrayOfInt([1,2,3,4,0,9,8,7]));
  W := TSymmetric<TArrayOfInt, TIntChannel>.Create(Write2IntChannel,
    GetArrayOfInt([1,2,3,4,0,9,8,7]), FIntChannel);
  Join([R, W])
end;

procedure TCustomChannelTests.G2GPingPong;
var
  Pinger, Ponger: IRawGreenlet;
  Stop, Start: TTime;
begin
  Start := Now;
  Pinger := TSymmetric<Integer, TIntChannel>.Spawn(Ping, BIG_TEST_COUNTER, FIntChannel);
  Ponger := TSymmetric<TIntChannel>.Spawn(Pong, FIntChannel);
  Join([Pinger, Ponger]);
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.G2GStress;
var
  R, W: IRawGreenlet;
  Stop, Start: TTime;
begin
  Start := Now;
  R := TSymmetric<Integer, TIntChannel>.Create(Write2IntChannelStress,
    BIG_TEST_COUNTER, FIntChannel);
  W := TSymmetric<TIntChannel>.Create(Read2IntChannelStress, FIntChannel);
  Join([R, W]);
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.G2GThreaded;
const
  TEST_COUNT = BIG_TEST_COUNTER div 10;
var
  R, W: IRawGreenlet;
  Stop, Start: TTime;
begin
  Start := Now;
  R := TSymmetric<TIntChannel, Integer>.Create(Read2IntChannelThreaded,
   FIntChannel, TEST_COUNT);
  W := TSymmetric<Integer, TIntChannel>.Create(Write2IntChannelThreaded,
    TEST_COUNT, FIntChannel);
  Join([R, W]);
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [TEST_COUNT, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.G2R;
var
  W: IRawGreenlet;
  Actual: Integer;
begin
  W := TSymmetric<TArrayOfInt, TIntChannel>.Spawn(Write2IntChannel,
   GetArrayOfInt([1,2,3,9,8,7]), FIntChannel);
  while FIntChannel.Read(Actual) do begin
    if Actual = 0 then
      Break;
    FLog.Add(IntToStr(Actual));
  end;
  Check(FLog.CommaText = '1,2,3,9,8,7');
end;

procedure TCustomChannelTests.G2RStress;
var
  W: IRawGreenlet;
  Stop, Start: TTime;
  Value: Integer;
begin
  Start := Now;
  W := TSymmetric<Integer, TIntChannel>.Spawn(Write2IntChannelStress,
    BIG_TEST_COUNTER, FIntChannel);
  while FIntChannel.Read(Value) do
    ;
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.GC1;
var
  W: IRawGreenlet;
  Rd1, Rd2, Rd3: TObject;

  procedure InternalRun;
  begin
    W := TSymmetric<TObject, TObjChannel>.Spawn(Write2ObjChannel, nil, FObjChannel);
    Rd1 := FObjChannel.Get;
    Rd2 := FObjChannel.Get;
    Rd3 := FObjChannel.Get;
    W := nil;
  end;

begin
  InternalRun;
  // уничтожим и канал чтоб почистить ссылки
  FObjChannel := tChannel<TObject>.Make;
  //и проверяем ссылки
  CheckFalse(TGarbageCollector.ExistsInGlobal(Rd1));
  CheckFalse(TGarbageCollector.ExistsInGlobal(Rd2));
  // Rd3 должен лежать в тек контексте
  CheckFalse(TGarbageCollector.ExistsInGlobal(Rd3));
end;

procedure TCustomChannelTests.GCStress;
const
  STRESS_COUNT = BIG_TEST_COUNTER div 10;
var
  Chan: TChannel<TTestObj>;
  Start, Stop: TTime;
  Producer, Consumer: IRawGreenlet;
begin
  Chan := TChannel<TTestObj>.Make(GetChanSize);
  Start := Now;
  Producer := TSymmetric<TChannel<TTestObj>.TReadOnly>.Spawn(ReadTestObj, Chan.ReadOnly);
  Consumer := TSymmetric<TChannel<TTestObj>.TWriteOnly, Integer>.Spawn(WriteTstObj, Chan.WriteOnly, STRESS_COUNT);
  Join([Producer, Consumer]);
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [STRESS_COUNT, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.InfiniteClose(const Ch: TChannel<Integer>);
begin
  while True do
    Ch.Close
end;

procedure TCustomChannelTests.InfiniteRead(const Ch: TChannel<Integer>);
var
  Value: Integer;
begin
  while True do
    Ch.Read(Value)
end;

procedure TCustomChannelTests.InfiniteWrite(const Ch: TChannel<Integer>);
begin
  while True do
    Ch.Write(1)
end;

procedure TCustomChannelTests.IsNull;
var
  Ch: TChannel<Integer>;
  Readonly: TChannel<Integer>.TReadOnly;
  WriteOnly: TChannel<Integer>.TWriteOnly;
begin
  Check(Ch.IsNull);
  Check(Readonly.IsNull);
  Check(WriteOnly.IsNull);

  Ch := TChannel<Integer>.Make(GetChanSize);
  CheckFalse(Ch.IsNull);

  Readonly := Ch.ReadOnly;
  WriteOnly := Ch.WriteOnly;
  CheckFalse(Readonly.IsNull);
  CheckFalse(WriteOnly.IsNull);

end;

procedure TCustomChannelTests.LeaveLockClose;
var
  LLE: ExceptionClass;
  DLE: ExceptionClass;
begin
  LLE := StdLeaveLockException;
  StdLeaveLockException := TSoftDeadlock;
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(MakeLeaveLockCloseChan, TSoftDeadlock);
  finally
    StdLeaveLockException :=  LLE;
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.LeaveLockReadWrite;
var
  LLE: ExceptionClass;
  DLE: ExceptionClass;
begin
  LLE := StdLeaveLockException;
  StdLeaveLockException := TSoftDeadlock;
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    CheckException(MakeLeaveLockReadChan, TSoftDeadlock);
    CheckException(MakeLeaveLockWriteChan, TSoftDeadlock)
  finally
    StdLeaveLockException :=  LLE;
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.LogReadChan(const Ch: TChannel<Integer>);
var
  I: Integer;
begin
  for I in Ch do
    FLog.Add(IntToStr(I))
end;

procedure TCustomChannelTests.LogReadonly(
  const Ch: TChannel<Integer>.TReadOnly);
var
  I: Integer;
begin
  for I in Ch do
    FLog.Add(IntToStr(I))
end;

procedure TCustomChannelTests.LostUpdate1;
var
  G: IRawGreenlet;
  I: Integer;
begin
  G := TSymmetric<Integer, TStrChannel>.Spawn(LostUpdateRoutine, 300, FStrChannel);
  for I := 1 to 10 do
    FStrChannel.Write(IntToStr(I));
  FStrChannel.Close;
  Join([G]);
  CheckEquals(FLog.Count, 10);

  FLog.Clear;
  G := TSymmetric<TArrayOfInt, TIntChannel>.Spawn(Write2IntChannel,
    GetArrayOfInt([0,1,2,3,4,5,6,7,8,9]), FIntChannel);
  for I in FIntChannel do
    FLog.Add(IntToStr(I));
  CheckEquals(FLog.Count, 10);
end;

procedure TCustomChannelTests.LostUpdate2;
var
  G1, G2: IRawGreenlet;
  I: Integer;
begin
  G1 := TSymmetric<Integer, TStrChannel>.Spawn(LostUpdateRoutine, 300, FStrChannel);
  G2 := TSymmetric<Integer, TStrChannel>.Spawn(LostUpdateRoutine, 300, FStrChannel);
  for I := 1 to 10 do
    FStrChannel.Write(IntToStr(I));
  FStrChannel.Close;
  Join([G1, G2]);
  CheckEquals(FLog.Count, 10);
end;

procedure TCustomChannelTests.LostUpdateRoutine(const DelayToStart: Integer;
  const Ch: TChannel<string>);
var
  S: string;
begin
  GreenSleep(DelayToStart);
  for S in Ch do begin
    FLog.Add(S)
  end;
end;

procedure TCustomChannelTests.MakeDeadlockChanRead;
var
  Chan: TChannel<Integer>;
  Value: Integer;
begin
  Chan := TChannel<Integer>.Make(GetChanSize);
  Chan.Read(Value);
end;

procedure TCustomChannelTests.MakeDeadlockChanWrite;
var
  Chan: TChannel<Integer>;
begin
  Chan := TChannel<Integer>.Make(GetChanSize);
  Chan.Write(0)
end;

procedure TCustomChannelTests.MakeDeadlockReadOnExit;
var
  R1, R2: IRawGreenlet;

  procedure Internal;
  var
    Ch: TChannel<Integer>;
  begin
    Ch := TChannel<Integer>.Make(GetChanSize);
    R1 := TSymmetric<TChannel<Integer>>.Spawn(LogReadChan, Ch);
    R2 := TSymmetric<TChannel<Integer>>.Spawn(LogReadChan, Ch);
  end;

begin
  Internal;
  Join([R1, R2], INFINITE, True)
end;

procedure TCustomChannelTests.MakeDeadlockWriteOnExit;
var
  R1, R2: IRawGreenlet;

  procedure Internal;
  var
    Ch: TChannel<Integer>;
  begin
    Ch := TChannel<Integer>.Make(GetChanSize);
    R1 := TSymmetric<TArrayOfInt, TChannel<Integer>>
      .Spawn(Write2IntChannel, GetArrayOfInt([1,2,3,4,0,9,8,7]), Ch);
    R2 := TSymmetric<TArrayOfInt, TChannel<Integer>>
      .Spawn(Write2IntChannel, GetArrayOfInt([1,2,3,4,0,9,8,7]), Ch)
  end;

begin
  Internal;
  Join([R1, R2], INFINITE, True)
end;

procedure TCustomChannelTests.MakeLeaveLockCloseChan;
var
  G: IRawGreenlet;
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(GetChanSize);
  G := TSymmetric<TChannel<Integer>>.Spawn(InfiniteClose, Ch);
  Join([G], INFINITE, True)
end;

procedure TCustomChannelTests.MakeLeaveLockReadChan;
var
  G: IRawGreenlet;
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(GetChanSize);
  G := TSymmetric<TChannel<Integer>>.Spawn(InfiniteRead, Ch);
  Ch.Close;
  Join([G], INFINITE, True)
end;

procedure TCustomChannelTests.MakeLeaveLockWriteChan;
var
  G: IRawGreenlet;
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(GetChanSize);
  G := TSymmetric<TChannel<Integer>>.Spawn(InfiniteWrite, Ch);
  Ch.Close;
  Join([G], INFINITE, True)
end;

procedure TCustomChannelTests.MakeNoDeadLockReadChan1;
begin
  FGlobalChan := TChannel<Integer>.Make(GetChanSize);
  FGlobGreenlet := TSymmetric<TChannel<Integer>.TReadOnly>.Spawn(LogReadonly, FGlobalChan.ReadOnly);
end;

procedure TCustomChannelTests.MakeNoDeadLockReadChan2;
begin
  FGlobalChan := TChannel<Integer>.Make(GetChanSize);
  FGlobGreenlet := TSymmetric<TChannel<Integer>>.Spawn(LogReadChan, FGlobalChan);
end;

procedure TCustomChannelTests.MultiChat;
var
  Mike, Bob: TSymmetric<string, TStrChannel>;
begin
  Bob := TSymmetric<string, TStrChannel>.Spawn(ChatRoutine, 'bob', FStrChannel);
  Mike := TSymmetric<string, TStrChannel>.Spawn(ChatRoutine, 'mike', FStrChannel);
  FStrChannel.Write(SerializeChatMessage('tom', 'mike', 'hallo'));
  FStrChannel.Write(SerializeChatMessage('tom', 'bob', 'hi'));
  FStrChannel.Write(SerializeChatMessage('tom', 'mike', 'how are you?'));
  FStrChannel.Write(SerializeChatMessage('tom', 'mike', 'bye'));
  FStrChannel.Close;
  Check(FLog.Count = 4);
  Check(FLog[0] = 'mike received (hallo) from tom');
  Check(FLog[1] = 'bob received (hi) from tom');
  Check(FLog[2] = 'mike received (how are you?) from tom');
  Check(FLog[3] = 'mike received (bye) from tom');
end;

procedure TCustomChannelTests.NoDeadlockOnGlobalChanRefs1;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    MakeNoDeadLockReadChan1;
    Check(FGlobGreenlet.GetState <> gsException, 'deadlock exception raised');
  finally
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.NoDeadlockOnGlobalChanRefs2;
var
  DLE: ExceptionClass;
begin
  DLE := StdDeadLockException;
  StdDeadLockException := TSoftDeadlock;
  try
    MakeNoDeadLockReadChan2;
    Check(FGlobGreenlet.GetState <> gsException, 'deadlock exception raised');
  finally
    StdDeadLockException :=  DLE;
  end;
end;

procedure TCustomChannelTests.PendingRead1;
var
  W: IRawGreenlet;
  WR: TWaitResult;
  Future: IFuture<Integer, TPendingError>;
  Emitter: IGevent;
  Index: Integer;
begin
  Emitter := TGevent.Create;
  W := TSymmetric<TIntChannel, TArrayOfInt, IGevent>
    .Spawn(WriteByStep, FIntChannel, GetArrayOfInt([1,111]), Emitter);

  Emitter.SetEvent;
  Future := FIntChannel.ReadPending;
  Future.OnFullFilled.WaitFor;
  CheckEquals(1, Future.GetResult);

  Check(Future.OnFullFilled.WaitFor(100) = wrSignaled);
  Emitter.SetEvent;
  Future := FIntChannel.ReadPending;
  Future.OnFullFilled.WaitFor;
  CheckEquals(111, Future.GetResult);

  W.Kill;
  Future := FIntChannel.ReadPending;
  WR := Select([Future.OnFullFilled, Future.OnRejected], Index, 100);
  Check(WR = wrTimeout);

  FIntChannel.Close;
  Future := FIntChannel.ReadPending;
  WR := Select([Future.OnFullFilled, Future.OnRejected], Index, 100);
  Check(WR = wrSignaled);
  CheckEquals(1, Index);
  Check(Future.GetErrorCode = psClosed);

end;

procedure TCustomChannelTests.PendingWrite1;
var
  R: IRawGreenlet;
  WR: TWaitResult;
  Future: IFuture<Integer, TPendingError>;
  Emitter: IGevent;
  Index: Integer;
begin
  Emitter := TGevent.Create;
  R := TSymmetric<TIntChannel, IGevent>
    .Spawn(ReadByStep, FIntChannel, Emitter);

  if GetChanSize = 0 then begin
    Future := FIntChannel.WritePending(1);
    WR := Future.OnFullFilled.WaitFor(100);
    Check(WR = wrTimeout);
    Emitter.SetEvent;
    WR := Future.OnFullFilled.WaitFor(1000);
    Check(WR = wrSignaled);
    CheckEquals(1, Future.GetResult);

    Check(Future.OnFullFilled.WaitFor(100) = wrSignaled);
    Future := FIntChannel.WritePending(2);
    WR := Future.OnFullFilled.WaitFor(100);
    Check(WR = wrTimeout);

    Emitter.SetEvent;
    Check(Future.OnFullFilled.WaitFor(100) = wrSignaled);
    CheckEquals(2, Future.GetResult);

    FIntChannel.Close;
    Future := FIntChannel.WritePending(3);
    WR := Select([Future.OnFullFilled, Future.OnRejected], Index, 100);
    Check(WR = wrSignaled);
    Check(Index = 1);
    Check(Future.GetErrorCode = psClosed);
  end
  else begin
    Future := FIntChannel.WritePending(100);
    WR := Future.OnFullFilled.WaitFor(100);
    Check(WR = wrSignaled);
    CheckEquals(100, Future.GetResult);
  end;
end;

procedure TCustomChannelTests.Ping(const Count: Integer; const Ch: TChannel<Integer>);
var
  vPing, vPong: Integer;
begin
  vPing := Count;
  while vPing >= 0 do begin
    Ch.Write(vPing);
    Ch.Read(vPong);
    Check(vPing - vPong = 1, 'Ping - Pong != 1');
    vPing := vPong - 1;
  end;
  Ch.Close;
end;

procedure TCustomChannelTests.Pong(const Ch: TChannel<Integer>);
var
  vPing, vPong: Integer;
begin
  for vPing in Ch do begin
    vPong := vPing - 1;
    Ch.Write(vPong);
  end;
end;

procedure TCustomChannelTests.R2G;
var
  R: IRawGreenlet;
  Actual: Integer;
begin
  R := TSymmetric<TIntChannel, TArrayOfInt>.Spawn(Read2IntChannel,
   FIntChannel,  GetArrayOfInt([1,2,3,4,5,6,7,8,9]));
  Actual := 1;
  while Actual < 10 do begin
    FIntChannel.Write(Actual);
    Check(R.GetState in [gsExecute, gsSuspended]);
    Inc(Actual);
  end;
  FIntChannel.Close;
  Check(Join([R], 100));
end;

procedure TCustomChannelTests.R2GStress;
var
  R: IRawGreenlet;
  Stop, Start: TTime;
  Value: Integer;
begin
  Start := Now;
  R := TSymmetric<TIntChannel>.Spawn(Read2IntChannelStress, FIntChannel);
  for Value := 0 to BIG_TEST_COUNTER do
    FIntChannel.Write(Value);
  FIntChannel.Close;
  Join([R]);
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
end;

procedure TCustomChannelTests.Read2IntChannel(const Ch: TChannel<Integer>; const Values: TArrayOfInt);
var
  Expected: Integer;
  Actual, Index: Integer;
begin
  Index := 0;
  for Actual in FIntChannel do begin
    Expected := Values[Index];
    Check(Expected = Actual);
    Inc(Index);
  end;
end;

procedure TCustomChannelTests.Read2IntChannelStress(const Ch: TChannel<Integer>);
var
  Value, Counter: Integer;
begin
  Counter := 0;
  while Ch.Read(Value) do begin
    Counter := Counter + 1;
  end;
  FLog.Add(IntToStr(Counter))
end;

procedure TCustomChannelTests.Read2IntChannelThreaded(const Ch: TChannel<Integer>;
  const Count: Integer);
var
  Value, Expected: Integer;
begin
  BeginThread;
  Expected := Count;
  for Value in Ch do begin
    Check(Value = Expected, Format('Reader Value <> Expected, %d <> %d', [Value, Expected]));
    Dec(Expected);
  end;
end;

procedure TCustomChannelTests.ReadByStep(const Ch: TChannel<Integer>;
  const Emitter: IGevent);
var
  Value: Integer;
begin
  while True do begin
    Emitter.WaitFor;
    if not Ch.Read(Value) then
      Exit
  end;
end;

procedure TCustomChannelTests.ReadTestObj(
  const Input: TChannel<TTestObj>.TReadOnly);
var
  I: TTestObj;
begin
  for I in Input do
    Check(Assigned(I));
end;

procedure TCustomChannelTests.RunInternalDeadlockAndRead;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(GetChanSize);
  FGlobGreenlet := TSymmetric<TChannel<Integer>.TReadOnly>.Spawn(SetInternalDeadlockAndRead, Ch.ReadOnly);
end;

function TCustomChannelTests.SerializeChatMessage(const Sender, Dest,
  Msg: string): string;
begin
  Result := string.Join(',', [Sender, Dest, Msg])
end;

procedure TCustomChannelTests.SetInternalDeadlockAndRead(
  const Ch: TChannel<Integer>.TReadOnly);
var
  I: Integer;
begin
  Ch.DeadlockEsxception := TInternalDeadLock;
  for I in Ch do begin
    if I = MaxInt then Exit // hide hint
    
  end;
end;

procedure TCustomChannelTests.SetSelfDeadlockException;
begin
  RunInternalDeadlockAndRead;
  GreenSleep(100);
  Check(FGlobGreenlet.GetState = gsException);
  Check(FGlobGreenlet.GetException.ClassType = TInternalDeadLock);
end;

procedure TCustomChannelTests.SetUp;
begin
  inherited;
  FLog := TStringList.Create;
end;

procedure TCustomChannelTests.SwitchForRead;
var
  W: IRawGreenlet;
  SR: TSwitchResult;
  Emitter: IGevent;
  CaseRead: TCase<Integer>;
  ReadSet, WriteSet, ErrorSet: TCaseSet;
begin
  Emitter := TGevent.Create;
  W := TSymmetric<TIntChannel, TArrayOfInt, IGevent>
    .Spawn(WriteByStep, FIntChannel, GetArrayOfInt([1,2,3,4,5]), Emitter);

  CaseRead < FIntChannel;
  ReadSet := ReadSet + CaseRead;
  ErrorSet := ReadSet;

  SR := Switch(ReadSet, WriteSet, ErrorSet, 100);
  CheckTrue(SR = srTimeout);
  CheckTrue(ReadSet.Has(CaseRead));
  CheckFalse(WriteSet.Has(CaseRead));
  CheckTrue(ErrorSet.Has(CaseRead));

  Emitter.SetEvent;
  SR := Switch(ReadSet, WriteSet, ErrorSet, 100);
  CheckTrue(SR = srReadSuccess);
  CheckTrue(ReadSet.Has(CaseRead));
  CheckFalse(WriteSet.Has(CaseRead));
  CheckFalse(ErrorSet.Has(CaseRead));
  CheckEquals(1, CaseRead);

  CaseRead < FIntChannel;
  Emitter.SetEvent;
  SR := Switch(ReadSet, WriteSet, ErrorSet, 100);
  CheckTrue(SR = srReadSuccess);
  CheckTrue(ReadSet.Has(CaseRead));
  CheckFalse(WriteSet.Has(CaseRead));
  CheckFalse(ErrorSet.Has(CaseRead));
  CheckEquals(2, CaseRead);

  FIntChannel.Close;
  CaseRead < FIntChannel;
  SR := Switch(ReadSet, WriteSet, ErrorSet, 100);
  CheckTrue(SR = srTimeout);

  ErrorSet := ReadSet;
  SR := Switch(ReadSet, WriteSet, ErrorSet, 100);
  CheckTrue(SR = srClosed);
  CheckFalse(ReadSet.Has(CaseRead));
  CheckFalse(WriteSet.Has(CaseRead));
  CheckTrue(ErrorSet.Has(CaseRead));

end;

procedure TCustomChannelTests.TearDown;
begin
  inherited;
  FLog.Free;
  FGlobGreenlet := nil;
end;

procedure TCustomChannelTests.Write2IntChannel(const Values: TArrayOfInt; const Ch: TChannel<Integer>);
var
  Val: Integer;
begin
  for Val in Values do begin
    FIntChannel.Write(Val)
  end;
  FIntChannel.Close;
end;

procedure TCustomChannelTests.Write2IntChannel2(const Values: TArrayOfInt;
  const Ch: TChannel<Integer>.TWriteOnly);
var
  Val: Integer;
begin
  for Val in Values do begin
    FIntChannel.Write(Val)
  end;
  FIntChannel.Close;
end;

procedure TCustomChannelTests.Write2IntChannelStress(const Count: Integer;
  const Ch: TChannel<Integer>);
var
  Value: Integer;
begin
  Value := Count;
  while Value >= 0 do begin
    Ch.Write(Value);
    Dec(Value);
  end;
  Ch.Close;
end;

procedure TCustomChannelTests.Write2IntChannelThreaded(const Count: Integer;
  const Ch: TChannel<Integer>);
var
  Value: Integer;
begin
  BeginThread;
  Value := Count;
  while Value > 0 do begin
    Ch.Write(Value);
    Dec(Value);
  end;
  Ch.Close;
end;

procedure TCustomChannelTests.Write2ObjChannel(const A: TObject;const Ch: TChannel<TObject>);
begin
  if Assigned(A) then
    Ch.Write(A);
  while not Ch.IsClosed do
    Ch.Write(TTestObj.Create)
end;

procedure TCustomChannelTests.WriteAndLog(const Ch: TChannel<Integer>;
  const Values: TArrayOfInt);
var
  I: Integer;
begin
  for I in Values do begin
    FLog.Add(IntToStr(I));
    Ch.Write(I);
  end;
  Ch.Close;
end;

procedure TCustomChannelTests.WriteByStep(const Ch: TChannel<Integer>;
  const Values: TArrayOfInt; const Emitter: IGevent);
var
  I: Integer;
begin
  for I := 0 to High(Values) do begin
    Emitter.WaitFor;
    Ch.Write(Values[I]);
  end;
end;

procedure TCustomChannelTests.WriteTstObj(
  const Output: TChannel<TTestObj>.TWriteOnly; const Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Count do begin
    Output.Write(TTestObj.Create)
  end;
  Output.Close;
end;

{ TContractTests }

procedure TContractTests.G2GLightEvPingPong;
var
  Stop, Start: TTime;
begin
  FPing := TSymmetric<Integer>.Spawn(PingSyncLightGevent, BIG_TEST_COUNTER);
  FPong := TSymmetric<Boolean>.Spawn(PongSyncLightGevent, False);
  Start := Now;
  Check(Join([FPing, FPong], 3000), Format('Timeout: FValue: %d', [FValue]));
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
  FPing := nil;
  FPong := nil;
end;

procedure TContractTests.G2GSyncFast;
var
  Stop, Start: TTime;
  Shared: PInteger;
begin
  Shared := @FValue;
  FPing := TSymmetric<Integer, PInteger>.Spawn(PingFast, BIG_TEST_COUNTER, Shared);
  FPong := TSymmetric<PInteger>.Spawn(PongFast, Shared);
  Start := Now;
  Check(Join([FPing, FPong], 3000));
  Stop := Now;
  {$IFDEF DEBUG}
  DebugString(Format('counter: %d timeout = %d',
    [BIG_TEST_COUNTER, GreenletsImpl.Time2TimeOut(Stop-Start)]));
  {$ENDIF};
  FPing := nil;
  FPong := nil;
end;


procedure TContractTests.PingFast(const Count: Integer;
  const Shared: PInteger);
var
  Ping, Pong: Integer;
begin
  Greenlets.Yield;
  Ping := Count;
  while Ping >= 0 do begin
    Shared^ := Ping;
    FPong.Switch;
    Pong := Shared^;
    Check(Ping - Pong = 1, 'Ping - Pong != 1');
    Dec(Ping);
  end;
end;

procedure TContractTests.PingSyncLightGevent(const Count: Integer);
var
  Ping, Pong: Integer;
  E: TLightGevent;
begin
  E := TLightGevent.Create;
  FLightPair.E1 := E;
  Greenlets.Yield;
  Ping := Count;
  while Ping > 0 do begin
    FValue := Ping;
    FLightPair.E2.SetEvent;
    E.WaitEvent;
    Pong := FValue;
    Check(Ping - Pong = 1, 'Ping - Pong != 1');
    Dec(Ping);
  end;
  FLightPair.E2.SetEvent;
end;

procedure TContractTests.PongFast(const Shared: PInteger);
var
  Ping, Pong: Integer;
begin
  Greenlets.Yield;
  while True do begin
    Ping := Shared^;
    Pong := Ping - 1;
    Shared^ := Pong;
    FPing.Switch;
    if Ping = 0 then
      Exit;
  end;
end;

procedure TContractTests.PongSyncLightGevent(const Threaded: Boolean);
var
  Ping: Integer;
  E: TLightGevent;
begin
  E := TLightGevent.Create;
  FLightPair.E2 := E;
  Greenlets.Yield;
  if Threaded then
    BeginThread;
  while True do begin
    E.WaitEvent;
    Ping := FValue - 1;
    FValue := Ping;
    FLightPair.E1.SetEvent;
    if Ping <= 0 then
      Exit;
  end;
  FLightPair.E1.SetEvent;
end;


procedure TContractTests.SetUp;
begin
  inherited;
  FLog := TStringList.Create;
end;

procedure TContractTests.TearDown;
begin
  inherited;
  FLog.Free;
end;

{ TSyncNonThreadChannelTests }

procedure TSyncNonThreadChannelTests.G2GThreaded;
begin
  CheckTrue(True);
end;

function TSyncNonThreadChannelTests.GetChanSize: Integer;
begin
  Result := 0;
end;

procedure TSyncNonThreadChannelTests.Sane;
var
  Intf: IChannel<Integer>;
begin
  Intf := FIntChannel;
  CheckEquals(0, Intf.GetBufSize)
end;

procedure TSyncNonThreadChannelTests.SetUp;
begin
  inherited;
  FIntChannel := TChannel<Integer>.Make(0, False);
  FStrChannel := TChannel<string>.Make(0, False);
  FObjChannel := TChannel<TObject>.Make(0, False);
end;

{ TFanOutTests }

procedure TFanOutTests.BlockProducerOnEmptyAsyncConsumers;
var
  Chan: TChannel<Integer>;
  FanOut: TFanOut<Integer>;
  G: IRawGreenlet;
begin
  Chan := TChannel<Integer>.Make(5);
  FanOut := TFanOut<Integer>.Make(Chan.ReadOnly);

  G := TSymmetric<TChannel<Integer>.TWriteOnly, Integer>
    .Spawn(WriteIntegersAndLog, Chan.WriteOnly, 50);

  Check(FLog.Count = 6);

end;

procedure TFanOutTests.BlockProducerOnEmptySyncConsumers;
var
  Chan: TChannel<Integer>;
  FanOut: TFanOut<Integer>;
  G: IRawGreenlet;
begin
  Chan := TChannel<Integer>.Make;
  FanOut := TFanOut<Integer>.Make(Chan.ReadOnly);

  G := TSymmetric<TChannel<Integer>.TWriteOnly, Integer>
    .Spawn(WriteIntegersAndLog, Chan.WriteOnly, 50);

  Check(FLog.Count = 1);

end;

procedure TFanOutTests.BlockProducerOnEmptySyncConsumersNonThread;
var
  Chan: TChannel<Integer>;
  FanOut: TFanOut<Integer>;
  G: IRawGreenlet;
begin
  Chan := TChannel<Integer>.Make(0, False);
  FanOut := TFanOut<Integer>.Make(Chan.ReadOnly);

  G := TSymmetric<TChannel<Integer>.TWriteOnly, Integer>
    .Spawn(WriteIntegersAndLog, Chan.WriteOnly, 50);

  Check(FLog.Count = 1);

end;

procedure TFanOutTests.DynamicAsyncChannel;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(1);
  DynamicInternal(Ch);
end;

procedure TFanOutTests.DynamicInternal(const Ch: TChannel<Integer>);
var
  FanOut: TFanOut<Integer>;
  Group: TGreenGroup<Integer>;
begin
  FanOut := TFanOut<Integer>.Make(Ch.ReadOnly);

  Group[0] := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
    .Spawn(LogIntegers, FanOut.Inflate, 1, 2);
  Group[1] := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
    .Spawn(LogIntegers, FanOut.Inflate, 2, 1000);

  Ch.Write(1);
  Ch.Write(2);
  Ch.Write(3);
  Ch.Write(4);
  Ch.Write(5);
  Ch.Write(6);
  Ch.Write(7);
  Ch.Write(8);
  Ch.Close;

  Check(Group.Join(1000), 'Group.Join timeout');

  CheckEquals(10, FLog.Count);
  CheckEquals('log[1][1]', FLog[0]);
  CheckEquals('log[2][1]', FLog[1]);
  CheckEquals('log[1][2]', FLog[2]);
  CheckEquals('log[2][2]', FLog[3]);
  CheckEquals('log[2][3]', FLog[4]);
  CheckEquals('log[2][4]', FLog[5]);
  CheckEquals('log[2][8]', FLog[9]);
end;

procedure TFanOutTests.DynamicSyncChannel;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make;
  DynamicInternal(Ch);
end;

procedure TFanOutTests.DynamicSyncChannelNonThread;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(0, False);
  DynamicInternal(Ch);
end;

procedure TFanOutTests.InflateAsyncChannel;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(1);
  InflateChannelInternal(Ch);
end;

procedure TFanOutTests.InflateSyncChannel;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make;
  InflateChannelInternal(Ch);
end;

procedure TFanOutTests.InflateSyncChannelNonThread;
var
  Ch: TChannel<Integer>;
begin
  Ch := TChannel<Integer>.Make(0, False);
  InflateChannelInternal(Ch);
end;

procedure TFanOutTests.InflateChannelInternal(
  const Ch: TChannel<Integer>);
var
  FanOut: TFanOut<Integer>;
  Group: TGreenGroup<Integer>;
begin
  FanOut := TFanOut<Integer>.Make(Ch.ReadOnly);

  Group[0] := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
    .Spawn(LogIntegers, FanOut.Inflate, 1, 1000);
  Group[1] := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
    .Spawn(LogIntegers, FanOut.Inflate, 2, 1000);

  Ch.Write(1);
  Ch.Write(2);
  Ch.Write(3);
  Ch.Write(4);
  Ch.Write(5);
  Ch.Write(6);
  Ch.Write(7);
  Ch.Close;

  Check(Group.Join(1000), 'Group.Join timeout');

  CheckEquals(14, FLog.Count);
  CheckEquals('log[1][1]', FLog[0]);
  CheckEquals('log[2][1]', FLog[1]);
  CheckEquals('log[1][2]', FLog[2]);
  CheckEquals('log[2][2]', FLog[3]);

  CheckEquals('log[1][7]', FLog[12]);
  CheckEquals('log[2][7]', FLog[13]);
end;


procedure TFanOutTests.LeaveWithChannelAsyncChannel;
begin
  FCurBufSz := 1;
  LeaveWithChannelInternal;
end;

procedure TFanOutTests.LeaveWithChannelInternal;
var
  G1, G2: IRawGreenlet;
  Producer: IRawGreenlet;

  procedure Internal;
  var
    FanOut: TFanOut<Integer>;
    Ch: TChannel<Integer>;
  begin
    Ch := TChannel<Integer>.Make(FCurBufSz);
    FanOut := TFanOut<Integer>.Make(Ch.ReadOnly);
    G1 := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
      .Spawn(LogIntegers, FanOut.Inflate, 1, 100);
    G2 := TSymmetric<TChannel<Integer>.TReadOnly, Integer, Integer>
      .Spawn(LogIntegers, FanOut.Inflate, 2, 100);
    Producer := TSymmetric<TChannel<Integer>.TWriteOnly, Integer>
      .Spawn(WriteIntegers, Ch.WriteOnly, 10);
  end;

begin
  Internal;
  Join([G1, G2, Producer], INFINITE, True);
  Check(FLog.Count = 20);
end;

procedure TFanOutTests.LeaveWithChannelSyncChannel;
begin
  FCurBufSz := 0;
  LeaveWithChannelInternal
end;

procedure TFanOutTests.LogIntegers(const Ch: TChannel<Integer>.TReadOnly;
  const ID, LimitCount: Integer);
var
  I, Counter: Integer;
begin
  Counter := 0;
  for I in Ch do begin
    if Counter >= LimitCount then
      Exit;
    Inc(Counter);
    FLog.Add(Format('log[%d][%d]', [ID, I]))
  end;
end;

procedure TFanOutTests.SetUp;
begin
  inherited;
  FLog := TStringList.Create;
end;

procedure TFanOutTests.SimpleConsumer(const Ch: TChannel<Integer>.TReadOnly);
var
  Value: Integer;
begin
  while Ch.Read(Value) do begin
    FLog.Add('')
  end;
end;

procedure TFanOutTests.TearDown;
begin
  inherited;
  FLog.Free;
end;

procedure TFanOutTests.UpDownConsumersAsync;
var
  Consumer1, Consumer2, Producer: IRawGreenlet;
  FanOut: TFanOut<Integer>;
  Ch: TChannel<Integer>;
begin
  FCurBufSz := 3;
  Ch := TChannel<Integer>.Make(FCurBufSz);
  FanOut := TFanOut<Integer>.Make(Ch.ReadOnly);
  Producer := TSymmetric<TChannel<Integer>.TWriteOnly, Integer>
    .Spawn(WriteIntegersAndLog, Ch.WriteOnly, 1000000);
  Consumer1 := TSymmetric<TChannel<Integer>.TReadOnly>
    .Spawn(SimpleConsumer, FanOut.Inflate);

  Check(FLog.Count = FCurBufSz+1);
  FLog.Clear;
  DefHub.Serve(0);
  Check(FLog.Count > 0);
  FLog.Clear;
  Consumer1.Kill;
  Join([Producer], 100);
  Check(FLog.Count > 0);
  FLog.Clear;
  Consumer2 := TSymmetric<TChannel<Integer>.TReadOnly>
    .Spawn(SimpleConsumer, FanOut.Inflate);
  DefHub.Serve(0);
  Check(FLog.Count > 0);
  FLog.Clear;
end;

procedure TFanOutTests.WriteIntegers(const Ch: TChannel<Integer>.TWriteOnly;
  const Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Count do
    Ch.Write(I);
  Ch.Close;
end;

procedure TFanOutTests.WriteIntegersAndLog(
  const Ch: TChannel<Integer>.TWriteOnly; const Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Count do begin
    FLog.Add(IntToStr(I));
    Ch.Write(I);
  end;
  Ch.Close;
end;

{ TCaseSetTests }

procedure TCaseSetTests.AddCase;
var
  CaseSet: TCaseSet;
  Case1: TCase<Integer>;
  Case2: TCase<string>;
  Case3: TCase<Integer>;
begin
  CheckFalse(CaseSet.Has(Case1));
  CaseSet := CaseSet + Case1;
  CaseSet := CaseSet + Case3;
  CheckTrue(CaseSet.Has(Case1));
  CheckFalse(CaseSet.Has(Case2));
  CheckTrue(CaseSet.Has(Case3));
end;

procedure TCaseSetTests.AddCaseSet;
var
  CaseSet1, CaseSet2, CaseSet: TCaseSet;
  Case1: TCase<Integer>;
  Case2: TCase<string>;
  Case3: TCase<Integer>;
begin
  CaseSet1 := TCaseSet.Make([Case1, Case2]);
  CaseSet2 := TCaseSet.Make([Case3]);
  CheckFalse(CaseSet1.Has(Case3));

  CaseSet := CaseSet1 + CaseSet2;
  CheckTrue(CaseSet.Has(Case1));
  CheckTrue(CaseSet.Has(Case2));
  CheckTrue(CaseSet.Has(Case3));
end;

procedure TCaseSetTests.ConstructorTest;
var
  CaseSet: TCaseSet;
  Case1: TCase<Integer>;
  Case2: TCase<string>;
  Case3: TCase<Integer>;
begin
  CaseSet := TCaseSet.Make([Case1, Case2]);
  CheckTrue(CaseSet.Has(Case1));
  CheckTrue(CaseSet.Has(Case2));
  CheckFalse(CaseSet.Has(Case3));

  CaseSet := TCaseSet.Make([Case1]);
  CheckTrue(CaseSet.Has(Case1));
  CheckFalse(CaseSet.Has(Case2));

  CaseSet := TCaseSet.Make([]);
  CheckFalse(CaseSet.Has(Case1));
  CheckFalse(CaseSet.Has(Case2));
end;

procedure TCaseSetTests.Duplicates;
var
  CaseSet: TCaseSet;
  Case1: TCase<Integer>;
begin
  CaseSet := TCaseSet.Make([Case1]);
  CaseSet := CaseSet + Case1;
  CheckFalse(CaseSet.IsEmpty);
  CaseSet := CaseSet - CaseSet;
  CheckTrue(CaseSet.IsEmpty);
end;

procedure TCaseSetTests.InOperator;
var
  CaseSet: TCaseSet;
  Case1, Case2: TCase<Integer>;
begin
  CaseSet := TCaseSet.Make([Case1]);
  CheckTrue(Case1 in CaseSet);
  CheckFalse(Case2 in CaseSet);
end;

procedure TCaseSetTests.IsEmpty;
var
  CaseSet: TCaseSet;
  Case1: TCase<Integer>;
begin
  CheckTrue(CaseSet.IsEmpty);
  CaseSet := TCaseSet.Make([Case1]);
  CheckFalse(CaseSet.IsEmpty);
end;

procedure TCaseSetTests.SubCase;
var
  CaseSet: TCaseSet;
  Case1: TCase<Integer>;
  Case2: TCase<string>;
  Case3: TCase<Integer>;
begin
  CaseSet := CaseSet + Case1 + Case2 + Case3;
  CheckTrue(CaseSet.Has(Case1));
  CaseSet := CaseSet - Case1;
  CheckFalse(CaseSet.Has(Case1));
  CheckTrue(CaseSet.Has(Case2));
  CheckTrue(CaseSet.Has(Case3));
end;

procedure TCaseSetTests.SubCaseSet;
var
  CaseSet1, CaseSet2: TCaseSet;
  Case1: TCase<Integer>;
  Case2: TCase<string>;
  Case3: TCase<Integer>;
begin
  CaseSet1 := TCaseSet.Make([Case1, Case2]);
  CaseSet2 := TCaseSet.Make([Case3]);

  CaseSet1 := CaseSet1 - CaseSet2;
  CheckTrue(CaseSet1.Has(Case1));
  CheckTrue(CaseSet1.Has(Case2));

  CaseSet2 := TCaseSet.Make([Case2]);
  CaseSet1 := CaseSet1 - CaseSet2;
  CheckTrue(CaseSet1.Has(Case1));
  CheckFalse(CaseSet1.Has(Case2));
end;

initialization
  RegisterTest('CaseSetTests', TCaseSetTests.Suite);
  RegisterTest('GCPointerTests', TGCPointerTests.Suite);
  RegisterTest('ContractTests', TContractTests.Suite);
  RegisterTest('SyncChannelTests', TSyncChannelTests.Suite);
  RegisterTest('SyncNonThreadChannelTests', TSyncNonThreadChannelTests.Suite);
  RegisterTest('AsyncChannelTests', TAsyncChannelTests.Suite);
  RegisterTest('FanOutTests', TFanOutTests.Suite);
end.
