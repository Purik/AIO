unit GSyncObjTests;

interface
uses
  {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections,  System.Rtti{$ENDIF},
  Classes,
  SyncObjs,
  Gevent,
  Greenlets,
  SysUtils,
  GInterfaces,
  Hub,
  GreenletsImpl,
  AsyncThread,
  GreenletTests,
  TestFramework;

const
  cTestSeqCount = 10;
  cTestSeq: array[0..cTestSeqCount-1] of Integer = (1,2,3,1,8,123,4,2,9,0);

type

  TCondVarRoundRobinThread = class(TThread)
  strict private
    FCond: TGCondVariable;
    FLock: TCriticalSection;
    FValue: PInteger;
    FPredValue: Integer;
    FError: Boolean;
    FLastWriter: PPointer;
    FCounter: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Cond: TGCondVariable;
      Lock: TCriticalSection; Value: PInteger; LastWriter: PPointer);
    destructor Destroy; override;
    property Error: Boolean read FError;
    property Counter: Integer read FCounter;
  end;

  TMultipleGreenletsThread = class(TThread)
  strict private
    FOnStart: TEvent;
    FWorkersCount: Integer;
    FRoutine: TSymmetricRoutine;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine; WorkersCount: Integer);
    destructor Destroy; override;
    procedure Start;
  end;

  TGSyncObjsTests = class(TTestCase)
  strict private
    FCondVar: TGCondVariable;
    FSemaphore: TGSemaphore;
    FQueue: TGQueue<Integer>;
    FObjQueue: TGQueue<TSmartPointer<TTestObj>>;
    FOutput: TStrings;
    FArray: array of NativeUInt;
    FGeventCountOnStart: Integer;
    procedure CondVarTest;
    procedure CondVarProc(const Args: array of const);
    procedure CondVarBroadcast;
    procedure QueueTest;
    procedure QueueGCTest;
    procedure SemaphoreTest1;
    procedure SemaphoreTest2;
    procedure SemaphoreProc(const Args: array of const);
    procedure GeneratorBody1(const A: array of const);
    procedure GeneratorBody2(const A: array of const);
    procedure Generator2Routine(const Args: array of const);
    procedure PrintThroughSem(const Msg: string);
    procedure EnumTestObjs(const Args: array of const);
    procedure EnumGCTestObjs(const Args: array of const);
    procedure OnTestFree(Sender: TObject);
    procedure CondVarSync1;
    procedure CondVarSync2;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CondVariable;
    procedure CondVariableWhileKill;
    procedure CondVariableSyncMech;
    procedure Semaphore1;
    procedure Semaphore2;
    procedure Semaphore3;
    procedure Semaphore4;
    procedure Semaphore5;
    procedure Queue;
    procedure QueueGC;
    procedure Generator1;
    procedure Generator2;
    procedure GeneratorMultiple;
    procedure GeneratorObjects;
    procedure GeneratorGCObjects;
    // threaded
    procedure CondVariableRoundRobin;
  end;

  TRefObject = class
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  GlobalRefCount: Integer;

implementation
uses GarbageCollector;


{ TGSyncObjsTests }

procedure TGSyncObjsTests.CondVarBroadcast;
begin
  GreenSleep(100);
  FCondVar.Broadcast;
  GreenSleep(100);
  FCondVar.Broadcast
end;

procedure TGSyncObjsTests.CondVariable;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(CondVarTest);
  G.Join;
end;

procedure TGSyncObjsTests.CondVariableRoundRobin;
var
  T1, T2: TCondVarRoundRobinThread;
  Value: Integer;
  LastWriter: Pointer;
  Cond: TGCondVariable;
  Lock: TCriticalSection;
  Stop, Start: TTime;
  Error: Boolean;
begin
  Lock := TCriticalSection.Create;
  Cond := TGCondVariable.Make(Lock);

  Error := False;

  Value := 0;
  LastWriter := nil;

  T1 := TCondVarRoundRobinThread.Create(Cond, Lock, @Value, @LastWriter);
  T2 := TCondVarRoundRobinThread.Create(Cond, Lock, @Value, @LastWriter);

  try
    Sleep(1000);
    Cond.Signal;
    Start := Now;
    Stop := Now + TimeOut2Time(1000);
    while Now < Stop do begin
      Error := T1.Error or T2.Error;
      if Error then begin
        Lock.Acquire;
        Value := 100000000;
        Lock.Release;
      end;
    end;
  finally
    Lock.Acquire;
    Value := 1000000000;
    Lock.Release;
    T1.Terminate;
    T2.Terminate;
    Cond.Broadcast;
    T1.WaitFor;
    {$IFDEF DEBUG}
    DebugString('T1');
    {$ENDIF}
    Cond.Broadcast;
    T2.WaitFor;
    {$IFDEF DEBUG}
    DebugString('T2');
    {$ENDIF}
    T1.Free;
    T2.Free;
    Lock.Free;
  end;
  CheckFalse(Error);
  {$IFDEF DEBUG}
  DebugString(Format('Timeout = %d, counters = %d',
    [
      Time2Timeout(Stop - Start),
      T1.Counter+T2.Counter
    ]));
  {$ENDIF}
end;

procedure TGSyncObjsTests.CondVariableSyncMech;
var
  G1, G2: TSymmetric;
begin
  G1 := TSymmetric.Create(CondVarSync1);
  G2 := TSymmetric.Create(CondVarSync2);

  Join([G2, G1]);
  Check(FOutput.CommaText = 'g2,g1,g2,g1');
end;

procedure TGSyncObjsTests.CondVariableWhileKill;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(CondVarProc, [1]);
  try
    FCondVar := TGCondVariable.Make;
  finally
    FCondVar := TGCondVariable.Make;
  end;
end;

procedure TGSyncObjsTests.CondVarProc(const Args: array of const);
var
  Index: Integer;
begin
  Index := Args[0].AsInteger;
  FOutput.Add(IntToStr(Index));
  FCondVar.Wait;
  FOutput.Add(IntToStr(Index));
  FCondVar.Wait;
  FOutput.Add(IntToStr(Index));
end;

procedure TGSyncObjsTests.CondVarSync1;
begin
  FOutput.Add('g1');
  FCondVar.Signal;
  FOutput.Add('g1');
end;

procedure TGSyncObjsTests.CondVarSync2;
begin
  FOutput.Add('g2');
  FCondVar.Wait;
  FOutput.Add('g2');
end;


procedure TGSyncObjsTests.CondVarTest;
var
  Gr: TGreenGroup<Integer>;
begin
  Gr[0] := TGreenlet.Spawn(CondVarProc, [0]);
  Gr[1] := TGreenlet.Spawn(CondVarProc, [1]);
  Gr[2] := TGreenlet.Spawn(CondVarBroadcast);
  Gr.Join;
  Check(FOutput.CommaText = '0,1,0,1,0,1');
end;

procedure TGSyncObjsTests.EnumGCTestObjs(const Args: array of const);
var
  Obj: TObject;
  I: Integer;
begin
  for I := 0 to High(Args) do begin
    Obj := Args[I].AsObject;
    TGenerator<TObject>.Yield(Obj);
  end;
end;

procedure TGSyncObjsTests.EnumTestObjs(const Args: array of const);
var
  Count, I: Integer;
  A: TTestObj;
begin
  Count := Args[0].AsInteger;
  for I := 1 to Count do begin
    A := TTestObj.Create;
    A.OnDestroy := Self.OnTestFree;
    TGenerator<TTestObj>.Yield(A);
  end;
end;

procedure TGSyncObjsTests.Generator1;
var
  Gen: TGenerator<Integer>;
  I: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create;
  Gen := TGenerator<Integer>.Create(GeneratorBody1, [4, 11, 3]);
  try
    for I in Gen do begin
      List.Add(I);
    end;
    Check(List.Count = 3);
    Check(List[0] = 4);
    Check(List[1] = 7);
    Check(List[2] = 10);
  finally
    List.Free;
  end;
end;

procedure TGSyncObjsTests.Generator2;
var
  Gen: TGenerator<Integer>;
  I: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create;
  Gen := TGenerator<Integer>.Create(GeneratorBody2, [1, 2, -300, 3, 4, -100, 5]);
  try
    for I in Gen do begin
      List.Add(I);
    end;
    Check(List.Count = 5);
    Check(List[0] = 1);
    Check(List[1] = 2);
    Check(List[2] = 3);
    Check(List[3] = 4);
    Check(List[4] = 5);
  finally
    List.Free;
  end;
end;

procedure TGSyncObjsTests.Generator2Routine(const Args: array of const);
var
  Gen: TGenerator<Integer>;
  List: TList<Integer>;
  Iter: Integer;
begin
  List := TList<Integer>(Args[0].AsObject);
  Gen := TGenerator<Integer>.Create(GeneratorBody2, Slice(Args, 1));
  for Iter in Gen do
    List.Add(Iter);
end;

procedure TGSyncObjsTests.GeneratorBody1(const A: array of const);
var
  Cur, Stop, Step: Integer;
begin
  Cur := A[0].AsInteger;
  Stop := A[1].AsInteger;
  if Length(A) > 2 then
    Step := A[2].AsInteger
  else
    Step := 1;
  while Cur <= Stop do begin
    TGenerator<Integer>.Yield(Cur);
    Inc(Cur, Step);
  end;
end;

procedure TGSyncObjsTests.GeneratorBody2(const A: array of const);
var
  I, Value: Integer;
begin
  for I := 0 to High(A) do begin
    Value := A[I].AsInteger;
    if Value >= 0 then
      TGenerator<Integer>.Yield(Value)
    else
      GreenSleep(-Value);
  end;
end;

procedure TGSyncObjsTests.GeneratorGCObjects;
var
  A1, A2, A3: TTestObj;

  procedure RunInternal;
  var
    Gen: TGenerator<TObject>;
    I: TObject;
  begin
    GC(A1);
    GC(A2);
    GC(A3);
    Gen := TGenerator<TObject>.Create(EnumGCTestObjs, [A1, A2, A3]);
    {$IFDEF DEBUG}
    Check(GCCounter > 0);
    {$ENDIF}
    for I in Gen do begin
      TTestObj(I).OnDestroy := Self.OnTestFree;
    end;
    {$IFDEF DEBUG}
    Check(GCCounter > 0);
    {$ENDIF}
  end;
begin
  {$IFDEF DEBUG}
  GCCounter := 0;
  {$ENDIF}
  A1 := TTestObj.Create;
  A2 := TTestObj.Create;
  A3 := TTestObj.Create;
  RunInternal;
  Check(FOutput.Count = 3);
  Check(FOutput.CommaText = 'OnDestroy,OnDestroy,OnDestroy');
  {$IFDEF DEBUG}
  CheckEquals(GCCounter, 0);
  {$ENDIF}

  CheckFalse(TGarbageCollector.ExistsInGlobal(A2));
  CheckFalse(TGarbageCollector.ExistsInGlobal(A1));

  CheckFalse(TGarbageCollector.ExistsInGlobal(A3));
end;

procedure TGSyncObjsTests.GeneratorMultiple;
var
  G1, G2, G3: TGreenlet;
  L1, L2, L3: TList<Integer>;

  function MakeCommaText(const L: TList<Integer>): string;
  var
    Strs: TStrings;
    I: Integer;
  begin
    Strs := TStringList.Create;
    try
      for I := 0 to L.Count-1 do
        Strs.Add(IntToStr(L[I]));
      Result := Strs.CommaText;
    finally
      Strs.Free
    end;
  end;

begin
  L1 := TList<Integer>.Create;
  L2 := TList<Integer>.Create;
  L3 := TList<Integer>.Create;

  G1 := TGreenlet.Spawn(Generator2Routine, [L1, 1,2,-100,4,5]);
  G2 := TGreenlet.Spawn(Generator2Routine, [L2, 10,11,-200,-100,12]);
  G3 := TGreenlet.Spawn(Generator2Routine, [L3, -100,40,50]);
  try
    Check(Greenlets.Join([G1, G2, G3], 1000));
    Check(MakeCommaText(L1) = '1,2,4,5');
    Check(MakeCommaText(L2) = '10,11,12');
    Check(MakeCommaText(L3) = '40,50');
  finally
    L1.Free;
    L2.Free;
    L3.Free;
  end;
end;

procedure TGSyncObjsTests.GeneratorObjects;
var
  Count: Integer;

  procedure RunInternal;
  var
    Gen: TGenerator<TTestObj>;
    I: TTestObj;
  begin
    Gen := TGenerator<TTestObj>.Create(EnumTestObjs, [Count]);
    for I in Gen do begin
      Check(Assigned(I));
    end;
  end;

begin
  Count := 5;
  RunInternal;
  Check(FOutput.Count = Count);
  Check(FOutput.CommaText = 'OnDestroy,OnDestroy,OnDestroy,OnDestroy,OnDestroy');
end;

procedure TGSyncObjsTests.OnTestFree(Sender: TObject);
begin
  FOutput.Add('OnDestroy')
end;

procedure TGSyncObjsTests.PrintThroughSem(const Msg: string);
begin
  FSemaphore.Acquire;
  try
    GreenSleep(0);
    FOutput.Add(Msg);
  finally
    FSemaphore.Release
  end;
end;

procedure TGSyncObjsTests.Queue;
var
  I: Integer;
  G: IRawGreenlet;
begin
  for I := 0 to cTestSeqCount-1 do
    FQueue.Enqueue(cTestSeq[I]);
  CheckEquals(FQueue.Count, cTestSeqCount, 'Queue.Count problems');
  G := TGreenlet.Spawn(QueueTest);
  G.Join;

  for I := 0 to cTestSeqCount-1 do
    FQueue.Enqueue(cTestSeq[I]);
  FQueue.Clear;
  Check(FQueue.Count = 0, 'FQueue.Clear problems');
end;

procedure TGSyncObjsTests.QueueGC;
var
  I: Integer;
  Obj: TTestObj;
  G: IRawGreenlet;
begin
  for I := 0 to cTestSeqCount-1 do begin
    Obj := TTestObj.Create;
    Obj.OnDestroy := Self.OnTestFree;
    Obj.Name := IntToStr(cTestSeq[I]);
    FObjQueue.Enqueue(Obj);
  end;
  CheckEquals(FObjQueue.Count, cTestSeqCount, 'Queue.Count problems');
  G := TGreenlet.Spawn(QueueGCTest);
  G.Join;

  Check(FOutput.IndexOf('OnDestroy') <> -1);

  FOutput.Clear;
  for I := 0 to cTestSeqCount-1 do begin
    Obj := TTestObj.Create;
    Obj.OnDestroy := Self.OnTestFree;
    FObjQueue.Enqueue(Obj);
  end;
  FObjQueue.Clear;
  Check(FObjQueue.Count = 0, 'FQueue.Clear problems');
  Check(FOutput.CommaText <> '');
  Check(FOutput.IndexOf('OnDestroy') <> -1);
end;

procedure TGSyncObjsTests.QueueGCTest;
var
  I, J: Integer;
  Val: TSmartPointer<TTestObj>;
begin
  I := 0;
  for J := cTestSeqCount downto 1 do begin
    CheckEquals(FObjQueue.Count, J);
    FObjQueue.Dequeue(Val);
    CheckEquals(Val.Get.Name, IntToStr(cTestSeq[I]));
    Inc(I)
  end;
end;

procedure TGSyncObjsTests.QueueTest;
var
  I, J, Val: Integer;
begin
  I := 0;
  for J := cTestSeqCount downto 1 do begin
    CheckEquals(FQueue.Count, J);
    FQueue.Dequeue(Val);
    CheckEquals(Val, cTestSeq[I]);
    Inc(I)
  end;
end;

procedure TGSyncObjsTests.Semaphore1;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(SemaphoreTest1);
  G.Join
end;

procedure TGSyncObjsTests.Semaphore2;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(SemaphoreTest2);
  G.Join
end;

procedure TGSyncObjsTests.Semaphore3;
var
  G: IRawGreenlet;
begin
  FSemaphore := TGSemaphore.Make(5);
  G := TGreenlet.Spawn(SemaphoreTest1);
  G.Join
end;

procedure TGSyncObjsTests.Semaphore4;
var
  G: IRawGreenlet;
begin
  FSemaphore := TGSemaphore.Make(1);
  G := TGreenlet.Spawn(SemaphoreTest1);
  G.Join
end;

procedure TGSyncObjsTests.Semaphore5;
begin
  TSymmetric<string>.Spawn(PrintThroughSem, '1');
  TSymmetric<string>.Spawn(PrintThroughSem, '2');
  TSymmetric<string>.Spawn(PrintThroughSem, '3');
  TSymmetric<string>.Spawn(PrintThroughSem, '4');
  TSymmetric<string>.Spawn(PrintThroughSem, '5');

  JoinAll;
  Check(FOutput.CommaText = '1,2,3,4,5');
end;

procedure TGSyncObjsTests.SemaphoreProc(const Args: array of const);
var
  Index, I, Timeout : Integer;
begin
  Index := Args[0].AsInteger;
  Timeout := Args[1].AsInteger;
  for I := 1 to 1 do begin
    FSemaphore.Acquire;
    try
      FQueue.Enqueue(Index);
      if Timeout > 0 then
        Greenlets.GreenSleep(Timeout);
    finally
      FSemaphore.Release;
    end;
  end;
end;

procedure TGSyncObjsTests.SemaphoreTest1;
var
  Gr: TGreenGroup<Integer>;
  I, Val: Integer;
begin
  Gr[0] := TGreenlet.Spawn(SemaphoreProc, [0, 100]);
  Gr[1] := TGreenlet.Spawn(SemaphoreProc, [1, 100]);
  Gr[2] := TGreenlet.Spawn(SemaphoreProc, [2, 100]);
  Gr[3] := TGreenlet.Spawn(SemaphoreProc, [3, 100]);
  for I := 0 to Gr.Count-1 do
    Gr[I].SetName(Format('G%d', [I]));
  Gr.Join;
  I := 0;
  while FQueue.Count > 0 do begin
    FQueue.Dequeue(Val);
    Check(Val = (I mod Gr.Count), 'TestQueue iteration ' + IntToStr(I) + ' error');
    Inc(I);
  end;
end;

procedure TGSyncObjsTests.SemaphoreTest2;
var
  Gr: TGreenGroup<Integer>;
  I, Val: Integer;
begin
  Gr[0] := TGreenlet.Spawn(SemaphoreProc, [0, 0]);
  Gr[1] := TGreenlet.Spawn(SemaphoreProc, [1, 0]);
  Gr[2] := TGreenlet.Spawn(SemaphoreProc, [2, 0]);
  Gr[3] := TGreenlet.Spawn(SemaphoreProc, [3, 0]);
  for I := 0 to Gr.Count-1 do
    Gr[I].SetName(Format('G%d', [I]));
  Gr.Join;
  I := 0;
  while FQueue.Count > 0 do begin
    FQueue.Dequeue(Val);
    Check(Val = (I mod Gr.Count), 'TestQueue iteration ' + IntToStr(I) + ' error');
    Inc(I);
  end;
end;

procedure TGSyncObjsTests.SetUp;
begin
  inherited;
  // в джоинере хаба создается Gevent
  JoinAll;
  {$IFDEF DEBUG}
  GreenletCounter := 0;
  GeventCounter := 0;
  {$ENDIF}
  FOutput := TStringList.Create;
  FCondVar := TGCondVariable.Make;
  FSemaphore := TGSemaphore.Make(3);
  FQueue := TGQueue<Integer>.Make;
  FObjQueue := TGQueue<TSmartPointer<TTestObj>>.Make;
  {$IFDEF DEBUG}
  FGeventCountOnStart := GeventCounter;
  {$ENDIF}
end;

procedure TGSyncObjsTests.TearDown;
begin
  inherited;
  FOutput.Free;
  SetLength(FArray, 0);
  {$IFDEF DEBUG}
  Check(GreenletCounter = 0, 'GreenletCore.RefCount problems');
  // некоторые тесты привоят к вызову DoSomethingLater
  DefHub.Serve(1000);
  Check(GeventCounter = FGeventCountOnStart, 'Gevent.RefCount problems');
  {$ENDIF}
end;

{ TRefObject }

constructor TRefObject.Create;
begin
  Inc(GlobalRefCount)
end;

destructor TRefObject.Destroy;
begin
  Dec(GlobalRefCount);
  inherited;
end;

{ TCondVarRoundRobinThread }

constructor TCondVarRoundRobinThread.Create(Cond: TGCondVariable;
  Lock: TCriticalSection; Value: PInteger; LastWriter: PPointer);
begin
  FCond := Cond;
  FLock := Lock;
  FValue := Value;
  FLastWriter := LastWriter;
  inherited Create(False)
end;

destructor TCondVarRoundRobinThread.Destroy;
begin
  DefHub(Self).Free;
  inherited;
end;

procedure TCondVarRoundRobinThread.Execute;
var
  Inc: Integer;
begin
  FLock.Acquire;
  if FLastWriter^ = nil then begin
    FLastWriter^ := Pointer(Self);
    FValue^ := 1;
  end;

  while not Terminated do begin
    FCond.Wait(FLock);
    FLock.Acquire;
    Inc := FValue^ - FPredValue;
    if Abs(Inc) > 2 then begin
      FError := True;
      FLock.Release;
      Exit;
    end;
    if FLastWriter^ <> Pointer(Self) then begin
      if FValue^ = 1000 then begin
        FValue^ := FValue^ - 1
      end
      else if FValue^ = 0 then begin
        FValue^ := FValue^ + 1
      end
      else begin
        FValue^ := FValue^ + Inc;
      end;
      FLastWriter^ := Pointer(Self);
      FPredValue := FValue^;
      FCounter := FCounter + 1;
    end;
    FCond.Signal
  end;
end;

{ TMultipleGreenletsThread }

constructor TMultipleGreenletsThread.Create(const Routine: TSymmetricRoutine;
  WorkersCount: Integer);
begin
  FRoutine := Routine;
  FWorkersCount := WorkersCount;
  FOnStart := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TMultipleGreenletsThread.Destroy;
begin
  FOnStart.Free;
  inherited;
end;

procedure TMultipleGreenletsThread.Execute;
var
  Workers: array of IRawGreenlet;
  I: Integer;
begin
  SetLength(Workers, FWorkersCount);
  FOnStart.WaitFor;
  for I := 0 to FWorkersCount-1 do
    Workers[I] := TGreenlet.Spawn(FRoutine);
  try
    Join(Workers);
  finally
    for I := 0 to FWorkersCount-1 do
      Workers[I] := nil
  end;
  SetLength(Workers, 0);
end;

procedure TMultipleGreenletsThread.Start;
begin
  FOnStart.SetEvent
end;

initialization
  RegisterTest('GSyncObjs', TGSyncObjsTests.Suite);
  //RegisterTest('ChannelTests', TChannelTests.Suite);
end.
