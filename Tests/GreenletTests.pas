unit GreenletTests;

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
  GarbageCollector,
  GreenletsImpl,
  TestFramework;

type
  TTestObj = class
    OnDestroy: TNotifyEvent;
    Name: string;
  public
    destructor Destroy; override;
  end;

  TIntfTestObj = class(TInterfacedObject)
    OnDestroy: TNotifyEvent;
  public
    destructor Destroy; override;
  end;

  TTestPersistanceObj = class(TPersistent)
  protected
    procedure AssignTo(Dest: TPersistent); override;
  public
    X: string;
    Y: Integer;
    function IsEqual(Other: TPersistent): Boolean;
  end;

  TTestComponentObj = class(TComponent)
  protected
    procedure AssignTo(Dest: TPersistent); override;
  public
    X: string;
    Y: Integer;
    function IsEqual(Other: TComponent): Boolean;
  end;

  TSleepThread = class(TThread)
  strict private
    FSleepValue: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Timeout: Integer);
  end;

  TPulseEventThread = class(TThread)
  strict private
    FEvent: TEvent;
    FTimeout: LongWord;
  protected
    procedure Execute; override;
  public
    constructor Create(Event: TEvent; Timeout: Integer);
  end;

  TPingPongThread = class(TThread)
  strict private
    FMy: TGevent;
    FPartner: TGevent;
    FMyValue: PInteger;
    FOtherValue: PInteger;
    FTimeout: Integer;
    FOnRun: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(MyValue, OtherValue: PInteger; Timeout: Integer);
    destructor Destroy; override;
    procedure Run(My: TGevent; Partner: TGevent);
  end;

  ETestError = class(EAbort);

  TMockGevent = class(TGevent)
  public
    property AssocCounter: Integer read WaitersCount;
  end;

  TGreenletTests = class(TTestCase)
  private
    FOutput: TStringList;
    FGEvent: TGEvent;
    FIgnoreLog: Boolean;
    FCallStack: TList<IRawGreenlet>;
    procedure OnGLSTestFree(Sender: TObject);
    procedure Print(const Msg: string);
    procedure CrossCallRoutine(const Msg: string; const Other: IRawGreenlet);
    procedure YieldResult(const A: array of const);
    procedure InfiniteRoutine;
    procedure SwitchWithArgsRoutine(const A: array of const);
    procedure Switch2YieldRoutine;
    function AccumRoutine1(const Value: Integer): Integer;
    function AccumRoutine2(const Value: Integer): Integer;
    function NStepRunner(const N: Integer; const DoError: Boolean): Boolean;
    procedure PrintHallo;
    function GEventWaitRoutine(const E: TGevent;
      const Timeout: Integer): TWaitResult;
    procedure GeventWait(const E: TGevent; const Timeout: Integer);
    procedure KillingRegRoutine;
    procedure SelfKillRoutine(const Counter: Integer);
    procedure PrintRoutine(const A: array of const);
    procedure SimpleRoutine(const A: array of const);
    procedure GSleepRoutine(const Timeout: Integer);
    procedure NonRootSelectRoutine(const A: array of const);
    procedure NonRootJoinRoutine(const A: array of const);
    function  NonRootJoinTimeoutRoutine(const G1: IRawGreenlet;
      const G2: IRawGreenlet; const G3: IRawGreenlet; const Timeout: Integer): Boolean;
    procedure PrintOrSleepRoutine(const A: array of const);
    procedure GEventRoutine;
    function Loop1Routine(const E1: TGevent;
      const E2: TGevent; const Sync: Boolean): TWaitResult;
    function Loop2Routine(const E1: TGevent;
      const E2: TGevent; const Sync: Boolean): TWaitResult;
    function GLSSetRoutine(const K: string; const Val: TObject): TObject;
    function  GLSGetRoutine(const K: string): TObject;
    procedure SelfSwitchRoutine;
    procedure Regress1Routine;
    procedure SleepSequence(const A: array of const);
    procedure EnvironTest1;
    procedure EnvironSetter;
    procedure EnvironGetter;
    procedure SetterGetterRoutine;
    procedure RaiseEAfterTimeout(const Timeout: Integer; const Msg: string);
    procedure GCRoutine(const A: TObject);
    procedure KillCbLog;
    procedure KillCbRoutine;
    procedure HubCbLog;
    procedure HubCbRoutine(const T: TGreenThread);
    procedure SelfSwitchRunner;
    procedure CallFromCallstack;
    procedure Regress4Routine(const E: TGevent);
    procedure LogHubFlags(const Timeout: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // обычный Switch
    procedure Switch;
    // перекрестный Switch
    procedure CrossCalls1;
    procedure CrossCalls2;
    procedure CrossCalls3;
    procedure CrossCalls4;
    procedure LoopProtect;
    // Создание гринлета в процедурном стиле
    procedure Spawn;
    // С аргументами
    procedure SwitchWithArgs;
    // Передача контекста с аргументами и результатом
    procedure Switch2Yield;
    // Принуд. завершение
    procedure Kill;
    // Непротивореч. смена состояний при манипуляциях
    procedure Reinit;
    procedure States;
    procedure SuspendResume;
    procedure InjectE;
    procedure InjectRoutine1;
    procedure InjectRoutine2;
    procedure InjectRoutine3;
    procedure Events;
    procedure SelfKill;
    procedure KillingContext;
    procedure JoinAll1;
    procedure JoinAll2;
    procedure JoinAllReraiseErrors;
    procedure JoinReraiseErrors;
    // Slice
    procedure Slice;
    // актуализация RefCount аргумента-интерфейса
    procedure ArgsRefCount;
    procedure FinalizeArgs;
    // Зеленый слип
    procedure GreenSleep1;
    procedure GreenSleep2;
    // Правильный перехват исключений
    procedure ExceptionHandling;
    // вызов Select из нитки (root-контекст)
    procedure RootSelect1;
    procedure RootSelect2;
    procedure RootSelectTimeouts;
    procedure SelectSignaled;
    procedure RootSelectRecursion;
    // вызов Join из нитки (root-контекст)
    procedure RootJoin1;
    procedure RootJoin2;
    procedure RootJoin3;
    procedure RootJoin4;
    procedure RootJoin5;
    procedure RootJoinTimeout;
    procedure RootJoinExceptions;
    // вызов Select из гринлета (non-root-контекст)
    procedure NonRootSelect;
    // вызов Join из гринлета (non-root-контекст)
    procedure NonRootJoin1;
    procedure NonRootJoin2;
    procedure NonRootJoin3;
    procedure NonRootJoinExceptions;
    // garbage collector
    procedure GarbageCollector1;
    procedure GarbageCollector2;
    // mega join
    procedure MegaJoinTree;
    // Gevent - простой тест
    procedure GEvent;
    procedure GEvent1;
    procedure GEvent2;
    // Gevent - таймаут ожидания
    procedure GEventTimeouts;
    // Gevent - отработка wrAbandoned при уничтожении
    procedure GEventDestroy;
    // Gevent - отработка при уничтожении ожидающего гринлета
    procedure GEventOnGreenletDestroy;
    // Gevent - отработка при принуд завершении ожидающего гринлета
    procedure GEventOnGreenletKilling;
    // Gevent - проверка порядка передачи контекста при перекрестных
    // Gevent.SetEvent
    procedure GEventCallSequences;
    procedure GEventCallSequencesSynced;
    // Gevent - оборачивание дескрипторов операц. системы
    procedure GeventWrapHandle;
    // проверяем флаги хаба
    procedure GeventHubFlags;
    // Сборщик мусора гринлета
    procedure Context;
    // Как ведет себя гринлет внутри исключения
    procedure DestroyInsideException;
    // Проверка на то что все гринлеты заснув на CONST MS выполнятся параллельно
    procedure AsyncSleep;
    // Проверка на то что все гринлеты обслужат свой event
    procedure AsyncEvents;
    // защита от бесконечного лупа
    procedure SelfSwitch;
    // множественное ожидание Gevent
    procedure WaitHandledGeventMultiple;
    // пинг понг в разных нитях
    procedure GeventPingPongThreaded;
    // чекаем окружение
    procedure EnvironExists;
    procedure EnvironInherit;
    // kill + hib triggers
    procedure KillTriggers;
    procedure HubTriggers;
    // max call per thread count
    procedure MaxCallPerThread;
    procedure MaxGreenletsCount;
    // регресс-баги
    procedure Regress1;
    procedure Regress2;
    procedure Regress3;
    procedure Regress4;
    procedure Regress5;
  end;

  TTestByteArray = array[0..10] of Byte;

  // тест на персистентность аргументов
  TPersistanceTests = class(TTestCase)
  private
    FLog: TStrings;
    procedure StrValueLog(const Value: string);
    procedure BytesLog(const Bytes: TBytes);
    procedure ByteArrayLog(const Bytes: TTestByteArray);
    procedure LogComponent(const A: TTestComponentObj);
    procedure LogObject(const A: TTestObj);
    function LogObjectAndReturnHimself(const A: TTestObj): TTestObj;
    function LogCompAndReturnHimself(const A: TTestComponentObj): TTestComponentObj;
    procedure DoYieldObjects(const A: array of const);
    procedure OnDestroy(Sender: TObject);
    procedure LogName(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Sane;
    procedure GCReplace;
    procedure SmartPoiner1;
    procedure SmartPoiner2;
    procedure SmartPoiner3;
    procedure SmartPoiner4;
    procedure Strings;
    procedure Bytes;
    procedure ByteArray;
    procedure WordArrayArgument;
    procedure PersistentObj;
    procedure Component;
    procedure ArgumentRefs0;
    procedure ArgumentRefs1;
    procedure ArgumentRefs2;
    procedure ArgumentRefs3;
    procedure ArgumentRefs4;
    procedure ArgumentRefs5;
    procedure ArgumentRefs6;
    procedure ArgumentRefs7;
    procedure GArgumentRefs1;
    procedure GArgumentRefs2;
  end;

  TGreenGroupTests = class(TTestCase)
  strict private
    FOutput: TStringList;
    procedure InfiniteRoutine;
    procedure PrintRoutine(const A: array of const);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Add;
    procedure Remove;
    procedure Join;
    procedure GreenletRefCount;
    procedure Copy;
  end;

  TGreenletThread = class(TThread)
  strict private
    FGreenlet: IRawGreenlet;
    FRoutine: TSymmetricRoutine;
  protected
    procedure Execute; override;
  public
    property Greenlet: IRawGreenlet read FGreenlet;
    constructor Create(const Proc: TSymmetricRoutine);
  end;

  TOtherQueueThread = class(TThread)
  strict private
    FCheckFlag: Boolean;
    FCheckTimeOut: LongWord;
    FCheckOkCounter: Integer;
    FHub: THub;
  protected
    procedure Execute; override;
  public
    constructor Create(CheckTimeout: LongWord);
    property CheckFlag: Boolean read FCheckFlag;
    property Hub: THub read FHub;
    property CheckOkCounter: Integer read FCheckOkCounter;
  end;

  TGreenletProxyTests = class(TTestCase)
  private
    FLock: TCriticalSection;
    FOutput: TStringList;
    FHub: THub;
    FAsyncThread: TGreenThread;
    FAsyncThreads: array of TGreenThread;
    procedure InfiniteLoop;
    procedure MoveToAsyncAndLoop;
    procedure SleepInfinite;
    function WaitGevent(const E: TGevent): TWaitResult;
    procedure ThreadedJoin;
    procedure KillAsyncThread;
    procedure ThreadsWalk;
    procedure BeginThreadRoutine;
    procedure BeginThreadAndInfiniteLoop;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Pulse;
    procedure PulseThreaded;
    procedure SuspendResume;
    procedure Moves;
    procedure BeginThread;
    procedure FreeBeginThreadOnTerminate;
    procedure EInjection;
    procedure KillAndDestroy;
    procedure KillAndDestroyThreaded;
    procedure Events;
    procedure Regress1;
  end;

  TGreenletMultiThreadTests = class(TTestCase)
  private
    FGEvent: TGEvent;
    FGEventManual: TGEvent;
    FOutput: TStringList;
    FCounter: Integer;
    FList1: TList;
    FList2: TList;
    function SleepAndRetThreadId(const Timeout: LongWord): LongWord;
    procedure GEventManualWaiter;
    function WaitStatus2Str(Status: TWaitResult): string;
    procedure AddThreadIdToList1;
    procedure AddThreadIdToList2;
    procedure AborterProc;
    procedure AddThreadIdToList1FromThreadToMainHub;
    procedure PulseGeventManualOnKill;
    procedure AddThreadIdToList1Threaded(const Count: Integer; const Delay: Integer);
    function WaitAndResult(const Timeout: Integer; const aResult: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // Gevent - межниточное взаимодействие
    procedure GEventOnThread;
    // поведение очереди хаба в множестве ниток
    procedure ThreadsQueueProc;
    // поведение очереди хаба в множестве ниток с таймаутом
    procedure ThreadsQueueProcTimeout;
    // проверка отработки SyncEvent хаба
    procedure SyncEventLoseState;
    // проверка что гринлет перемещенный в др нитку будет
    // уничтожен в чужой нитке при выходе из обл видимости тек блока
    procedure KillMoved;
    procedure KillMovedAgressive;
    // asymmetrics
    procedure Asymmetrcs;
    // проверка что Join правильно отрабатывает если гринлет перемещен в
    // др. нитку
    procedure JoinMoved;
    procedure JoinMovedStress;
    // regress
    procedure Regress1;
  end;

implementation
uses AsyncThread;

type
  TRawGreenletPImpl = class(TRawGreenletImpl);


{ TGreenletTests }

procedure TGreenletTests.SelectSignaled;
var
  E: TGevent;
  Index: Integer;
begin
  E := TGevent.Create(False, True);
  try
    Check(Select([E], Index, 0) = wrSignaled);
    Check(Index = 0);
    Check(E.WaitFor(0) = wrTimeout)
  finally
    E.Free
  end;

  E := TGevent.Create(True, False);
  try
    Check(Select([E], Index, 0) = wrTimeout);
    Check(Index = -1);
    E.SetEvent;
    Check(Select([E], Index, 0) = wrSignaled);
    Check(Select([E], Index, 0) = wrSignaled);
  finally
    E.Free
  end
end;

procedure TGreenletTests.SelfKill;
var
  G: IRawGreenlet;
begin
  G := TSymmetric<Integer>.Spawn(SelfKillRoutine, 5);
  Join([G], 100);
  Check(G.GetState = gsKilled);
end;

procedure TGreenletTests.SelfKillRoutine(const Counter: Integer);
var
  StepCnt: Integer;
begin
  StepCnt := Counter;
  while StepCnt > 0 do begin
    Dec(StepCnt);
    Greenlets.Yield;
  end;
  TRawGreenletImpl(GetCurrent).Kill;
  StepCnt := Counter;
  while StepCnt > 0 do begin
    Dec(StepCnt);
    Greenlets.Yield;
  end;
end;

procedure TGreenletTests.SelfSwitchRunner;
var
  G: IRawGreenlet;
begin
  G := TSymmetric.Create(SelfSwitchRoutine);
  Join([G], INFINITE, True);
end;

procedure TGreenletTests.SelfSwitch;
begin
  CheckException(SelfSwitchRunner, GreenletsImpl.TRawGreenletImpl.ESelfSwitch);
end;

procedure TGreenletTests.SelfSwitchRoutine;
begin
  while True do begin
    TRawGreenletImpl(GetCurrent).Switch;
    Greenlets.Yield;
    FOutput.Add('selfswitch');
  end;
end;

procedure TGreenletTests.SetterGetterRoutine;
begin
  EnvironSetter;
  TGreenlet.Spawn(EnvironGetter);
end;

procedure TGreenletTests.SetUp;
begin
  inherited;
  JoinAll(0);
  FOutput := TStringList.Create;
  {$IFDEF DEBUG}
  GreenletCounter := 0;
  GeventCounter := 0;
  {$ENDIF}
  FGEvent := TGEvent.Create;
  FCallStack := TList<IRawGreenlet>.Create;
end;

procedure TGreenletTests.SimpleRoutine(const A: array of const);
begin
  FOutput.Add(A[0].AsString)
end;

procedure TGreenletTests.SleepSequence(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Greenlets.GreenSleep(A[I].AsInteger);
end;

procedure TGreenletTests.Slice;
var
  Tup: tTuple;

  function IsEqual(const Tup1: tTuple; const Tup2: array of const): Boolean;
  var
    I: Integer;
  begin
    Result := Length(Tup1) = Length(Tup2);
    if Result then begin
      for I := 0 to High(Tup1) do begin
        if Tup1[I].VType <> Tup2[I].VType then
          Exit(False);
        if Tup1[I].VInt64 <> Tup2[I].VInt64 then
          Exit(False);
      end;
    end;
  end;

begin
  Tup := Greenlets.Slice([1,2,3,4,5], 2);
  Check(IsEqual(Tup, [3,4,5]));

  Tup := Greenlets.Slice([1,2,3,4,5], 0);
  Check(IsEqual(Tup, [1,2,3,4,5]));

  Tup := Greenlets.Slice([1,2,3,4,5], 0);
  Check(IsEqual(Tup, [1,2,3,4,5]));

  Tup := Greenlets.Slice([1,2,3,4,5], 40);
  Check(IsEqual(Tup, []));

  Tup := Greenlets.Slice([1,2,3,4,5], 2, 3);
  Check(IsEqual(Tup, [3,4]));

  Tup := Greenlets.Slice([1,2,3,4,5], 3, 30);
  Check(IsEqual(Tup, [4,5]));
end;

procedure TGreenletTests.Spawn;
begin
  TSymmetric<string>.Spawn(Print, 'spawn');
  Check(FOutput[0] = 'spawn');

end;

procedure TGreenletTests.States;
var
  G: IRawGreenlet;
  A: TAsymmetric<Integer, Boolean, Boolean>;
  I: Integer;
begin
  A := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 3, False);
  G := A;
  Check(G.GetState = gsReady);
  G.Switch;
  Check(G.GetState = gsExecute);
  for I := 0 to 10 do
    G.Switch;
  Check(G.GetState = gsTerminated);
  A := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 3000, False);
  G := A;
  G.Switch;
  G.Switch;
  G.Kill;
  Check(G.GetState = gsKilled);
  A := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 3, True);
  G := A;
  for I := 0 to 10 do
    G.Switch;
  Check(G.GetState = gsException);
  Check(G.GetException.ClassType = ETestError);
  Check(G.GetException.Message = 'test error');
end;

procedure TGreenletTests.SuspendResume;
var
  G: IGreenlet;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  G.Suspend;
  Check(G.GetState = gsSuspended);
  Check(FOutput.Count = 1);
  G.Switch;
  Check(FOutput.Count = 1);
  G.Resume;
  Check(G.GetState = gsExecute);
  Check(FOutput.Count = 2);
end;

procedure TGreenletTests.Switch;
var
  G: IRawGreenlet;
begin
  G := TSymmetric<string>.Create(Print, 'test');
  Check(FOutput.Count = 0);
  G.Switch;
  Check(FOutput[0] = 'test');
end;

procedure TGreenletTests.Switch2Yield;
var
  G: TGreenlet;
  Tup: tTuple;
begin
  G := TGreenlet.Create(Switch2YieldRoutine);
  G.Switch;
  Tup := G.Switch([1, 2, -3, 1]);
  Check(Length(Tup) = 3);
  Check(Tup[0].AsInteger = 1);
  Check(Tup[1].AsInteger = -6);
  Check(Tup[2].AsInteger = 4);
  Check(FOutput.Count = 4);
  Check(FOutput[0] = '1');
  Check(FOutput[1] = '2');
  Check(FOutput[2] = '-3');
  Check(FOutput[3] = '1');
end;

procedure TGreenletTests.Switch2YieldRoutine;
var
  Tup: tTuple;
  I, Sum, Count, Accum: Integer;
begin
  Tup := TGreenlet.Yield;
  Accum := 1;
  Sum := 0;
  Count := Length(Tup);
  for I := 0 to High(Tup) do begin
    FOutput.Add(Tup[I].AsString);
    Sum := Sum + Tup[I].VInteger;
    Accum := Accum * Tup[I].VInteger;
  end;
  TGreenlet.Yield([Sum, Accum, Count]);
end;

procedure TGreenletTests.SwitchWithArgs;
var
  G: TGreenlet;
begin
  G := TGreenlet.Spawn(SwitchWithArgsRoutine, [1, 2, 'hallo', 5.1]);
  Check(FOutput.Count = 4);
  Check(FOutput[0] = '1');
  Check(FOutput[1] = '2');
  Check(FOutput[2] = 'hallo');
  Check(FOutput[3] = Format('%.1f', [5.1]));
end;

procedure TGreenletTests.SwitchWithArgsRoutine(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    FOutput.Add(A[I].AsString)
end;

function TGreenletTests.AccumRoutine1(const Value: Integer): Integer;
begin
  Result := Value + 1
end;

function TGreenletTests.AccumRoutine2(const Value: Integer): Integer;
begin
  Result := Value + 2
end;

procedure TGreenletTests.ArgsRefCount;
var
  A: TIntfTestObj;
  I: IInterface;
  G: TGreenlet;
begin
  A := TIntfTestObj.Create;
  I := A;
  G := TGreenlet.Spawn(SimpleRoutine, ['s1', 's2', I]);
  Check(A.RefCount = 1);
  I := nil;
  Check(A.RefCount = 0);
end;

procedure TGreenletTests.AsyncEvents;
var
  Ge1, Ge2, Ge3, Ge4, Ge5: TGevent;
  E1, E2, E3, E4, E5: TEvent;
  G1, G2, G3, G4, G5: TSymmetric<TGevent, Integer>;
  Stamp: TTime;
  T1, T2, T3, T4, T5: TPulseEventThread;
begin
  E1 := TEvent.Create(nil, False, False, '');
  E2 := TEvent.Create(nil, False, False, '');
  E3 := TEvent.Create(nil, False, False, '');
  E4 := TEvent.Create(nil, False, False, '');
  E5 := TEvent.Create(nil, False, False, '');

  Ge1 := TGevent.Create(E1.Handle);
  Ge2 := TGevent.Create(E2.Handle);
  Ge3 := TGevent.Create(E3.Handle);
  Ge4 := TGevent.Create(E4.Handle);
  Ge5 := TGevent.Create(E5.Handle);

  T1 := TPulseEventThread.Create(E1, 1000);
  T2 := TPulseEventThread.Create(E2, 1000);
  T3 := TPulseEventThread.Create(E3, 1000);
  T4 := TPulseEventThread.Create(E4, 1000);
  T5 := TPulseEventThread.Create(E5, 1000);

  G1 := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge1, 2000);
  G2 := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge2, 2000);
  G3 := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge3, 2000);
  G4 := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge4, 2000);
  G5 := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge5, 2000);

  try
    Stamp := Now;
    Join([G1, G2, G3, G4, G5], 3000);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 900), 'problem 1.1, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
    Check(Stamp <= EncodeTime(0, 0, 1, 100), 'problem 1.2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
  finally
    E1.Free;
    E2.Free;
    E3.Free;
    E4.Free;
    E5.Free;
    Ge1.Free;
    Ge2.Free;
    Ge3.Free;
    Ge4.Free;
    Ge5.Free;
    T1.Free;
    T2.Free;
    T3.Free;
    T4.Free;
    T5.Free;
  end;

end;

procedure TGreenletTests.AsyncSleep;
var
  G1, G2, G3, G4, G5: TSymmetric<Integer>;
  Stamp: TTime;
begin
  G1 := TSymmetric<Integer>.Spawn(GSleepRoutine, 1000);
  G2 := TSymmetric<Integer>.Spawn(GSleepRoutine, 1000);
  G3 := TSymmetric<Integer>.Spawn(GSleepRoutine, 1000);
  G4 := TSymmetric<Integer>.Spawn(GSleepRoutine, 1000);
  G5 := TSymmetric<Integer>.Spawn(GSleepRoutine, 1000);
  Stamp := Now;
  Join([G1, G2, G3, G4, G5]);
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 990), 'problem 1.1');
  Check(Stamp <= EncodeTime(0, 0, 1, 10), 'problem 1.2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.CallFromCallstack;
var
  G: IRawGreenlet;
  Cur: TObject;
begin
  Cur := GetCurrent;
  while FCallStack.Count > 0 do begin
    G := FCallStack[0];
    FCallStack.Delete(0);
    G.Switch;
    Check(Cur = GetCurrent, 'GetCurrent problems');
    if TRawGreenletPImpl.GetCallStackIndex = 1 then
      FOutput.Add('root')
  end;
end;

procedure TGreenletTests.Context;
var
  G: IAsymmetric<TObject>;
  Test: TTestObj;
  IntfTest: TIntfTestObj;

  procedure SubTest1;
  var
    A: IAsymmetric<TObject>;
  begin
    Test := TTestObj.Create;
    Test.OnDestroy := Self.OnGLSTestFree;
    A := TAsymmetric<string, TObject, TObject>.Create(GLSSetRoutine, 'key', Test);
    Check(A.GetResult = Test);
  end;

  procedure SubTest2;
  var
    A: IAsymmetric<TObject>;
  begin
    A := TAsymmetric<string, TObject, TObject>.Create(GLSSetRoutine, 'intf-key', IntfTest);
    A.Switch;
    Check(IntfTest.RefCount = 2);
    Check(A.GetResult = IntfTest);
  end;

  procedure SubTest3;
  var
    A: IAsymmetric<TObject>;
  begin
    A := TAsymmetric<string, TObject, TObject>.Create(GLSSetRoutine, 'intf-key', IntfTest);
    A.Switch;
  end;

begin
  G := TAsymmetric<string, TObject>.Create(GLSGetRoutine, 'non-esists-key');
  Check(G.GetResult = nil);

  SubTest1;
  Check(FOutput[0] = 'OnDestroy');

  IntfTest := TIntfTestObj.Create;
  IntfTest._AddRef;
  try
    SubTest2;
    Check(IntfTest.RefCount = 1);
  finally
    IntfTest._Release;
  end;
  Check(IntfTest.RefCount = 0);

  IntfTest := TIntfTestObj.Create;
  IntfTest._AddRef;
  try
    SubTest3;
    Check(IntfTest.RefCount = 1);
  finally
    IntfTest._Release;
  end;
end;

procedure TGreenletTests.CrossCallRoutine(const Msg: string;
  const Other: IRawGreenlet);
begin
  FOutput.Add(Msg);
  if Other <> nil then
    Other.Switch;
end;

procedure TGreenletTests.CrossCalls1;
var
  G1, G2: IRawGreenlet;
begin
  G2 := TSymmetric<string, IRawGreenlet>.Create(CrossCallRoutine, 'g2', nil);
  G1 := TSymmetric<string, IRawGreenlet>.Create(CrossCallRoutine, 'g1', G2);
  G1.Switch;
  Check(FOutput.Count = 2);
  Check(FOutput[0] = 'g1');
  Check(FOutput[1] = 'g2');
end;

procedure TGreenletTests.CrossCalls2;
var
  G: TGreenlet;
  Test: TTestObj;
  Tup: GInterfaces.tTuple;
  Val1: Integer;
  Val2, Val3: string;
begin
  Test := TTestObj.Create;
  G := TGreenlet.Create(YieldResult, [1, 'hallo', Test]);
  try
    Tup := G.Switch;
    Val1 := Tup[0].AsInteger;
    Val2 := Tup[1].AsString;
    Val3 := Tup[2].AsString;
    Check(Val1 = 2);
    Check(Val2 = 'bye');
    Check(Val3 = Test.ClassName);
  finally
    Test.Free;
  end;
end;

procedure TGreenletTests.CrossCalls3;
var
  G1, G2: IRawGreenlet;
begin
  G1 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g1');
      G2.Switch;
      FOutput.Add('g1');
      G2.Switch;
      FOutput.Add('g1.terminate');
    end
  );

  G2 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g2');
      G1.Switch;
      FOutput.Add('g2');
      G1.Switch;
      FOutput.Add('g2.terminate');
    end
  );

  G1.Switch;
  Check(FOutput.CommaText = 'g1,g2,g1,g2,g1.terminate,g2.terminate');
  G1 := nil;
  G2 := nil;
end;

procedure TGreenletTests.CrossCalls4;
var
  G1, G2, G3, G4: IRawGreenlet;
begin
  G1 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g1');
      G2.Switch;
      FOutput.Add('g1');
      G2.Switch;
      FOutput.Add('g1.terminate');
    end
  );

  G2 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g2');
      G3.Switch;
      FOutput.Add('g2');
      G3.Switch;
      FOutput.Add('g2.terminate');
    end
  );

  G3 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g3');
      G4.Switch;
      FOutput.Add('g3');
      G4.Switch;
      FOutput.Add('g3.terminate');
    end
  );

  G4 := TGreenlet.Create(procedure
    begin
      FOutput.Add('g4');
      G1.Switch;
      FOutput.Add('g4');
      G1.Switch;
      FOutput.Add('g4.terminate');
    end
  );

  G1.Switch;
  Check(FOutput.CommaText = 'g1,g2,g3,g4,g1,g2,g3,g4,g1.terminate,g4.terminate,g3.terminate,g2.terminate');
  G1 := nil;
  G2 := nil;
  G3 := nil;
  G4 := nil;
end;

procedure TGreenletTests.DestroyInsideException;

  procedure SubTest;
  var
    G: IRawGreenlet;
  begin
    G := TGreenlet.Spawn(InfiniteRoutine);
    G.Switch;
    try
      raise ETestError.Create('test');
    except
      G := nil;
    end;
  end;

begin
  SubTest;
  Check(FOutput[FOutput.Count-1] = 'terminated');
end;

procedure TGreenletTests.EnvironExists;
begin
  // root context
  EnvironTest1;
  // greenlet context
  TGreenlet.Spawn(EnvironTest1)
end;

procedure TGreenletTests.EnvironGetter;
begin
  Check(GetEnvironment.GetIntValue('x') = 1);
  Check(GetEnvironment.GetStrValue('y') = 'y');
  Check(GetEnvironment.GetFloatValue('z') = 1.5);
  Check(GetEnvironment.GetDoubleValue('w') = 2.5);
  Check(GetEnvironment.GetInt64Value('a') = 9000000000);
end;

procedure TGreenletTests.EnvironInherit;
begin
  SetterGetterRoutine;
  TGreenlet.Spawn(SetterGetterRoutine)
end;

procedure TGreenletTests.EnvironTest1;
begin
  Check(GetEnvironment <> nil);
  GetEnvironment.Clear;
  GetEnvironment.SetIntValue('int', 123);
  Check(GetEnvironment.GetIntValue('int') = 123);

  GetEnvironment.UnsetValue('int');
  Check(GetEnvironment.GetIntValue('int') = 0);

  Check(GetEnvironment.GetStrValue('str') = '');
  GetEnvironment.SetStrValue('str', 'test');
  Check(GetEnvironment.GetStrValue('str') = 'test');

  Check(GetEnvironment.GetFloatValue('float') = 0);
  GetEnvironment.SetFloatValue('float', 123.5);
  Check(GetEnvironment.GetFloatValue('float') = 123.5);

  Check(GetEnvironment.GetDoubleValue('double') = 0);
  GetEnvironment.SetDoubleValue('double', 123.5);
  Check(GetEnvironment.GetDoubleValue('double') = 123.5);

  Check(GetEnvironment.GetInt64Value('int64') = 0);
  GetEnvironment.SetInt64Value('int64', 5000000000);
  Check(GetEnvironment.GetInt64Value('int64') = 5000000000);

end;

procedure TGreenletTests.EnvironSetter;
begin
  GetEnvironment.SetIntValue('x', 1);
  GetEnvironment.SetStrValue('y', 'y');
  GetEnvironment.SetFloatValue('z', 1.5);
  GetEnvironment.SetDoubleValue('w', 2.5);
  GetEnvironment.SetInt64Value('a', 9000000000);
end;

procedure TGreenletTests.Events;
var
  Waiter: IAsymmetric<TWaitResult>;
  G: IGreenlet;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  Waiter := TAsymmetric<TGevent, Integer, TWaitResult>.Create(
    GEventWaitRoutine, G.GetOnTerminate, Integer(INFINITE)
  );
  Waiter.Switch;
  Check(Waiter.GetState = gsSuspended);
  G.Switch;
  G.Kill;
  Check(Waiter.GetResult = wrSignaled);
end;

procedure TGreenletTests.ExceptionHandling;
var
  G: IAsymmetric<Boolean>;
begin
  G := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 10, True);
  while G.GetState in [gsReady, gsExecute] do
    G.Switch;
  Check(G.GetState = gsException);
  Check(G.GetException.ClassType = ETestError);
  Check(G.GetException.Message = 'test error');
end;

procedure TGreenletTests.FinalizeArgs;
var
  A: TIntfTestObj;
  I: IInterface;
  Str: string;
  AStr: AnsiString;
  B: TIntfTestObj;
  PCh: PChar;
  UStr: UnicodeString;
  Cur: Currency;
  Vrnt: Variant;
  Int: Integer;
  I64: Int64;
  G: IRawGreenlet;
begin

  A := TIntfTestObj.Create;
  I := A;
  B := TIntfTestObj.Create;
  B._AddRef;
  Str := 'Str';
  AStr := 'AStr';
  PCh := 'PChar';
  UStr := 'UStr';
  Cur := 150.67;
  Vrnt := '123';
  Int := 123;
  I64 := 321;

  G := TGreenlet.Spawn(SimpleRoutine, [Str, I, B, AStr, PCh, UStr, Cur, Vrnt, Int, I64]);
  G.Kill;

  Check(B.RefCount = 1);
  B._Release;
  Check(Str = 'Str');
  Check(AStr = 'AStr');
  Check(PCh = 'PChar');
  Check(UStr = 'UStr');
  Check(Cur = 150.67);
  Check(Vrnt = '123');
  Check(Int = 123);
  Check(I64 = 321);
end;

procedure TGreenletTests.GarbageCollector1;
var
  A: TTestObj;
  Ref: IGCObject;
begin
  A := TTestObj.Create;
  A.OnDestroy := Self.OnGLSTestFree;
  Ref := GC(A);
  Check(Ref.GetValue = A);
  Ref := nil;
  GC(nil);
  Check(FOutput.CommaText = 'OnDestroy');
end;

procedure TGreenletTests.GarbageCollector2;
var
  A: TTestObj;

  procedure SubContext;
  var
    G: IRawGreenlet;
  begin
    GC(A);
    G := TSymmetric<TObject>.Spawn(GCRoutine, A);
    Join([G], 100);
    G.Kill;
    GC(nil);
  end;

begin
  A := TTestObj.Create;
  A.OnDestroy := Self.OnGLSTestFree;
  SubContext;
  Check(FOutput.CommaText = 'OnDestroy');
end;

procedure TGreenletTests.GCRoutine(const A: TObject);
begin
  GC(A);
  while True do
    Greenlets.Yield
end;

procedure TGreenletTests.GEvent;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(GEventRoutine);
  Check(G.GetState = gsSuspended);
  FGEvent.SetEvent;
  G.Switch;
  Check(G.GetState = gsSuspended);
  DefHub.Serve(0);
  Check(G.GetState = gsTerminated);
  Check(FOutput[0] = 'signal');
end;

procedure TGreenletTests.GEvent1;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(GEventRoutine);
  Check(G.GetState = gsSuspended);
  FGEvent.SetEvent;
end;

procedure TGreenletTests.GEvent2;
var
  E: TGevent;
begin
  E := TGevent.Create;
  try
    Check(E.WaitFor(100) = wrTimeout);
    E.SetEvent;
    Check(E.WaitFor(0) = wrSignaled);
    Check(E.WaitFor(100) = wrTimeout);
  finally
    E.Free;
  end;

  E := TGevent.Create(False, True);
  try
    Check(E.WaitFor(0) = wrSignaled);
    Check(E.WaitFor(100) = wrTimeout);
  finally
    E.Free;
  end;

  E := TGevent.Create(True);
  try
    Check(E.WaitFor(100) = wrTimeout);
    E.SetEvent;
    Check(E.WaitFor(0) = wrSignaled);
    Check(E.WaitFor(0) = wrSignaled);
  finally
    E.Free;
  end;

  E := TGevent.Create(True, True);
  try
    Check(E.WaitFor(0) = wrSignaled);
    Check(E.WaitFor(0) = wrSignaled);
  finally
    E.Free;
  end
end;

procedure TGreenletTests.GEventCallSequences;
var
  Ev1, Ev2: TGevent;
  G1, G2: IAsymmetric<TWaitResult>;
begin
  Ev1 := TGevent.Create;
  Ev2 := TGevent.Create;
  G1 := TAsymmetric<TGevent, TGevent, Boolean, TWaitResult>.Create(Loop1Routine, Ev1, Ev2, False);
  G2 := TAsymmetric<TGevent, TGevent, Boolean, TWaitResult>.Create(Loop2Routine, Ev1, Ev2, False);
  try
    Join([G1, G2], 1000);
    Check(FOutput.Count = 7);
    Check(FOutput.CommaText = '2,1,1,2,2,2,1');
    Check(G1.GetResult = wrSignaled);
    Check(G2.GetResult = wrSignaled);
  finally
    Ev1.Free;
    Ev2.Free;
  end;

end;

procedure TGreenletTests.GEventCallSequencesSynced;
var
  Ev1, Ev2: TGevent;
  G1, G2: IAsymmetric<TWaitResult>;
begin
  Ev1 := TGevent.Create;
  Ev2 := TGevent.Create;
  G1 := TAsymmetric<TGevent, TGevent, Boolean, TWaitResult>.Create(Loop1Routine, Ev1, Ev2, True);
  G2 := TAsymmetric<TGevent, TGevent, Boolean, TWaitResult>.Create(Loop2Routine, Ev1, Ev2, True);
  try
    Join([G1, G2], 1000);
    Check(FOutput.Count = 7);
    Check(FOutput.CommaText = '2,1,2,1,2,1,2');
    Check(G1.GetResult = wrSignaled);
    Check(G2.GetResult = wrSignaled);
  finally
    Ev1.Free;
    Ev2.Free;
  end;

end;

procedure TGreenletTests.GEventDestroy;
var
  G: IAsymmetric<TWaitResult>;
  Ev: TGevent;
  WR: TWaitResult;
begin
  Ev := TGevent.Create(True);
  G := TAsymmetric<TGevent, Integer, TWaitResult>.Create(GEventWaitRoutine, Ev, 30000);
  G.Switch;
  Check(G.GetState = gsSuspended);
  Ev.Free;
  WR := G.GetResult;
  Check(WR = wrAbandoned);
end;

procedure TGreenletTests.GeventHubFlags;
var
  Ev: TGevent;
  G: TSymmetric<Integer>;
begin
  Ev := TGevent.Create(True);
  G := TSymmetric<Integer>.Spawn(LogHubFlags, 300);
  try
    Check(Ev.WaitFor(500) = wrTimeout);
    Check(FOutput.CommaText = 'suspended:False,suspended:True');
  finally
    Ev.Free
  end
end;

procedure TGreenletTests.GEventOnGreenletDestroy;
var
  G: IAsymmetric<TWaitResult>;
  Ev: TGevent;
begin
  Ev := TGevent.Create(True);
  G := TAsymmetric<TGevent, Integer, TWaitResult>.Create(GEventWaitRoutine, Ev, 300);
  try
    G.Switch;
    Check(G.GetState = gsSuspended);
  finally
    Ev.Free;
  end;
end;

procedure TGreenletTests.GEventOnGreenletKilling;
var
  G: IAsymmetric<TWaitResult>;
  Ev: TGevent;
begin
  Ev := TGevent.Create(True);
  G := TAsymmetric<TGevent, Integer, TWaitResult>.Create(GEventWaitRoutine, Ev, 300);
  try
    G.Switch;
    Check(G.GetState = gsSuspended);
    G.Kill;
  finally
    Ev.Free;
  end;
end;

procedure TGreenletTests.GeventPingPongThreaded;
const
  cCounter = 100000;
var
  T1, T2: TPingPongThread;
  E1, E2: TGevent;
  Counter1, Counter2: Integer;
  {$IFDEF DEBUG}
  Start: TTime;
  {$ENDIF}
begin
  E1 := TGevent.Create;
  E2 := TGevent.Create;
  Counter1 := cCounter;
  Counter2 := cCounter;
  T1 := TPingPongThread.Create(@Counter1, @Counter2, 5000);
  T2 := TPingPongThread.Create(@Counter2, @Counter1, 5000);
  {$IFDEF DEBUG}
  Start := Now;
  {$ENDIF}
  try
    T1.Run(E1, E2);
    T2.Run(E2, E1);
    T1.WaitFor;
    T2.WaitFor;
  finally
    T1.Free;
    T2.Free;
    E1.Free;
    E2.Free;
  end;
  Check(Counter1 = 0, Format('Counter1 = %d', [Counter1]));
  Check(Counter2 = 0, Format('Counter2 = %d', [Counter2]));
  {$IFDEF DEBUG}
  DebugString(Format('Timeout = %d, counter = %d',
    [Time2Timeout(Now-Start), 2*cCounter]));
  {$ENDIF}
end;

procedure TGreenletTests.GEventRoutine;
begin
  case FGEvent.WaitFor of
    wrSignaled:
      FOutput.Add('signal')
    else
      FOutput.Add('no-signal')
  end;
end;

procedure TGreenletTests.GEventTimeouts;
var
  G: TAsymmetric<TGevent, Integer, TWaitResult>;
  Ev: TGevent;
  Stamp: TTime;
begin
  Ev := TGevent.Create(True);
  G := TAsymmetric<TGevent, Integer, TWaitResult>.Create(GEventWaitRoutine, Ev, 300);
  try
    Stamp := Now;
    Join([G]);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 290));
    Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem timeout: ' + IntToStr(Time2TimeOut(Stamp)));
    Check(G.GetResult = wrTimeout);
  finally
    Ev.Free;
  end;
end;

procedure TGreenletTests.GeventWait(const E: TGevent; const Timeout: Integer);
begin
  E.WaitFor(Timeout)
end;

function TGreenletTests.GEventWaitRoutine(const E: TGevent;
  const Timeout: Integer): TWaitResult;
begin
  Result := E.WaitFor(Timeout)
end;

procedure TGreenletTests.GeventWrapHandle;
var
  Ev: TGevent;
  Thread: TSleepThread;
begin
  Thread := TSleepThread.Create(300);
  Ev := TGevent.Create(Thread.Handle);
  try
    Check(Ev.WaitFor(500) = wrSignaled);
    Check(Thread.Terminated);
  finally
    Ev.Free;
    Thread.Free;
  end;
end;

function TGreenletTests.GLSGetRoutine(const K: string): TObject;
begin
  Result := Greenlets.Context(K);
end;

function TGreenletTests.GLSSetRoutine(const K: string;
  const Val: TObject): TObject;
begin
  Greenlets.Context(K, Val);
  Result := Greenlets.Context(K);
  Greenlets.GreenSleep(100);
end;

procedure TGreenletTests.GreenSleep1;
var
  Stamp: TTime;
begin
  Stamp := Now;
  Greenlets.GreenSleep(300);
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 290), 'problem 1');
  Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem 2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.GreenSleep2;
var
  Stamp: TTime;
  G: TSymmetric<Integer>;
begin
  Stamp := Now;
  G := TSymmetric<Integer>.Spawn(GSleepRoutine, 300);
  Check(FGEvent.WaitFor(1000) = wrSignaled, 'problem 1');
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 290), 'problem 2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
  Check(Stamp <= EncodeTime(0, 0, 0, 320), 'problem 3, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.GSleepRoutine(const Timeout: Integer);
begin
  Greenlets.GreenSleep(Timeout);
  FGEvent.SetEvent;
end;

procedure TGreenletTests.HubCbLog;
begin
  if not FIgnoreLog then
    FOutput.Add('hub')
end;

procedure TGreenletTests.HubCbRoutine(const T: TGreenThread);
begin
  RegisterHubHandler(HubCbLog);
  MoveTo(T);
  GreenSleep(INFINITE);
end;

procedure TGreenletTests.HubTriggers;
var
  G: IRawGreenlet;
  T: TGreenThread;
begin
  FIgnoreLog := False;
  T := TGreenThread.Create;
  G := TSymmetric<TGreenThread>.Spawn(HubCbRoutine, T);
  try
    Check(FOutput.CommaText = 'hub');
    Join([G], 100);
    FIgnoreLog := True;
    T.Kill(True);
  finally
    G := nil;
    T.Free
  end;
  GetCurrentHub.Serve(0);
end;

procedure TGreenletTests.InfiniteRoutine;
var
  I: Integer;
begin
  I := 0;
  try
    while True do begin
      FOutput.Add(IntToStr(I));
      Inc(I);
      Greenlets.Yield;
    end;
  finally
    FOutput.Add('terminated')
  end;
end;

procedure TGreenletTests.InjectE;
var
  G: IGreenlet;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  G.Inject(ETestError.Create('test'));
  Check(G.GetState = gsException);
  Check(Assigned(G.GetException));
  Check(G.GetException.Message = 'test');
end;

procedure TGreenletTests.InjectRoutine1;
var
  G: IGreenlet;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  G.Inject(PrintHallo);
  Check(G.GetState = gsExecute);
  G.Switch;
  Check(G.GetState = gsExecute);
  Check(FOutput.CommaText = '0,hallo,1');
end;

procedure TGreenletTests.InjectRoutine2;
var
  G: IGreenlet;
begin
  G := TGreenlet.Create(InfiniteRoutine);
  G.Inject(PrintHallo);
  Check(G.GetState = gsExecute);
  G.Inject(PrintHallo);
  Check(G.GetState = gsExecute);
  Check(FOutput.CommaText = 'hallo,hallo');
end;

procedure TGreenletTests.InjectRoutine3;
var
  G: IGreenlet;
begin
  G := TGreenlet.Create(InfiniteRoutine);
  FOutput.Clear;
  G.Suspend;
  G.Switch; G.Switch; G.Switch;
  Check(FOutput.Count = 0);
  G.Inject(PrintHallo);
  Check(FOutput.Count = 0);
end;

procedure TGreenletTests.JoinAll1;
var
  G1, G2: TGreenlet;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g1.1', 'g1.2', 'g1.3']);
  G2 := TGreenlet.Spawn(PrintRoutine, ['g2.1', 'g2.2']);
  Check(JoinAll(1000));
  Check(FOutput.CommaText = 'g1.1,g2.1,g1.2,g2.2,g1.3');
end;

procedure TGreenletTests.JoinAll2;
var
  G1, G2: TGreenlet;
  LittleCount, BigCount: Integer;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g1.1', 'g1.2', 'g1.3']);
  G2 := TGreenlet.Spawn(InfiniteRoutine);
  CheckFalse(JoinAll(100));
  LittleCount := FOutput.Count;
  FOutput.Clear;
  CheckFalse(JoinAll(1000));
  BigCount := FOutput.Count;
  Check(Round(BigCount/LittleCount) > 5);
  Check(LittleCount > 1000)
end;

procedure TGreenletTests.JoinAllReraiseErrors;
var
  G: TSymmetric<Integer, string>;
  ErrMsg: string;
begin
  ErrMsg := '';
  G := TSymmetric<Integer, string>.Spawn(RaiseEAfterTimeout, 100, 'test-error');
  try
    JoinAll;
  except
    on E: ETestError do begin
      ErrMsg := E.Message
    end;
  end;
  Check(ErrMsg = 'test-error');
end;

procedure TGreenletTests.JoinReraiseErrors;
var
  G: TSymmetric<Integer, string>;
  ErrMsg: string;
begin
  ErrMsg := '';
  G := TSymmetric<Integer, string>.Spawn(RaiseEAfterTimeout, 100, 'test-error');
  try
    Join([G], INFINITE, True);
  except
    on E: ETestError do begin
      ErrMsg := E.Message
    end;
  end;
  Check(ErrMsg = 'test-error');
end;

procedure TGreenletTests.Kill;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  G.Switch;
  G.Switch;
  G.Kill;
  Check(FOutput.Count = 4, 'problem 1');
  Check(FOutput[0] = '0', 'problem 2');
  Check(FOutput[1] = '1', 'problem 3');
  Check(FOutput[2] = '2', 'problem 4');
  Check(FOutput[3] = 'terminated');
end;

procedure TGreenletTests.KillCbLog;
begin
  FOutput.Add('kill')
end;

procedure TGreenletTests.KillCbRoutine;
var
  I: Integer;
begin
  RegisterKillHandler(KillCbLog);
  for I := 1 to 3 do begin
    Greenlets.Yield;
    FOutput.Add(IntToStr(I));
  end
end;

procedure TGreenletTests.KillingContext;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(KillingRegRoutine);
  G.SetName('killing');
  Join([G], 100);
  G.Kill;
  Check(FOutput.CommaText = G.GetName);
end;

procedure TGreenletTests.KillingRegRoutine;
begin
  try
    while True do
      Greenlets.Yield;
  finally
    FOutput.Add(TRawGreenletImpl(GetCurrent).GetName)
  end;
end;

procedure TGreenletTests.KillTriggers;
var
  G: IRawGreenlet;
begin
  G := TSymmetric.Spawn(KillCbRoutine);
  Check(FOutput.CommaText = '');
  G.Join;
  Check(FOutput.CommaText = '1,2,3,kill');
end;

procedure TGreenletTests.LogHubFlags(const Timeout: Integer);
begin
  while True do begin
   FOutput.Add(Format('suspended:%s', [BoolToStr(GetCurrentHub.IsSuspended)]));
   GreenSleep(Timeout);
  end
end;

function TGreenletTests.Loop1Routine(const E1, E2: TGevent;
  const Sync: Boolean): TWaitResult;
begin
  Greenlets.GreenSleep(300);
  FOutput.Add('1');
  E1.SetEvent(Sync);  // напрямую переключим контекст и тут же в ожидание
  FOutput.Add('1');
  Result := E2.WaitFor;
  FOutput.Add('1');
end;

function TGreenletTests.Loop2Routine(const E1, E2: TGevent;
  const Sync: Boolean): TWaitResult;
begin
  FOutput.Add('2');
  Result := E1.WaitFor;
  FOutput.Add('2');
  Greenlets.GreenSleep(300);
  FOutput.Add('2');
  E2.SetEvent(Sync);
  FOutput.Add('2');
end;

procedure TGreenletTests.LoopProtect;
var
  G1, G2, G3: IRawGreenlet;
  G1Counter, G2Counter, G3Counter: Integer;
begin
  G1Counter := 0;
  G2Counter := 0;
  G3Counter := 0;

  G1 := TGreenlet.Create(procedure
    begin
      while True do begin
        Inc(G1Counter);
        G2.Switch;
      end
    end
  );

  G2 := TGreenlet.Create(procedure
    begin
      while True do begin
        Inc(G2Counter);
        G3.Switch;
      end
    end
  );

  G3 := TGreenlet.Create(procedure
    begin
      while True do begin
        Inc(G3Counter);
        G1.Switch;
      end
    end
  );

  G1.Switch;

  G1.Kill;
  G2.Kill;
  G3.Kill;

  G1 := nil;
  G2 := nil;
  G3 := nil;
  {$IFDEF DEBUG}
  DebugString(IntToStr(G1Counter));
  DebugString(IntToStr(G2Counter));
  DebugString(IntToStr(G3Counter));
  {$ENDIF}
  Check(G1Counter > 0);
  Check(G2Counter > 0);
  Check(G3Counter > 0);
end;

procedure TGreenletTests.MaxCallPerThread;
var
  G1, G2, G3: IRawGreenlet;
  I, Counter: Integer;
begin
  G1 := TSymmetric.Create(CallFromCallstack);
  G2 := TSymmetric.Create(CallFromCallstack);
  G3 := TSymmetric.Create(CallFromCallstack);
  Counter := 1;
  for I := 0 to TRawGreenletImpl.MAX_CALL_PER_THREAD + 10 do begin
    case Counter of
      0: FCallStack.Add(G1);
      1: FCallStack.Add(G2);
      2: FCallStack.Add(G3);
    end;
    Counter := (Counter + 1) mod 3
  end;
  Join([G1, G2, G3]);
  Check(FCallStack.Count = 0);
  Check(FOutput.Count = 1);
end;

procedure TGreenletTests.MaxGreenletsCount;
var
  Gs: array of IRawGreenlet;
  I: Integer;
begin
  SetLength(Gs, 1000);
  for I := 0 to High(Gs) do begin
    Gs[I] := TSymmetric.Spawn(InfiniteRoutine)
  end;
  Join(Gs, 1000, True)
end;

procedure TGreenletTests.MegaJoinTree;
var
  G1, G2, G11, G12, G13, G21, G22, G23: IRawGreenlet;
begin
  G11 := TGreenlet.Create(PrintOrSleepRoutine, ['g11', 'g11', 'g11']);
  G12 := TGreenlet.Create(PrintOrSleepRoutine, ['g12', 100,   'g12']);
  G13 := TGreenlet.Create(PrintOrSleepRoutine, ['g13', 300,   'g13']);

  G21 := TGreenlet.Create(PrintOrSleepRoutine, ['g21', 200,   'g21']);
  G22 := TGreenlet.Create(PrintOrSleepRoutine, ['g22', 500,   'g22']);
  G23 := TGreenlet.Create(PrintOrSleepRoutine, [1000,  'g23', 'g23']);

  G1 := TGreenlet.Create(NonRootJoinRoutine, [G11, G12, G13]);
  G2 := TGreenlet.Create(NonRootJoinRoutine, [G21, G22, G23]);

  CheckFalse(JoinAll(0));
  CheckTrue(JoinAll(3000));
  Check(FOutput.CommaText = 'g11,g11,g11,g12,g13,g21,g22,start,start,g12,g21,g13,stop,g22,g23,g23,stop');
end;

procedure TGreenletTests.NonRootJoin1;
var
  G1, G2, G3, Joiner: IRawGreenlet;
begin
  G1 := TGreenlet.Create(PrintRoutine, ['g-1.1', 'g-1.2']);
  G2 := TGreenlet.Create(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Create(PrintRoutine, ['g-3.1']);
  Joiner := TGreenlet.Create(NonRootJoinRoutine, [G1, G2, G3]);
  try
    Joiner.Join;
    Check(FOutput[0] = 'start');
    Check(FOutput[1] = 'g-1.1');
    Check(FOutput[2] = 'g-2.1');
    Check(FOutput[3] = 'g-3.1');
    Check(FOutput[4] = 'g-1.2');
    Check(FOutput[5] = 'g-2.2');
    Check(FOutput[6] = 'g-2.3');
    Check(FOutput[7] = 'stop');
  finally
    
  end;
end;

procedure TGreenletTests.NonRootJoin2;
var
  G1, G2, G3: IRawGreenlet;
  Joiner: IAsymmetric<Boolean>;
  OK: Boolean;
  Stamp: TTime;
begin
  G1 := TGreenlet.Create(InfiniteRoutine);
  G2 := TGreenlet.Create(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Create(PrintRoutine, ['g-3.1']);
  Joiner := TAsymmetric<IRawGreenlet, IRawGreenlet, IRawGreenlet, Integer, Boolean>.Create(NonRootJoinTimeoutRoutine, G1, G2, G3, 300);
  Stamp := Now;
  OK := Joiner.GetResult;
  CheckFalse(OK, 'problem 1');
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 290));
  Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem timeout: ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.NonRootJoin3;
var
  G1, G2, G3: TGreenlet;
  Joiner: IAsymmetric<Boolean>;
  OK: Boolean;
begin
  G1 := TGreenlet.Create(PrintRoutine, ['g-1.1', 'g-1.2']);
  G2 := TGreenlet.Create(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Create(PrintRoutine, ['g-3.1']);
  Joiner := TAsymmetric<IRawGreenlet, IRawGreenlet, IRawGreenlet, Integer, Boolean>.Create(NonRootJoinTimeoutRoutine, G1, G2, G3, 300);
  OK := Joiner.GetResult;
  CheckTrue(OK, 'problem 1');
  Check(FOutput[0] = 'start');
  Check(FOutput[1] = 'g-1.1');
  Check(FOutput[2] = 'g-2.1');
  Check(FOutput[3] = 'g-3.1');
  Check(FOutput[4] = 'g-1.2');
  Check(FOutput[5] = 'g-2.2');
  Check(FOutput[6] = 'g-2.3');
  Check(FOutput[7] = 'stop');
end;

procedure TGreenletTests.NonRootJoinExceptions;
var
  G1: IAsymmetric<Boolean>;
  G2, G3, Joiner: IRawGreenlet;
  Error: Exception;
begin
  G1 := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 1, True);
  G2 := TGreenlet.Create(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Create(PrintRoutine, ['g-3.1']);
  Joiner := TGreenlet.Create(NonRootJoinRoutine, [G1, G2, G3]);
  try
    Join([Joiner], INFINITE, True);
  except
    on E: ETestError do begin
      Error := E;
      Check(Error.Message = 'test error');
    end;
  end;
  Check(Joiner.GetState = gsException);
  Check(Joiner.GetException.ClassType = ETestError);
end;

procedure TGreenletTests.NonRootJoinRoutine(const A: array of const);
var
  G1, G2, G3: IRawGreenlet;
begin
  G1 := IRawGreenlet(A[0].AsInterface);
  G2 := IRawGreenlet(A[1].AsInterface);
  G3 := IRawGreenlet(A[2].AsInterface);
  FOutput.Add('start');
  Join([G1, G2, G3], INFINITE, True);
  FOutput.Add('stop');
end;

function TGreenletTests.NonRootJoinTimeoutRoutine(const G1, G2,
  G3: IRawGreenlet; const Timeout: Integer): Boolean;
begin
  FOutput.Add('start');
  Result := Join([G1, G2, G3], Timeout);
  FOutput.Add('stop');
end;

procedure TGreenletTests.NonRootSelect;
var
  G1, G2, G3, Selector: IRawGreenlet;
  Stamp: TTime;
begin
  G1 := TSymmetric<Integer>.Spawn(GSleepRoutine, 3000);
  G2 := TSymmetric<Integer>.Spawn(GSleepRoutine, 300);
  G3 := TSymmetric<Integer>.Spawn(GSleepRoutine, 5000);
  Selector := TGreenlet.Create(NonRootSelectRoutine, [G1, G2, G3]);
  try
    Stamp := Now;
    Join([Selector]);
    Stamp := Now - Stamp;
    Check(FOutput.Count=3);
    Check(FOutput[0] = 'start');
    Check(FOutput[1] = 'select_index=1');
    Check(FOutput[2] = 'stop');
    Check(Stamp >= EncodeTime(0, 0, 0, 290), 'problem 1');
    Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem 2, timeout: ' + IntToStr(Time2TimeOut(Stamp)));
  finally
  end;
end;

procedure TGreenletTests.NonRootSelectRoutine(const A: array of const);
var
  G1, G2, G3: IRawGreenlet;
  Index: Integer;
begin
  G1 := IRawGreenlet(A[0].AsInterface);
  G2 := IRawGreenlet(A[1].AsInterface);
  G3 := IRawGreenlet(A[2].AsInterface);
  FOutput.Add('start');
  Select([G1.GetOnTerminate, G2.GetOnTerminate, G3.GetOnTerminate], Index);
  FOutput.Add('select_index=' + IntToStr(Index));
  FOutput.Add('stop');
end;

function TGreenletTests.NStepRunner(const N: Integer;
  const DoError: Boolean): Boolean;
var
  Counter: Integer;
begin
  Counter := N;
  while Counter > 0 do begin
    Greenlets.Yield;
    Dec(Counter);
  end;
  if DoError then
    raise ETestError.Create('test error');
  Result := True;
end;

procedure TGreenletTests.OnGLSTestFree(Sender: TObject);
begin
  FOutput.Add('OnDestroy')
end;

procedure TGreenletTests.Print(const Msg: string);
begin
  FOutput.Add(Msg)
end;

procedure TGreenletTests.PrintHallo;
begin
  FOutput.Add('hallo')
end;

procedure TGreenletTests.PrintOrSleepRoutine(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do begin
    if A[I].IsInteger then
      GreenSleep(A[I].AsInteger)
    else if A[I].IsString then
      FOutput.Add(A[I].AsString)
  end;
end;

procedure TGreenletTests.PrintRoutine(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do begin
    FOutput.Add(A[I].AsString);
    Greenlets.Yield;
  end;
end;

procedure TGreenletTests.RaiseEAfterTimeout(const Timeout: Integer;
  const Msg: string);
begin
  GreenSleep(Timeout);
  raise ETestError.Create(Msg);
end;

procedure TGreenletTests.Regress1;
var
  G: IRawGreenlet;
begin
  {
    Эмуляция проблемы, которая проявляется при запуске
    дерева сопрограмм
  }
  G := TGreenlet.Spawn(Regress1Routine);
  G.SetName('Joiner[TGreenletTests.Regress1Routine]');
  G.Join;
end;

procedure TGreenletTests.Regress1Routine;
var
  G1, G2, G3: IRawGreenlet;
begin
  G1 := TGreenlet.Spawn(SleepSequence, [100]);
  G1.SetName('No1[TGreenletTests.SleepSequence]');
  G2 := TGreenlet.Spawn(SleepSequence, [300]);
  G2.SetName('No2[TGreenletTests.SleepSequence]');
  G3 := TGreenlet.Spawn(SleepSequence, [100]);
  G3.SetName('No3[TGreenletTests.SleepSequence]');
  Join([G1]);
  Join([G1, G2, G3]);
end;

procedure TGreenletTests.Regress2;
var
  Ge: TGevent;
  E: TEvent;
  G: TSymmetric<TGevent, Integer>;
  Stamp: TTime;
  T: TPulseEventThread;
begin
  {
    Эмуляция проблемы, которая проявляется при
    сбрасывании системного события из другой нитки
  }
  E := TEvent.Create(nil, False, False, '');
  Ge := TGevent.Create(E.Handle);
  T := TPulseEventThread.Create(E, 1000);
  G := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge, 2000);

  try
    Stamp := Now;
    Join([G], 3000);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 900), 'problem 1.1, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
    Check(Stamp <= EncodeTime(0, 0, 1, 100), 'problem 1.2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
  finally
    E.Free;
    Ge.Free;
    T.Free;
  end;
end;

procedure TGreenletTests.Regress3;
var
  GeventRefTmp: Integer;

  procedure Step(EventsNum: Integer = 1);
  var
    E: array of TEvent;
    Ge: array of TGevent;
    T: array of TPulseEventThread;
    G: array of IRawGreenlet;
    STamp: TTime;
    I: Integer;
  begin
    SetLength(E, EventsNum);
    SetLength(Ge, EventsNum);
    SetLength(T, EventsNum);
    SetLength(G, EventsNum);
    for I := 0 to EventsNum-1 do begin
      E[I] := TEvent.Create(nil, False, False, '');
      Ge[I] := TGevent.Create(E[I].Handle);
      T[I] := TPulseEventThread.Create(E[I], 1000);
      G[I] := TSymmetric<TGevent, Integer>.Spawn(GEventWait, Ge[I], 2000);
    end;
    try
      Stamp := Now;
      Join(G, 3000);
      Stamp := Now - Stamp;
      Check(Stamp >= EncodeTime(0, 0, 0, 900), 'problem 1, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
      Check(Stamp <= EncodeTime(0, 0, 1, 100), 'problem 2, timeout = ' + IntToStr(Time2TimeOut(Stamp)));
    finally
      for I := 0 to EventsNum-1 do begin
        E[I].Free;
        Ge[I].Free;
        T[I].Free;
      end;
    end;
  end;

begin
  {
    Эмуляция проблемы, которая проявляется при
    проходе 2 шагов
    1- запуск ожидания срабатывания Event-ов
    2- после Join запуск ожидания других Event-ов
    comment: если массив хаба не закроет старые- будет ошибка
  }
  Step(4);
  {$IFDEF DEBUG}
  GeventRefTmp := GeventCounter;
  GeventCounter := GeventRefTmp;
  {$ENDIF}
  Step(1);
end;

procedure TGreenletTests.Regress4;
var
  G: IRawGreenlet;
  E: TGevent;

begin
   {
     Ошибка, вызываемая заходом гринлета в Gevent в момент когда
     status == gsKilling
   }
   E := TGevent.Create;
   G := TSymmetric<TGevent>.Spawn(Regress4Routine, E);
   G.Kill;
   E.SetEvent;
   E.Free;
end;

procedure TGreenletTests.Regress4Routine(const E: TGevent);
begin
  try
    GreenSleep(INFINITE);
  finally
    E.WaitFor
  end;
end;

procedure TGreenletTests.Regress5;
var
  Emitter: TSymmetric<TGevent, LongWord>;
  Gevent: TGevent;
  WR: TWaitResult;
  Index: Integer;
begin
  {
    В методе Select сброшенный в сигнал Gevent при повторной
    передаче в Select приводит к срабатыванию Select
    т.к. Gevent не сбрасывается
  }
  Gevent := TGevent.Create;
  try
    Emitter := TSymmetric<TGevent, LongWord>.Spawn(
      procedure(const Gevent: TGevent; const Timeout: LongWord)
      begin
        GreenSleep(Timeout);
        Gevent.SetEvent;
      end,
      Gevent, 200
    );
    WR := Select([Gevent], Index, 1000);
    Check(WR = wrSignaled);
    WR := Select([Gevent], Index, 0);
    Check(WR = wrTimeout);
  finally
    Gevent.Free
  end;
end;

procedure TGreenletTests.Reinit;
var
  G: IAsymmetric<Integer>;
  R1, R2: Integer;
begin
  G := TAsymmetric<Integer, Integer>.Create(AccumRoutine1, 1);
  G.Switch;
  R1 := G.GetResult;
  G := TAsymmetric<Integer, Integer>.Create(AccumRoutine2, 1);
  G.Switch;
  R2 := G.GetResult;
  Check(R1 = 2);
  Check(R2 = 3);
end;

procedure TGreenletTests.RootJoin1;
var
  G1, G2, G3: TGreenlet;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g-1.1', 'g-1.2']);
  G2 := TGreenlet.Spawn(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Spawn(PrintRoutine, ['g-3.1']);
  Join([G1, G2, G3]);
  Check(FOutput[0] = 'g-1.1');
  Check(FOutput[1] = 'g-2.1');
  Check(FOutput[2] = 'g-3.1');
  Check(FOutput[3] = 'g-1.2');
  Check(FOutput[4] = 'g-2.2');
  Check(FOutput[5] = 'g-2.3');
end;

procedure TGreenletTests.RootJoin2;
var
  G1, G2: TGreenlet;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g-1.1', 'g-1.2']);
  G2 := TGreenlet.Spawn(InfiniteRoutine);
  Join([G1, G2], 200);
end;

procedure TGreenletTests.RootJoin3;
var
  G: TGreenlet;
  OK: Boolean;
  Stamp: TTime;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  Stamp := Now;
  OK := Join([G], 300);
  CheckFalse(OK, 'problem 1');
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 290));
  Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem timeout: ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.RootJoin4;
var
  G: TGreenlet;
  OK: Boolean;
begin
  G := TGreenlet.Spawn(PrintRoutine, ['1', '2', '3', '4', '5']);
  OK := Join([G], 300);
  CheckTrue(OK);
end;

procedure TGreenletTests.RootJoin5;
var
  G1, G2, G3: TGreenlet;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g-1.1', 'g-1.2']);
  G2 := TGreenlet.Spawn(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  G3 := TGreenlet.Spawn(PrintRoutine, ['g-3.1']);
  Join([G1, nil, G2, G3, nil]);
  Check(FOutput[0] = 'g-1.1');
  Check(FOutput[1] = 'g-2.1');
  Check(FOutput[2] = 'g-3.1');
  Check(FOutput[3] = 'g-1.2');
  Check(FOutput[4] = 'g-2.2');
  Check(FOutput[5] = 'g-2.3');
end;

procedure TGreenletTests.RootJoinExceptions;
var
  G: TAsymmetric<Integer, Boolean, Boolean>;
  Error: Exception;
begin
  Error := nil;
  G := TAsymmetric<Integer, Boolean, Boolean>.Create(NStepRunner, 3, True);
  try
    Join([G], INFINITE, True);
  except
    on E: ETestError do begin
      Error := E;
      Check(Error.Message = 'test error');
    end;
  end;
  Check(Assigned(Error));
  Check(Error.ClassType = ETestError);
end;

procedure TGreenletTests.RootJoinTimeout;
var
  G1, G2: TGreenlet;
  G3: TSymmetric<Integer>;
  Stamp: TTime;
begin
  G1 := TGreenlet.Spawn(PrintRoutine, ['g-1.1', 'g-1.2']);
  IRawGreenlet(G1).SetName('g1');
  G2 := TGreenlet.Spawn(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  IRawGreenlet(G2).SetName('g2');
  G3 := TSymmetric<Integer>.Spawn(GSleepRoutine, 500);
  IRawGreenlet(G3).SetName('g3');
  try
    Stamp := Now;
    Join([G1, G2, G3], 300);
    Stamp := Now - Stamp;
    Check(Stamp >= EncodeTime(0, 0, 0, 290));
    Check(Stamp <= EncodeTime(0, 0, 0, 310), 'problem timeout: ' + IntToStr(Time2TimeOut(Stamp)));
    Check(FOutput[0] = 'g-1.1');
    Check(FOutput[1] = 'g-2.1');
    Check(FOutput[2] = 'g-1.2');
    Check(FOutput[3] = 'g-2.2');
    Check(FOutput[4] = 'g-2.3');
  finally
  end;
end;

procedure TGreenletTests.RootSelect1;
var
  G1: IRawGreenlet;
  G2: IRawGreenlet;
  Index: Integer;
  Stamp: TTime;
begin
  G1 := TSymmetric<Integer>.Spawn(GSleepRoutine, 500);
  G2 := TSymmetric.Spawn(InfiniteRoutine);
  Stamp := Now;
  Select([G1.GetOnTerminate], Index);
  Stamp := Now - Stamp;
  Check(Index = 0);
  Check(G1.GetOnTerminate.WaitFor(0) = wrSignaled, 'problem 1');
  Check(G2.GetOnTerminate.WaitFor(0) = wrTimeout, 'problem 2');
  Check(Stamp >= EncodeTime(0, 0, 0, 490), 'problem 3');
  Check(Stamp <= EncodeTime(0, 0, 0, 510), 'problem 4, timeout: ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.RootSelect2;
var
  G1: IRawGreenlet;
  G2: IRawGreenlet;
  Index: Integer;
  Stamp: TTime;
begin
  G1 := TSymmetric<Integer>.Spawn(GSleepRoutine, 500);
  G2 := TSymmetric.Spawn(InfiniteRoutine);
  Stamp := Now;
  Select([nil, nil, G1.GetOnTerminate, nil], Index);
  Stamp := Now - Stamp;
  Check(Index = 2);
  Check(G1.GetOnTerminate.WaitFor(0) = wrSignaled, 'problem 1');
  Check(G2.GetOnTerminate.WaitFor(0) = wrTimeout, 'problem 2');
  Check(Stamp >= EncodeTime(0, 0, 0, 490), 'problem 3');
  Check(Stamp <= EncodeTime(0, 0, 0, 510), 'problem 4, timeout: ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.RootSelectRecursion;
var
  E: TMockGevent;
  Index: Integer;
begin
  E := TMockGevent.Create(True, False);
  try
    Select([E], Index, 0);
    Select([E], Index, 100);
    Select([E], Index, 0);
    Check(E.AssocCounter < 2);
  finally
    E.Free;
  end;
end;

procedure TGreenletTests.RootSelectTimeouts;
var
  G1: IRawGreenlet;
  G2: IRawGreenlet;
  Index: Integer;
  Stamp: TTime;
begin
  G1 := TSymmetric<Integer>.Spawn(GSleepRoutine, 600);
  G2 := TSymmetric.Spawn(InfiniteRoutine);
  Stamp := Now;
  Check(Select([G2.GetOnTerminate], Index, 500) = wrTimeout);
  Stamp := Now - Stamp;
  Check(Stamp >= EncodeTime(0, 0, 0, 490), 'problem 5');
  Check(Stamp <= EncodeTime(0, 0, 0, 510), 'problem 5, timeout: ' + IntToStr(Time2TimeOut(Stamp)));
end;

procedure TGreenletTests.TearDown;
begin
  inherited;
  FOutput.Free;
  FGEvent.Free;
  FCallStack.Free;
  {$IFDEF DEBUG}
  // некоторые тесты привоят к вызову DoSomethingLater
  DefHub.Serve(0);
  Check(GreenletCounter = 0, 'GreenletCore.RefCount problems');
  Check(GeventCounter = 0, 'Gevent.RefCount problems');
  {$ENDIF}
end;


procedure TGreenletTests.WaitHandledGeventMultiple;
var
  G1, G2: TGreenlet;
  Ev: TEvent;
begin
  FGEvent.Free;
  Ev := TEvent.Create(nil, True, False, '');
  FGEvent := TGevent.Create(Ev.Handle);
  G1 := TGreenlet.Spawn(GEventRoutine);
  try
    G2 := TGreenlet.Spawn(GEventRoutine);
    GreenSleep(100);
    Ev.SetEvent;
    Join([G1, G2]);
    FGEvent.SetEvent;
    Check(FOutput.CommaText = 'signal,signal');
  finally
    Ev.Free;
  end;
end;

procedure TGreenletTests.YieldResult(const A: array of const);
var
  Val1: Integer;
  Val2: string;
  Val3: string;
begin
  Val1 := A[0].AsInteger + 1;
  Val2 := A[1].AsString;
  if Val2 = 'hallo' then
    Val2 := 'bye';
  Val3 := A[2].AsObject.ClassName;
  TGreenlet.Yield([Val1, Val2, Val3]);
end;

{ TTestObj }

destructor TTestObj.Destroy;
begin
  if Assigned(Self.OnDestroy) then
    Self.OnDestroy(Self);
  inherited;
end;

{ TIntfTestObj }

destructor TIntfTestObj.Destroy;
begin
  if Assigned(Self.OnDestroy) then
    Self.OnDestroy(Self);
  inherited;
end;

{ TSleepThread }

constructor TSleepThread.Create(Timeout: Integer);
begin
  FSleepValue := Timeout;
  inherited Create(False)
end;

procedure TSleepThread.Execute;
begin
  Sleep(FSleepValue);
  Terminate;
end;

{ TPulseEventThread }

constructor TPulseEventThread.Create(Event: TEvent; Timeout: Integer);
begin
  FEvent := Event;
  FTimeout := Timeout;
  inherited Create(False);
end;

procedure TPulseEventThread.Execute;
begin
  Sleep(FTimeout);
  FEvent.SetEvent;
end;

{ TPingPongThread }

constructor TPingPongThread.Create(MyValue, OtherValue: PInteger;
  Timeout: Integer);
begin
  FMyValue := MyValue;
  FOtherValue := OtherValue;
  FTimeout := Timeout;
  FOnRun := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TPingPongThread.Destroy;
begin
  DefHub(Self).Free;
  FOnRun.Free;
  inherited;
end;

procedure TPingPongThread.Execute;
var
  Stop: TTime;
begin
  Stop := Now + TimeOut2Time(FTimeout);
  FOnRun.WaitFor(FTimeout);
  while ((FMyValue^ > 0) or (FOtherValue^ > 0)) and (Stop > Now) do begin
    FPartner.SetEvent;
    if FMyValue^ > 0 then begin
      FMy.WaitFor(Time2TimeOut(Stop - Time));
      Dec(FMyValue^);
    end;
  end;
end;

procedure TPingPongThread.Run(My, Partner: TGevent);
begin
  FMy := My;
  FPartner := Partner;
  FOnRun.SetEvent;
end;

{ TGreenGroupTests }

procedure TGreenGroupTests.Add;
var
  G: TGreenlet;
  Group: TGreenGroup<Integer>;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  {FGroup.Append(G);
  Check(FGroup.Count = 1);}
  CheckTrue(Group.IsEmpty);
  Group[0] := G;
  CheckFalse(Group.IsEmpty);
end;

procedure TGreenGroupTests.Copy;
var
  G: TGreenlet;
  Group1, Group2: TGreenGroup<Integer>;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  Group1[0] := G;
  CheckFalse(Group1.IsEmpty);
  CheckTrue(Group2.IsEmpty);
  Group2 := Group1.Copy;
  CheckFalse(Group2.IsEmpty);
  Group1[0] := nil;
  CheckTrue(Group1.IsEmpty);
  CheckFalse(Group2.IsEmpty);
end;

procedure TGreenGroupTests.GreenletRefCount;
var
  G: IRawGreenlet;
  Group: TGreenGroup<Integer>;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  try
    Group[0] := G;
  finally
    G := nil
  end;
  CheckFalse(Group.IsEmpty);
end;

procedure TGreenGroupTests.InfiniteRoutine;
begin
  while True do
    Greenlets.Yield
end;

procedure TGreenGroupTests.Join;
var
  Group: TGreenGroup<Integer>;
begin
  Group[0] := TGreenlet.Spawn(PrintRoutine, ['g-1.1', 'g-1.2']);
  Group[1] := TGreenlet.Spawn(PrintRoutine, ['g-2.1', 'g-2.2', 'g-2.3']);
  Group[2] := TGreenlet.Spawn(PrintRoutine, ['g-3.1']);
  Group.Join;
  Check(FOutput[0] = 'g-1.1');
  Check(FOutput[1] = 'g-2.1');
  Check(FOutput[2] = 'g-3.1');
  Check(FOutput[3] = 'g-1.2');
  Check(FOutput[4] = 'g-2.2');
  Check(FOutput[5] = 'g-2.3');
end;

procedure TGreenGroupTests.PrintRoutine(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do begin
    FOutput.Add(A[I].AsString);
    Greenlets.Yield;
  end;
end;

procedure TGreenGroupTests.Remove;
var
  G: TGreenlet;
  Group: TGreenGroup<Integer>;
begin
  G := TGreenlet.Spawn(InfiniteRoutine);
  Group[0] := nil;
  CheckTrue(Group.IsEmpty);
  Group[0] := G;
  CheckFalse(Group.IsEmpty);
  Group[0] := nil;
  CheckTrue(Group.IsEmpty);
end;

procedure TGreenGroupTests.SetUp;
begin
  inherited;
  FOutput := TStringList.Create;
end;

procedure TGreenGroupTests.TearDown;
begin
  inherited;
  FOutput.Free;
end;

{ TGreenletProxyTests }

procedure TGreenletProxyTests.BeginThread;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(BeginThreadRoutine);
  Check(G.GetOnTerminate.WaitFor = wrSignaled);
  Check(FOutput.Count = 5);
  Check(FOutput[0] = FOutput[3]);
  Check(FOutput[0] = FOutput[4]);
  Check(FOutput[0] <> FOutput[1]);
  Check(FOutput[1] = FOutput[2]);
end;

procedure TGreenletProxyTests.BeginThreadAndInfiniteLoop;
begin
  Greenlets.BeginThread;
  GreenSleep(INFINITE);
end;

procedure TGreenletProxyTests.BeginThreadRoutine;
begin
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  Greenlets.BeginThread;
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  Greenlets.BeginThread;
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  Greenlets.EndThread;
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  Greenlets.EndThread;
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
end;

procedure TGreenletProxyTests.EInjection;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Create(InfiniteLoop);
  G.Inject(ETestError.Create('injection'));
  Check(G.GetState = gsException);
  Check(Assigned(G.GetException));
  Check(G.GetException.Message = 'injection');
end;

procedure TGreenletProxyTests.Events;
var
  G: IRawGreenlet;
  Waiter: IAsymmetric<TWaitResult>;
  Proxy, KillProxy: IGreenletProxy;
begin
  G := TGreenlet.Spawn(InfiniteLoop);
  Proxy := G.GetProxy;
  Waiter := TAsymmetric<TGevent, TWaitResult>.Create(WaitGevent, Proxy.GetOnStateChanged);
  Waiter.Switch;
  Proxy.Suspend;
  Check(Waiter.GetResult = wrSignaled);
  Check(Proxy.GetState = gsExecute);
  DefHub.Serve(0);
  Check(Proxy.GetState = gsSuspended);

  Waiter := TAsymmetric<TGevent, TWaitResult>.Create(WaitGevent, Proxy.GetOnStateChanged);
  Waiter.Switch;
  Proxy.Resume;
  Check(Waiter.GetResult = wrSignaled);
  Check(Proxy.GetState = gsSuspended);
  DefHub.Serve(0);
  Check(Proxy.GetState = gsExecute);

  Waiter := TAsymmetric<TGevent, TWaitResult>.Create(WaitGevent, Proxy.GetOnStateChanged);
  Waiter.Switch;
  KillProxy := G.GetProxy;

  KillProxy.Kill;
  Check(Waiter.GetResult = wrSignaled);
  Check(Proxy.GetState = gsKilled);
end;

procedure TGreenletProxyTests.FreeBeginThreadOnTerminate;
var
  NumOfGreenThreads: Integer;
  G: IRawGreenlet;
begin
  NumOfGreenThreads := TGreenThread.NumberOfInstances;
  G := TSymmetric.Spawn(BeginThreadAndInfiniteLoop);
  try
    Check(TGreenThread.NumberOfInstances = NumOfGreenThreads + 1);
    G.Kill;
    GreenSleep(1000);
    Check(TGreenThread.NumberOfInstances = NumOfGreenThreads);
  finally

  end;
end;

procedure TGreenletProxyTests.InfiniteLoop;
var
  I: Integer;
begin
  I := 0;
  while True do begin
    FOutput.Add(IntToStr(I));
    Inc(I);
    Greenlets.Yield;
  end;
end;

procedure TGreenletProxyTests.KillAndDestroy;
var
  G: IRawGreenlet;
  Proxy: IGreenletProxy;
begin
  G := TGreenlet.Spawn(InfiniteLoop);
  Proxy := G.GetProxy;
  Proxy.Kill;
  Check(G.GetState = gsKilled);
end;

procedure TGreenletProxyTests.KillAndDestroyThreaded;
var
  Proxy: IGreenletProxy;
  T: TGreenletThread;
begin
  T := TGreenletThread.Create(InfiniteLoop);
  while T.Greenlet = nil do
    Sleep(100);
  Proxy := T.Greenlet.GetProxy;
  try
    CheckFalse(T.Terminated);
    Proxy.Kill;
    T.WaitFor;
    Check(T.Terminated);
  finally
    T.Free;
  end;
end;

procedure TGreenletProxyTests.KillAsyncThread;
begin
  Abort
end;

procedure TGreenletProxyTests.Moves;
var
  T: TGreenThread;
  I: Integer;
  ExpectedList: TStrings;
begin
  SetLength(FAsyncThreads, 5);
  ExpectedList := TStringList.Create;
  ExpectedList.Add(IntToStr(TThread.CurrentThread.ThreadID));
  try
    for I := 0 to High(FAsyncThreads) do begin
      T := TGreenThread.Create;
      FAsyncThreads[I] := T;
      ExpectedList.Add(IntToStr(T.ThreadID));
    end;
    TGreenlet.Spawn(ThreadsWalk);
    Sleep(1000);
    for I := 0 to High(FAsyncThreads) do begin
      DefHub(FAsyncThreads[I]).EnqueueTask(KillAsyncThread);
      FAsyncThreads[I].WaitFor;
      FAsyncThreads[I].Free
    end;
    Check(FOutput.CommaText = ExpectedList.CommaText);
  finally
    ExpectedList.Free
  end
end;

procedure TGreenletProxyTests.MoveToAsyncAndLoop;
begin
  Greenlets.MoveTo(FAsyncThread);
  InfiniteLoop;
end;

procedure TGreenletProxyTests.Pulse;
var
  G: IRawGreenlet;
  Proxy: IGreenletProxy;
begin
  G := TGreenlet.Spawn(InfiniteLoop);
  Proxy := G.GetProxy;
  Proxy.Pulse;
  Check(FOutput.Count = 2);
end;

procedure TGreenletProxyTests.PulseThreaded;
var
  G: IRawGreenlet;
  Proxy: IGreenletProxy;
  T: TAnyMethodThread;
begin
  T := TAnyMethodThread.Create(ThreadedJoin);
  FAsyncThread := TGreenThread(T);
  G := TGreenlet.Spawn(MoveToAsyncAndLoop);
  try
    Proxy := G.GetProxy;
    Proxy.Pulse;
    Sleep(1000);
    Check(FOutput.Count = 2);
  finally
    DefHub(T).EnqueueTask(KillAsyncThread);
    T.WaitFor;
    T.Free;
  end;
end;

procedure TGreenletProxyTests.Regress1;
var
  G: IRawGreenlet;
  Proxy: IGreenletProxy;
begin
  {
    Регресс баг, проявляется в виде exception
    после цикла Suspend-Resume без вызова след такта (где лежит в очереди
    ф-ия Switch )
  }
  G := TGreenlet.Spawn(InfiniteLoop);
  Proxy := G.GetProxy;
  G.Switch;
  Proxy.Suspend;
  Proxy.Resume;
  DefHub.Serve(0);
  Check(Proxy.GetState = gsExecute);
end;

procedure TGreenletProxyTests.SetUp;
begin
  inherited;
  FHub := TSingleThreadHub.Create;
  FLock := TCriticalSection.Create;
  FOutput := TStringList.Create;
end;

procedure TGreenletProxyTests.SleepInfinite;
begin
  GreenSleep(1000000);
end;

procedure TGreenletProxyTests.SuspendResume;
var
  G: IRawGreenlet;
  Proxy: IGreenletProxy;
begin
  G := TGreenlet.Spawn(InfiniteLoop);
  Proxy := G.GetProxy;
  G.Switch;
  Proxy.Suspend;
  DefHub.Serve(0);
  Check(Proxy.GetState = gsSuspended);
  Proxy.Resume;
  DefHub.Serve(0);
  Check(Proxy.GetState = gsExecute);
  // пробуждение произойдет в след цикле мультиплексора
  DefHub.Serve(0);
  Check(FOutput.Count = 3);
end;

procedure TGreenletProxyTests.TearDown;
begin
  inherited;
  FHub.Free;
  FLock.Free;
  FOutput.Free;
end;

procedure TGreenletProxyTests.ThreadedJoin;
var
  Root: IRawGreenlet;
begin
  Root := TGreenlet.Spawn(SleepInfinite);
  Root.Join
end;

procedure TGreenletProxyTests.ThreadsWalk;
var
  T: TGreenThread;
begin
  FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  for T in FAsyncThreads do begin
    MoveTo(T);
    FOutput.Add(IntToStr(TThread.CurrentThread.ThreadID));
  end;
end;

function TGreenletProxyTests.WaitGevent(const E: TGevent): TWaitResult;
begin
  Result := E.WaitFor;
end;

{ TGreenletThread }

constructor TGreenletThread.Create(const Proc: TSymmetricRoutine);
begin
  FRoutine := Proc;
  inherited Create(False);
end;

procedure TGreenletThread.Execute;
begin
  FGreenlet := TGreenlet.Spawn(FRoutine);
  try
    FGreenlet.Join;
  finally
    FGreenlet := nil;
    Terminate
  end;
end;

{ TGreenletMultiThreadTests }

procedure TGreenletMultiThreadTests.AborterProc;
begin
  raise EAbort.Create('abort');
end;

procedure TGreenletMultiThreadTests.AddThreadIdToList1;
begin
  FList1.Add(Pointer(TThread.CurrentThread.ThreadID))
end;

procedure TGreenletMultiThreadTests.AddThreadIdToList1FromThreadToMainHub;
begin
  DefHub(MainThreadID).EnqueueTask(AddThreadIdToList1);
end;

procedure TGreenletMultiThreadTests.AddThreadIdToList1Threaded(const Count: Integer;
  const Delay: Integer);
var
  I: Integer;
begin
  BeginThread;
  {$IFDEF DEBUG}
  DebugString(Format('current thread id: %d', [TThread.CurrentThread.ThreadID]));
  {$ENDIF}
  for I := 1 to Count do begin
    AddThreadIdToList1;
    GreenSleep(Delay);
  end;
  EndThread;
end;

procedure TGreenletMultiThreadTests.AddThreadIdToList2;
begin
  FList2.Add(Pointer(TThread.CurrentThread.ThreadID))
end;

procedure TGreenletMultiThreadTests.Asymmetrcs;
var
  A1, A2, A3: TAsymmetric<Integer, Integer, Integer>;
  Actual, Expected: Integer;
begin
  A1 := TAsymmetric<Integer, Integer, Integer>.Spawn(WaitAndResult, 1000, 1);
  A2 := TAsymmetric<Integer, Integer, Integer>.Spawn(WaitAndResult, 500, 2);
  A3 := TAsymmetric<Integer, Integer, Integer>.Spawn(WaitAndResult, 1000, 3);

  Actual := A1.GetResult + A2.GetResult + A3.GetResult;
  Expected := 1+2+3;

  Check(Expected = Actual);
end;

procedure TGreenletMultiThreadTests.GEventManualWaiter;
begin
  FOutput.Add(WaitStatus2Str(FGEventManual.WaitFor(300)));
  FOutput.Add(WaitStatus2Str(FGEventManual.WaitFor))
end;

procedure TGreenletMultiThreadTests.GEventOnThread;
var
  T: TAnyMethodThread;
begin
  T := TAnyMethodThread.Create(GEventManualWaiter);
  try
    Sleep(500);
    FGEventManual.SetEvent;
    T.WaitFor;
    Check(FOutput[0] = 'timeout');
    Check(FOutput[1] = 'signaled');
  finally
    T.Free;
  end;
end;

procedure TGreenletMultiThreadTests.JoinMoved;
const
  cCount = 5;
  cDelay = 100;
var
  G1: TSymmetric;
  G2: TSymmetric<Integer, Integer>;
  I: Integer;
begin
  FList1 := TList.Create;
  FList2 := TList.Create;
  try
    G1 := TSymmetric.Create(AddThreadIdToList2);
    G2 := TSymmetric<Integer, Integer>.Create(AddThreadIdToList1Threaded, cCount, cDelay);
    Check(Join([G1, G2], cCount*cDelay*2), 'timeout');
    Check(FList2.Count = 1);
    Check(FList2[0] = Pointer(MainThreadID));
    Check(FList1.Count = cCount);
    for I := 0 to FList1.Count-1 do
      Check(FList1[I] <> Pointer(MainThreadID));
  finally
    FList1.Free;
    FList2.Free;
  end;
end;

procedure TGreenletMultiThreadTests.JoinMovedStress;
const
  COUNTER = 10;
var
  I: Integer;
begin
  {$IFDEF DEBUG}
  DebugString(Format('main thread id: %d', [MainThreadId]));
  {$ENDIF}
  for I := 1 to COUNTER do begin
    {$IFDEF DEBUG}
    DebugString(Format('counter: %d', [I]));
    {$ENDIF}
    JoinMoved;
  end;
end;

procedure TGreenletMultiThreadTests.KillMoved;
var
  G: IRawGreenlet;
  I: Integer;
begin
  for I := 0 to 3 do begin
    G := TSymmetric.Spawn(PulseGeventManualOnKill);
    GreenSleep(I*100);
    G.Kill;
    Check(FGEventManual.WaitFor(500) = wrSignaled, 'timeout');
    FGEventManual.ResetEvent;
  end;
end;

procedure TGreenletMultiThreadTests.KillMovedAgressive;
var
  Count, I: Integer;
  G: IRawGreenlet;
begin
  Count := 10;
  for I := 1 to Count do begin
    G := TSymmetric.Spawn(PulseGeventManualOnKill);
  end;
  G.Kill;
  GreenSleep(1000);
  Check(FCounter = Count);
end;

procedure TGreenletMultiThreadTests.PulseGeventManualOnKill;
begin
  BeginThread;
  try
    GreenSleep(INFINITE);
  finally
    Inc( FCounter);
    FGEventManual.SetEvent;
    EndThread; // regress bug
  end;
end;

procedure TGreenletMultiThreadTests.Regress1;
var
  A1, A2: TAsymmetric<LongWord>;
  T: TGreenThread;
  Ret1, Ret2: LongWord;
begin
  {Возникает вылет на ассиметриках, запущенных в одной нитке,
   с ожиданием результатов в рутовом контексте}
  T := TGreenThread.Create;
  try
    A1 := T.Asymmetrics<LongWord>.Spawn<LongWord>(SleepAndRetThreadId, 1000);
    A2 := T.Asymmetrics<LongWord>.Spawn<LongWord>(SleepAndRetThreadId, 1000);
    Ret1 := A1.GetResult;
    Ret2 := A2.GetResult;
    Check(Ret1 <> MainThreadID);
    Check(Ret2 = Ret1);
  finally
    T.Free;
  end;
end;

procedure TGreenletMultiThreadTests.SetUp;
begin
  inherited;
  FGEvent := TGevent.Create;
  FGEventManual := TGEvent.Create(True);
  FOutput := TStringList.Create;
  FCounter := 0;
end;

function TGreenletMultiThreadTests.SleepAndRetThreadId(
  const Timeout: LongWord): LongWord;
begin
  GreenSleep(Timeout);
  Result := TThread.CurrentThread.ThreadID;
end;

procedure TGreenletMultiThreadTests.SyncEventLoseState;
var
  T: TAnyMethodThread;
begin
  FList1 := TList.Create;
  T := TAnyMethodThread.Create(AddThreadIdToList1FromThreadToMainHub);
  try
    T.WaitFor;
    CheckTrue(DefHub.Serve(0));
    Check(FList1.Count = 1);
    Check(LongWord(FList1[0]) = MainThreadID);
  finally
    T.Free;
    FList1.Free
  end;
end;

procedure TGreenletMultiThreadTests.TearDown;
begin
  inherited;
  FGEvent.Free;
  FGEventManual.Free;
  FOutput.Free;
end;

procedure TGreenletMultiThreadTests.ThreadsQueueProc;
var
  T1, T2: TOtherQueueThread;
  I: Integer;
begin
  FList1 := TList.Create;
  FList2 := TList.Create;
  T1 := TOtherQueueThread.Create(INFINITE);
  T2 := TOtherQueueThread.Create(INFINITE);
  Sleep(1000);
  T1.Hub.EnqueueTask(AddThreadIdToList1);
  T1.Hub.EnqueueTask(AddThreadIdToList1);
  T2.Hub.EnqueueTask(AddThreadIdToList2);
  Sleep(100);
  T2.Hub.EnqueueTask(AddThreadIdToList2);
  T1.Hub.EnqueueTask(AddThreadIdToList1);


  // klll threads
  T1.Hub.EnqueueTask(AborterProc);
  T2.Hub.EnqueueTask(AborterProc);

  T1.WaitFor;
  T2.WaitFor;

  try
    Check(FList1.Count = 3, 'thread1 problems');
    for I := 0 to FList1.Count-1 do
      Check(NativeUINt(FList1[I]) = T1.ThreadID, 'thread1 problem');
    Check(T1.CheckFlag, 'flag1 problems');

    Check(FList2.Count = 2, 'thread2 problems');
    Check(T2.CheckFlag, 'flag2 problems');
  finally
    FList1.Free;
    FList2.Free;
    T1.Free;
    T2.Free;
  end;

end;

procedure TGreenletMultiThreadTests.ThreadsQueueProcTimeout;
var
  T: TOtherQueueThread;
begin
  FList1 := TList.Create;
  T := TOtherQueueThread.Create(100);
  Sleep(1000);

  // klll threads
  T.Hub.EnqueueTask(AborterProc);

  T.WaitFor;
  try
    Check(FList1.Count = 0, 'thread problems');
    Check(T.CheckOkCounter = 1, 'flag problems');
  finally
    FList1.Free;
    T.Free;
  end;
end;

function TGreenletMultiThreadTests.WaitAndResult(const Timeout,
  aResult: Integer): Integer;
begin
  BeginThread;
  GreenSleep(Timeout);
  EndThread;
  Result := aResult;
end;

function TGreenletMultiThreadTests.WaitStatus2Str(Status: TWaitResult): string;
begin
  case Status of
    wrSignaled:
      Exit('signaled');
    wrTimeout:
      Exit('timeout');
    wrAbandoned:
      Exit('abandoned');
    wrError:
      Exit('error');
    wrIOCompletion:
      Exit('iocompletition');
  end;
end;

{ TOtherQueueThread }

constructor TOtherQueueThread.Create(CheckTimeout: LongWord);
begin
  FCheckTimeOut := CheckTimeout;
  inherited Create(False);
end;

procedure TOtherQueueThread.Execute;
begin
  FHub := DefHub;
  while True do begin
    FCheckFlag := FHub.Serve(FCheckTimeOut);
    if FCheckFlag then
      Inc(FCheckOkCounter)
  end;
end;


{ TPersistanceTests }

procedure TPersistanceTests.ArgumentRefs0;
var
  A: TTestComponentObj;
  Ref: IGCObject;
begin
  A := TTestComponentObj.Create(nil);
  Ref := GC(A);
  Ref := GC(nil);
  CheckFalse(TGarbageCollector.ExistsInGlobal(A));
end;

procedure TPersistanceTests.ArgumentRefs1;
var
  A: TTestComponentObj;
  G: IRawGreenlet;
begin
  A := TTestComponentObj.Create(nil);
  try
    G := TSymmetric<TTestComponentObj>.Spawn(LogComponent, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    CheckFalse(TGarbageCollector.ExistsInGlobal(A));
  finally
    A.Free
  end;
end;

procedure TPersistanceTests.ArgumentRefs2;
var
  A: TTestComponentObj;
  G: IRawGreenlet;
  Ref: IGCObject;
begin
  A := TTestComponentObj.Create(nil);
  Ref := GC(A);
  G := TSymmetric<TTestComponentObj>.Spawn(LogComponent, A);
  CheckEquals(FLog.CommaText, A.ClassName);
  Ref := GC(nil);
  // гриндет должен скопировать persistence
  CheckFalse(TGarbageCollector.ExistsInGlobal(A));
  FLog.Clear;
  G.Switch;
  // а у себя держать копию
  CheckEquals(FLog.CommaText, A.ClassName);
  FLog.Clear;
  G.Kill;
  CheckEquals(FLog.CommaText, 'term');
end;

procedure TPersistanceTests.ArgumentRefs3;
var
  A: TTestObj;

  procedure InternalProc;
  var
    G: IRawGreenlet;
    Ref: IGCObject;
  begin
    Ref := GC(A);
    G := TSymmetric<TTestObj>.Spawn(LogObject, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    Ref := GC(nil);
    // гриндет должен увеличить число ссылок
    CheckTrue(TGarbageCollector.ExistsInGlobal(A));
    FLog.Clear;
    G.Switch;
    // и держать сылку на оригинал
    CheckEquals(FLog.CommaText, A.ClassName);
    FLog.Clear;
    G.Kill;
    CheckEquals(FLog.CommaText, 'term');
    CheckTrue(TGarbageCollector.ExistsInGlobal(A));
  end;

begin
  A := TTestObj.Create;
  InternalProc;
  CheckFalse(TGarbageCollector.ExistsInGlobal(A));
end;

procedure TPersistanceTests.ArgumentRefs4;
var
  A, Res: TTestObj;
  G: TAsymmetric<TTestObj, TTestObj>;
begin
  A := TTestObj.Create;
  try
    G := TAsymmetric<TTestObj, TTestObj>.Spawn(LogObjectAndReturnHimself, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    Res := G.GetResult;
    CheckFalse(TGarbageCollector.ExistsInGlobal(A));
    CheckTrue(Res = A);
  finally
    A.Free
  end;
end;

procedure TPersistanceTests.ArgumentRefs5;
var
  A, Res: TTestObj;
  GG: IRawGreenlet;

  procedure InternalProc;
  var
    G: TAsymmetric<TTestObj, TTestObj>;
  begin
    GC(A);
    G := TAsymmetric<TTestObj, TTestObj>.Spawn(LogObjectAndReturnHimself, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    Res := G.GetResult;
    CheckTrue(Res = A);
    GC(nil);
    GG := G;
  end;

begin
  A := TTestObj.Create;
  InternalProc;
  // гринлет еще не убит
  CheckTrue(TGarbageCollector.ExistsInGlobal(A));
  GG := nil;
  // а тперь должен быть уничтожен
  CheckFalse(TGarbageCollector.ExistsInGlobal(A));
end;

procedure TPersistanceTests.ArgumentRefs6;
var
  A, Res: TTestComponentObj;
  GG: IRawGreenlet;

  procedure InternalProc;
  var
    G: TAsymmetric<TTestComponentObj, TTestComponentObj>;
  begin
    CheckFalse(TGarbageCollector.ExistsInGlobal(A));
    G := TAsymmetric<TTestComponentObj, TTestComponentObj>.Spawn(LogCompAndReturnHimself, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    Res := G.GetResult;
    GG := G;
  end;

begin
  A := TTestComponentObj.Create(nil);
  try
    A.X := 'string';
    A.Y := 432;
    InternalProc;
    // гринлет копирует TComponent
    CheckFalse(Res = A);
    CheckTrue(Res.IsEqual(A));
    // старый так и остался не в GC
    CheckFalse(TGarbageCollector.ExistsInGlobal(A));
    // а вот результат фиксируется
    CheckTrue(TGarbageCollector.ExistsInGlobal(Res));
    GG := nil;
    CheckFalse(TGarbageCollector.ExistsInGlobal(Res));
  finally
    A.Free
  end;
end;

procedure TPersistanceTests.ArgumentRefs7;
var
  A, Res: TTestComponentObj;
  GG: IRawGreenlet;

  procedure InternalProc;
  var
    G: TAsymmetric<TTestComponentObj, TTestComponentObj>;
  begin
    CheckTrue(TGarbageCollector.ExistsInGlobal(A));
    G := TAsymmetric<TTestComponentObj, TTestComponentObj>.Spawn(LogCompAndReturnHimself, A);
    CheckEquals(FLog.CommaText, A.ClassName);
    Res := G.GetResult;
    GG := G;
  end;

begin
  A := TTestComponentObj.Create(nil);
  GC(A);
  A.X := 'string';
  A.Y := 432;
  InternalProc;
  // гринлет копирует TComponent
  CheckFalse(Res = A);
  CheckTrue(Res.IsEqual(A));
  // старый так и остался не в GC
  CheckTrue(TGarbageCollector.ExistsInGlobal(A));
  // а вот результат фиксируется
  CheckTrue(TGarbageCollector.ExistsInGlobal(Res));
  GG := nil;
  CheckFalse(TGarbageCollector.ExistsInGlobal(Res));
  CheckTrue(TGarbageCollector.ExistsInGlobal(A));
end;

procedure TPersistanceTests.ByteArray;
type
  TByteArray = array[0..10] of Byte;
var
  G: IRawGreenlet;
  Value, NewValue: TTestByteArray;

  function ArrayOf(const Arr: array of Byte): TTestByteArray;
  var
    I: Integer;
  begin
    FillChar(Result, SizeOf(TByteArray), 0);
    for I := 0 to High(Arr) do
      Result[I] := Arr[I]
  end;

begin
  Value := ArrayOf([66, 67, 68]);
  NewValue := ArrayOf([69, 70, 71]);
  G := TSymmetric<TTestByteArray>.Spawn(ByteArrayLog, Value);
  Value[0] := 123;
  G.Switch;
  Value := NewValue;
  G.Switch;
  Check(FLog.Count = 3);
  CheckEquals(FLog[0], 'BCD');
  CheckEquals(FLog[1], 'BCD');
  CheckEquals(FLog[2], 'BCD');
end;

procedure TPersistanceTests.ByteArrayLog(const Bytes: TTestByteArray);
var
  S: AnsiString;
  I: Integer;
begin
  while True do begin
    SetLength(S, 3);
    for I := 0 to 2 do begin
      S[I+1] := AnsiChar(Bytes[I]);
    end;
    FLog.Add(string(S));
    Greenlets.Yield;
  end;
end;

procedure TPersistanceTests.Bytes;
var
  G: IRawGreenlet;
  Value, NewValue: TBytes;

  function ArrayOf(const Arr: array of Byte): TBytes;
  var
    I: Integer;
  begin
    SetLength(Result, Length(Arr));
    for I := 0 to High(Arr) do
      Result[I] := Arr[I]
  end;

begin
  Value := ArrayOf([66, 67, 68]);
  NewValue := ArrayOf([69, 70, 71]);
  G := TSymmetric<TBytes>.Spawn(BytesLog, Value);
  Value[0] := 123;
  G.Switch;
  Value := NewValue;
  G.Switch;
  Check(FLog.Count = 3);
  CheckEquals(FLog[0], 'BCD');
  CheckEquals(FLog[1], 'BCD');
  CheckEquals(FLog[2], 'BCD');
end;

procedure TPersistanceTests.BytesLog(const Bytes: TBytes);
var
  S: AnsiString;
  I: Integer;
begin
  while True do begin
    SetLength(S, Length(Bytes));
    for I := 0 to High(Bytes) do begin
      S[I+1] := AnsiChar(Bytes[I]);
    end;
    FLog.Add(string(S));
    Greenlets.Yield;
  end;
end;

procedure TPersistanceTests.Component;
var
  Arg: TArgument<TTestComponentObj>;
  X, Y: TTestComponentObj;
begin
  X := TTestComponentObj.Create(nil);
  try
    X.X := 'string value';
    X.Y := 123;
    Arg := TArgument<TTestComponentObj>.Create(X);
    Y := Arg;
    Check(Y.IsEqual(X));
    Check(Y <> X);
    Check(TGarbageCollector.ExistsInGlobal(Y));
    CheckFalse(TGarbageCollector.ExistsInGlobal(X));
  finally
    X.Free;
  end;
end;

procedure TPersistanceTests.DoYieldObjects(const A: array of const);
var
  Tuple: tTuple;
  I: Integer;

  procedure Log;
  var
    I: Integer;
    Strs: TStrings;
  begin
    Strs := TStringList.Create;
    Strs.Delimiter := ';';
    try
      for I := 0 to High(Tuple) do
        if Tuple[I].VType = vtObject then
          Strs.Add(Tuple[I].VObject.ClassName);
      FLog.Add(Strs.DelimitedText)
    finally
      Strs.Free
    end;
  end;

begin
  SetLength(Tuple, Length(A));
  for I := 0 to High(A) do
    Tuple[I] := A[I];
  Log;
  while True do begin
    Tuple := TGreenlet.Yield(Tuple);
    Log;
  end;
end;

procedure TPersistanceTests.GArgumentRefs1;
var
  A1: TTestObj;
  A2: TTestComponentObj;
  G: TGreenlet;
begin
  A1 := TTestObj.Create;
  A2 := TTestComponentObj.Create(nil);
  try
    G := TGreenlet.Spawn(DoYieldObjects, [A1, A2]);
    Check(FLog.CommaText = 'TTestObj;TTestComponentObj');
    CheckFalse(TGarbageCollector.ExistsInGlobal(A1));
    CheckFalse(TGarbageCollector.ExistsInGlobal(A2));
  finally
    A1.Free;
    A2.Free;
  end;
end;

procedure TPersistanceTests.GArgumentRefs2;
var
  A1: TTestObj;
  A2: TTestComponentObj;
  G: IRawGreenlet;
  Tup: tTuple;

  procedure RunInternal;
  var
    GG: TGreenlet;
  begin
    CheckFalse(TGarbageCollector.ExistsInGlobal(A1));
    CheckFalse(TGarbageCollector.ExistsInGlobal(A2));

    GC(A1);
    GC(A2);
    GG := TGreenlet.Spawn(DoYieldObjects, [A1, A2]);
    G := GG;
    Check(FLog.CommaText = 'TTestObj;TTestComponentObj');

    Tup := GG.Switch([A1, A2]);
    Check(Tup[0].VObject = A1);
    Check(Tup[1].VObject = A2);

  end;
begin
  A1 := TTestObj.Create;
  A2 := TTestComponentObj.Create(nil);
  RunInternal;
  // пока жив гринлет, ссылки на объекты должня быть
  CheckTrue(TGarbageCollector.ExistsInGlobal(A1));
  CheckTrue(TGarbageCollector.ExistsInGlobal(A2));

  G := nil;
  // а теперь нет
  CheckFalse(TGarbageCollector.ExistsInGlobal(A1));
  CheckFalse(TGarbageCollector.ExistsInGlobal(A2));
end;

procedure TPersistanceTests.GCReplace;
var
  Obj1, Obj2: TTestObj;
  Ref: IGCObject;

  procedure RunInternal;
  begin
    GC(Obj1);
    GC(Obj2);
  end;

begin
  // 1
  Obj1 := TTestObj.Create;
  Obj1.Name := 'obj1';
  Obj2 := TTestObj.Create;
  Obj2.Name := 'obj2';
  Obj1.OnDestroy := LogName;
  Obj2.OnDestroy := LogName;
  Ref := GC(Obj1);
  Ref := GC(Obj2);
  Check(FLog.CommaText = 'obj1');
  // 2
  FLog.Clear;
  Obj1 := TTestObj.Create;
  Obj1.Name := 'obj3';
  Obj2 := TTestObj.Create;
  Obj2.Name := 'obj4';
  Obj1.OnDestroy := LogName;
  Obj2.OnDestroy := LogName;
  RunInternal;
  Check(FLog.IndexOf('obj3') <> -1);
  Check(FLog.IndexOf('obj4') <> -1);
end;

procedure TPersistanceTests.LogComponent(const A: TTestComponentObj);
begin
  try
    while True do begin
      FLog.Add(A.ClassName);
      Greenlets.Yield;
    end;
  finally
    FLog.Add('term')
  end;
end;

procedure TPersistanceTests.LogName(Sender: TObject);
begin
  FLog.Add(TTestObj(Sender).Name)
end;

procedure TPersistanceTests.LogObject(const A: TTestObj);
begin
  try
    while True do begin
      FLog.Add(A.ClassName);
      Greenlets.Yield;
    end;
  finally
    FLog.Add('term')
  end;
end;

function TPersistanceTests.LogObjectAndReturnHimself(const A: TTestObj): TTestObj;
begin
  FLog.Add(A.ClassName);
  GreenSleep(100);
  Result := A;
end;

procedure TPersistanceTests.OnDestroy(Sender: TObject);
begin
  FLog.Add('OnDestroy')
end;

function TPersistanceTests.LogCompAndReturnHimself(
  const A: TTestComponentObj): TTestComponentObj;
begin
  FLog.Add(A.ClassName);
  GreenSleep(100);
  Result := A;
end;

procedure TPersistanceTests.Sane;
var
  NilObj, Thrash, ExistsObj, NonExistsObj: TObject;
  Ref: IGCObject;
begin
  NilObj := nil;
  ExistsObj := TTestObj.Create;
  Ref := GC(ExistsObj);
  NonExistsObj := TTestObj.Create;
  Thrash := TObject($0123);
  try
    CheckFalse(TGarbageCollector.ExistsInGlobal(NilObj));
    CheckFalse(TGarbageCollector.ExistsInGlobal(Thrash));
    CheckFalse(TGarbageCollector.ExistsInGlobal(NonExistsObj));
    CheckTrue(TGarbageCollector.ExistsInGlobal(ExistsObj));

    Ref := nil;
    CheckFalse(TGarbageCollector.ExistsInGlobal(ExistsObj));
  finally
    NonExistsObj.Free;
  end;
end;

procedure TPersistanceTests.SetUp;
begin
  inherited;
  FLog := TStringList.Create;
  {$IFDEF DEBUG}
  GCCounter := 0;
  {$ENDIF}
end;

procedure TPersistanceTests.SmartPoiner1;
var
  SmartRef: TSmartPointer<TTestObj>;
  Obj: TTestObj;
begin
  Obj := TTestObj.Create;
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef := Obj;
  SmartRef.Get.OnDestroy := Self.OnDestroy;
  CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef := nil;
  Check(FLog.CommaText = 'OnDestroy');
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
end;

procedure TPersistanceTests.SmartPoiner2;
var
  SmartRef1, SmartRef2: TSmartPointer<TTestObj>;
  Obj: TTestObj;
begin
  Obj := TTestObj.Create;
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef1 := Obj;
  SmartRef1.Get.OnDestroy := Self.OnDestroy;
  CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  //------------
  SmartRef2 := Obj;
  //------------
  SmartRef1 := nil;
  Check(FLog.CommaText = '');
  CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef2 := nil;
  Check(FLog.CommaText = 'OnDestroy');
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
end;

procedure TPersistanceTests.SmartPoiner3;
var
  SmartRef1, SmartRef2: TSmartPointer<TTestObj>;
  Obj: TTestObj;
begin
  Obj := TTestObj.Create;
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef1 := Obj;
  SmartRef1.Get.OnDestroy := Self.OnDestroy;
  CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  //----------
  SmartRef2 := SmartRef1;
  //----------
  SmartRef1 := nil;
  Check(FLog.CommaText = '');
  CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  SmartRef2 := nil;
  Check(FLog.CommaText = 'OnDestroy');
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
end;

procedure TPersistanceTests.SmartPoiner4;
var
  Obj: TTestObj;

  procedure RunInternal(Obj: TTestObj);
  var
    SmaprPtr: TSmartPointer<TTestObj>;
  begin
    CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
    SmaprPtr := Obj;
    CheckTrue(TGarbageCollector.ExistsInGlobal(Obj));
  end;

begin
  Obj := TTestObj.Create;
  Obj.OnDestroy := Self.OnDestroy;
  RunInternal(Obj);
  Check(FLog.CommaText = 'OnDestroy');
  CheckFalse(TGarbageCollector.ExistsInGlobal(Obj));
end;

procedure TPersistanceTests.Strings;
var
  G: IRawGreenlet;
  Value, NewValue: string;
begin
  Value := 'value1';
  NewValue := 'value2';
  G := TSymmetric<string>.Spawn(StrValueLog, Value);
  Value[1] := '!';
  G.Switch;
  Value := NewValue;
  G.Switch;
  Check(FLog.Count = 3);
  CheckEquals(FLog[0], 'value1');
  CheckEquals(FLog[1], 'value1');
  CheckEquals(FLog[2], 'value1');
end;

procedure TPersistanceTests.StrValueLog(const Value: string);
begin
  while True do begin
    FLog.Add(Value);
    Greenlets.Yield;
  end;
end;

procedure TPersistanceTests.TearDown;
begin
  inherited;
  FLog.Free;
  {$IFDEF DEBUG}
  CheckEquals(GCCounter, 0);
  {$ENDIF}
end;

procedure TPersistanceTests.WordArrayArgument;
type
  TArrayOfInt = array of Word;
var
  Arg: TArgument<TArrayOfInt>;
  X, Y: TArrayOfInt;
  I: Integer;
begin
  SetLength(X, 5);
  for I := 0 to High(X) do
    X[I] := I+1;
  Arg := TArgument<TArrayOfInt>.Create(X);
  Y := Arg;
  X[0] := 123;
  CheckNotEquals(X[0], Y[0]);
  for I := 1 to High(Y) do
    CheckEquals(X[I], Y[I]);
end;

procedure TPersistanceTests.PersistentObj;
var
  Arg: TArgument<TTestPersistanceObj>;
  X, Y: TTestPersistanceObj;
begin
  X := TTestPersistanceObj.Create;
  try
    X.X := 'string value';
    X.Y := 123;
    Arg := TArgument<TTestPersistanceObj>.Create(X);
    Y := Arg;
    Check(Y.IsEqual(X));
    Check(Y <> X);
    Check(TGarbageCollector.ExistsInGlobal(Y));
    CheckFalse(TGarbageCollector.ExistsInGlobal(X));
  finally
    X.Free;
  end;
end;

{ TTestPersistanceObj }

procedure TTestPersistanceObj.AssignTo(Dest: TPersistent);
begin
  if Dest.InheritsFrom(TTestPersistanceObj) then
    with TTestPersistanceObj(Dest) do begin
      X := Self.X;
      Y := Self.Y;
    end;
end;

function TTestPersistanceObj.IsEqual(Other: TPersistent): Boolean;
begin
  Result := Other.InheritsFrom(TTestPersistanceObj);
  if Result then with TTestPersistanceObj(Other) do begin
    Result := (X = Self.X) and (Y = Self.Y)
  end;
end;

{ TTestComponentObj }

procedure TTestComponentObj.AssignTo(Dest: TPersistent);
begin
  if Dest.InheritsFrom(TTestComponentObj) then
    with TTestComponentObj(Dest) do begin
      X := Self.X;
      Y := Self.Y;
    end;
end;

function TTestComponentObj.IsEqual(Other: TComponent): Boolean;
begin
  Result := Other.InheritsFrom(TTestComponentObj);
  if Result then with TTestComponentObj(Other) do begin
    Result := (X = Self.X) and (Y = Self.Y)
  end;
end;

initialization
  RegisterTest('Greenlets', TGreenletTests.Suite);
  RegisterTest('PersistanceTests', TPersistanceTests.Suite);
  RegisterTest('GreenletProxy', TGreenletProxyTests.Suite);
  RegisterTest('GreenGroupTests', TGreenGroupTests.Suite);
  RegisterTest('GreenletMultiThreads', TGreenletMultiThreadTests.Suite);

end.
