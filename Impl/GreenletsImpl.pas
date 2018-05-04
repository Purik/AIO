unit GreenletsImpl;

{$DEFINE USE_NATIVE_OS_API}

interface
uses SysUtils, Gevent, Classes, Boost, SyncObjs, GInterfaces, Hub, Greenlets,
  {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections, System.Rtti{$ENDIF},
  GarbageCollector, PasMP;

type

  // local storage
  TLocalStorage = class
  type
    TValuesArray = array of TObject;
  strict private
    {$IFDEF DCC}
    FStorage: TDictionary<string, TObject>;
    {$ELSE}
    FStorage: TFPGMap<string, TObject>;
    {$ENDIF}
  protected
    function ToArray: TValuesArray;
    procedure Clear;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetValue(const Key: string; Value: TObject);
    function  GetValue(const Key: string): TObject;
    procedure UnsetValue(const Key: string); overload;
    procedure UnsetValue(Value: TObject); overload;
    function  IsExists(const Key: string): Boolean; overload;
    function  IsExists(Value: TObject): Boolean; overload;
    function  IsEmpty: Boolean;
  end;

  TTriggers = record
  strict private
    FCollection: array of TThreadMethod;
    function Find(const Cb: TThreadMethod; out Index: Integer): Boolean;
  public
    procedure OnCb(const Cb: TThreadMethod);
    procedure OffCb(const Cb: TThreadMethod);
    procedure RaiseAll;
  end;


  TRawGreenletImpl = class(TInterfacedObject, IRawGreenlet)
  type
    AExit = class(EAbort);
    ESelfSwitch = class(Exception);
  const
    MAX_CALL_PER_THREAD = 1000;
  strict private
    // context dependencies
    FContext: Boost.TContext;
    FCurrentContext: Boost.TContext;
    // internal flags
    FInjectException: Exception;
    FInjectRoutine: TSymmetricRoutine;
    // fields
    FException: Exception;
    FLS: TLocalStorage;
    FGC: TGarbageCollector;
    FOnStateChange: TGevent;
    FOnTerminate: TGevent;
    FState: tGreenletState;
    //
    FProxy: TObject;
    FLock: SyncObjs.TCriticalSection;
    // triggers
    FKillTriggers: TTriggers;
    FHubTriggers: TTriggers;
    // хаб на котором обслуживаемся
    FHub: TCustomHub;
    FName: string;
    FEnviron: TObject;
    FOrigThread: TThread;
    FSleepEv: TGevent;
    FObjArguments: TList;
    //
    {$IFDEF USE_NATIVE_OS_API}
    class procedure EnterProcFiber(Param: Pointer); stdcall; static;
    {$ELSE}
    FStack: Pointer;
    FStackSize: LongWord;
    function  Allocatestack(Size: NativeUInt): Pointer;
    procedure DeallocateStack(Stack: Pointer; Size: NativeUInt);
    {$ENDIF}
    class procedure EnterProc(Param: Pointer); cdecl; static;
    procedure ContextSetup; inline;
    procedure SetHub(Value: TCustomHub);
    function GetHub: TCustomHub;
  private
    FForcingKill: Boolean;
    FBeginThread: TGreenThread;
  protected
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    procedure Execute; virtual; abstract;
    class function GetStackSize: LongWord; virtual;
    class function IsNativeAPI: Boolean;
    procedure SetState(const Value: tGreenletState);
    procedure Lock; inline;
    procedure Unlock; inline;
    procedure HubChanging(OldHub, NewHub: TCustomHub); virtual;
    class function GetCurrent: TRawGreenletImpl;
    procedure MoveTo(NewHub: THub); overload;
    procedure MoveTo(Thread: TThread); overload;
    procedure BeginThread;
    procedure EndThread;
    class function GetEnviron: IGreenEnvironment;
    property KillTriggers: TTriggers read FKillTriggers;
    property HubTriggers: TTriggers read FHubTriggers;
    class procedure Switch2RootContext(const aDelayedCall: TThreadMethod=nil); static;
    class procedure ClearContexts; static;
    class function GetCallStackIndex: Integer; static;
    property Hub: TCustomHub read GetHub write SetHub;
    procedure Sleep(const Timeout: LongWord);
    property ObjArguments: TList read FObjArguments;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Switch;
    procedure Yield; overload;
    function  GetUID: NativeUInt;
    function  GetProxy: IGreenletProxy;
    procedure Inject(E: Exception); overload;
    procedure Inject(const Routine: TSymmetricRoutine); overload;
    procedure Kill;
    procedure Suspend;
    procedure Resume;
    function  GetState: tGreenletState; inline;
    function  GetException: Exception;
    procedure ReraiseException;
    function  GetInstance: TObject;
    function  GetOnStateChanged: TGevent;
    function  GetOnTerminate: TGevent;
    function  GetName: string;
    procedure SetName(const Value: string);
    function Context: TLocalStorage;
    procedure Join(const RaiseErrors: Boolean = False);
    function GLS: TLocalStorage;
    function GC: TGarbageCollector;
    {$IFDEF DEBUG}
    function RefCount: Integer;
    {$ENDIF}
  end;

  TChannelRefBasket = class(TInterfacedObject)
  strict private
    FChannel: IAbstractChannel;
    FReaderFactor: Integer;
    FWriterFactor: Integer;
  public
    constructor Create(Channel: IAbstractChannel; ReaderFactor, WriterFactor: Integer);
    destructor Destroy; override;
  end;

  // доп прослойка для входных аргументов сопрограмм
  // может облегчить доп. работу по копированию или
  // приведению к персистентному виду

  TArgument<T> = record
  strict private
  type
    PValue = ^T;
  var
    FValue: T;
    FIsObject: Boolean;
    FObject: TObject;
    FSmartObj: IGCObject;
    FIsDynArr: Boolean;
    FChanBasket: IInterface;
  public
    constructor Create(const Value: T; Owner: TRawGreenletImpl = nil);
    class operator Implicit(const A: TArgument<T>): T;
    property IsObject: Boolean read FIsObject;
    property AsObject: TObject read FObject;
  end;

  TResult<T> = record
  strict private
  type
    PValue = ^T;
  var
    FValue: T;
    FIsObject: Boolean;
    FObject: TObject;
    FSmartObj: IGCObject;
  public
    constructor Create(const Value: T; Owner: TRawGreenletImpl);
    class operator Implicit(const A: TResult<T>): T;
  end;

  // implementations

  TGreenletImpl = class(TRawGreenletImpl, IGreenlet)
  strict private
    FRoutine: TSymmetricRoutine;
    FArgRoutine: TSymmetricArgsRoutine;
    FArgStaticRoutine: TSymmetricArgsStatic;
  protected
  const
    MAX_ARG_SZ = 20;
  var
    FArgs: array[0..MAX_ARG_SZ-1] of TVarRec;
    FSmartArgs: array[0..MAX_ARG_SZ-1] of IGCObject;
    FArgsSz: Integer;
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine); overload;
    constructor Create(const Routine: TSymmetricArgsRoutine; const Args: array of const); overload;
    constructor Create(const Routine: TSymmetricArgsStatic; const Args: array of const); overload;
    function  Switch: tTuple; overload;
    function  Switch(const Args: array of const): tTuple; overload;
    function Yield: tTuple; overload;
    function Yield(const A: array of const): tTuple; overload;
  end;

  
  { TGeneratorImpl }

  TGeneratorImpl<T> = class(TInterfacedObject, IGenerator<T>)
  type
    TGenEnumerator = class(GInterfaces.TEnumerator<T>)
    private
      FGen: TGeneratorImpl<T>;
    protected
      function GetCurrent: T; override;
    public
      function MoveNext: Boolean; override;
      property Current: T read GetCurrent;
      procedure Reset; override;
    end;
  private
  type
    TGenGreenletImpl = class(TGreenletImpl)
      FGen: TGeneratorImpl<T>;
    end;
  var
    FGreenlet: IGreenlet;
    FCurrent: T;
    FIsObject: Boolean;
    FYieldExists: Boolean;
    FSmartPtr: TSmartPointer<TObject>;
    function MoveNext: Boolean; dynamic;
    procedure Reset;
    procedure CheckMetaInfo;
    procedure GarbageCollect(const Old, New: T);
  public
    constructor Create(const Routine: TSymmetricRoutine); overload;
    constructor Create(const Routine: TSymmetricArgsRoutine; const Args: array of const); overload;
    constructor Create(const Routine: TSymmetricArgsStatic; const Args: array of const); overload;
    destructor Destroy; override;
    procedure Setup(const Args: array of const);
    function GetEnumerator: GInterfaces.TEnumerator<T>;
    class function Yield(const Value: T): tTuple;
  end;

  TSymmetricImpl = class(TRawGreenletImpl)
  strict private
    FRoutine: TSymmetricRoutine;
    FRoutineStatic: TSymmetricRoutineStatic;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine; Hub: THub=nil); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic; Hub: THub=nil); overload;
  end;

  TSymmetricImpl<T> = class(TRawGreenletImpl)
  strict private
    FArg: TArgument<T>;
    FRoutine: TSymmetricRoutine<T>;
    FRoutineStatic: TSymmetricRoutineStatic<T>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine<T>; const Arg: T; Hub: THub=nil); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T>; const Arg: T; Hub: THub=nil); overload;
  end;

  TSymmetricImpl<T1, T2> = class(TRawGreenletImpl)
  strict private
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
    FRoutine: TSymmetricRoutine<T1, T2>;
    FRoutineStatic: TSymmetricRoutineStatic<T1, T2>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2>; const Arg1: T1; const Arg2: T2; Hub: THub=nil); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2>; const Arg1: T1; const Arg2: T2; Hub: THub=nil); overload;
  end;

  TSymmetricImpl<T1, T2, T3> = class(TRawGreenletImpl)
  strict private
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
    FArg3: TArgument<T3>;
    FRoutine: TSymmetricRoutine<T1, T2, T3>;
    FRoutineStatic: TSymmetricRoutineStatic<T1, T2, T3>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2, T3>; const Arg1: T1; const Arg2: T2; const Arg3: T3; Hub: THub=nil); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const Arg1: T1; const Arg2: T2; const Arg3: T3; Hub: THub=nil); overload;
  end;

  TSymmetricImpl<T1, T2, T3, T4> = class(TRawGreenletImpl)
  strict private
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
    FArg3: TArgument<T3>;
    FArg4: TArgument<T4>;
    FRoutine: TSymmetricRoutine<T1, T2, T3, T4>;
    FRoutineStatic: TSymmetricRoutineStatic<T1, T2, T3, T4>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub=nil); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub=nil); overload;
  end;

  TAsymmetricImpl<Y> = class(TRawGreenletImpl, IAsymmetric<Y>)
  strict private
    FRoutine: TAsymmetricRoutine<Y>;
    FRoutineStatic: TAsymmetricRoutineStatic<Y>;
    FResult: TResult<Y>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TAsymmetricRoutine<Y>; Hub: THub=nil); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<Y>; Hub: THub=nil); overload;
    destructor Destroy; override;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetricImpl<T, Y> = class(TRawGreenletImpl, IAsymmetric<Y>)
  strict private
    FRoutine: TAsymmetricRoutine<T, Y>;
    FRoutineStatic: TAsymmetricRoutineStatic<T, Y>;
    FResult: TResult<Y>;
    FArg: TArgument<T>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T, Y>; const Arg: T; Hub: THub=nil); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T, Y>; const Arg: T; Hub: THub=nil); overload;
    destructor Destroy; override;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetricImpl<T1, T2, Y> = class(TRawGreenletImpl, IAsymmetric<Y>)
  strict private
    FRoutine: TAsymmetricRoutine<T1, T2, Y>;
    FRoutineStatic: TAsymmetricRoutineStatic<T1, T2, Y>;
    FResult: TResult<Y>;
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, Y>; const Arg1: T1; const Arg2: T2; Hub: THub=nil); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const Arg1: T1; const Arg2: T2; Hub: THub=nil); overload;
    destructor Destroy; override;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetricImpl<T1, T2, T3, Y> = class(TRawGreenletImpl, IAsymmetric<Y>)
  strict private
    FRoutine: TAsymmetricRoutine<T1, T2, T3, Y>;
    FRoutineStatic: TAsymmetricRoutineStatic<T1, T2, T3, Y>;
    FResult: TResult<Y>;
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
    FArg3: TArgument<T3>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const Arg1: T1; const Arg2: T2; const Arg3: T3; Hub: THub=nil); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const Arg1: T1; const Arg2: T2; const Arg3: T3; Hub: THub=nil); overload;
    destructor Destroy; override;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetricImpl<T1, T2, T3, T4, Y> = class(TRawGreenletImpl, IAsymmetric<Y>)
  strict private
    FRoutine: TAsymmetricRoutine<T1, T2, T3, T4, Y>;
    FRoutineStatic: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>;
    FResult: TResult<Y>;
    FArg1: TArgument<T1>;
    FArg2: TArgument<T2>;
    FArg3: TArgument<T3>;
    FArg4: TArgument<T4>;
  protected
    procedure Execute; override;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub=nil); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub=nil); overload;
    destructor Destroy; override;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TGreenGroupImpl<KEY> = class(TInterfacedObject, IGreenGroup<KEY>)
  strict private
    {$IFDEF DCC}
    FMap: TDictionary<KEY, IRawGreenlet>;
    {$ELSE}
    FMap: TFPGMap<KEY, IRawGreenlet>;
    {$ENDIF}
    FOnUpdated: TGevent;
    FList: TList;
    function  IsExists(const Key: KEY): Boolean;
    procedure Append(const Key: KEY; G: IRawGreenlet);
    procedure Remove(const Key: KEY);
    procedure SetValue(const Key: KEY; G: IRawGreenlet);
    function  GetValue(const Key: KEY): IRawGreenlet;
  public
    constructor Create;
    destructor Destroy; override;
    property Item[const Index: KEY]: IRawGreenlet read GetValue write SetValue; default;
    procedure Clear;
    procedure KillAll;
    function IsEmpty: Boolean;
    function Join(Timeout: LongWord = INFINITE; const RaiseError: Boolean=False): Boolean;
    function Copy: IGreenGroup<KEY>;
    function Count: Integer;
  end;

  tArrayOfGreenlet = array of IRawGreenlet;
  tArrayOfGevent = array of TGevent;

  TJoiner = class
  strict private
    FList: TList;
    FOnUpdate: TGevent;
    FLock: SyncObjs.TCriticalSection;
    function Find(G: TRawGreenletImpl; out Index: Integer): Boolean;
    function GetItem(Index: Integer): TRawGreenletImpl;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Remove(G: TRawGreenletImpl);
    procedure Append(G: TRawGreenletImpl);
    procedure Clear;
    property OnUpdate: TGevent read FOnUpdate;
    property Count: Integer read GetCount;
    function GetStateEvents: tArrayOfGevent;
    function GetAll: tArrayOfGreenlet;
    function HasExecutions: Boolean;
    property Item[Index: Integer]: TRawGreenletImpl read GetItem; default;
    procedure KillAll;
  end;

  TGCondVariableImpl = class(TInterfacedObject, IGCondVariable)
  strict private
  type
    TCoDescr = record
      Thread: TThread;
      Ctx: NativeUInt;
      GEv: TGEvent;
      Cond: PBoolean;
      IsDestroyed: PBoolean;
      {$IFDEF FPC}
      class operator = (a : TCoDescr; b : TCoDescr): Boolean;
      {$ENDIF}
    end;
    TItems = {$IFDEF DCC}TList<TCoDescr>{$ELSE}TFPGList<TCoDescr>{$ENDIF};
  var
    FQueue: TItems;
    FMutex: TCriticalSection;
    FExternalMutex: Boolean;
    FSync: Boolean;
    procedure Enqueue(const D: TCoDescr;
      aUnlocking: TCriticalSection; aSpinUnlocking: TPasMPSpinLock);
    function Dequeue(out D: TCoDescr): Boolean;
    procedure ForceDequeue(Ctx: NativeUInt; Thread: TThread);
    procedure WaitInternal(aUnlocking: TCriticalSection;
      aSpinUnlocking: TPasMPSpinLock; Gevent: TGevent = nil);
  protected
    property Queue: TItems read FQueue;
    procedure SetSync(const Value: Boolean);
    function GetSync: Boolean;
  public
    constructor Create(aExternalMutex: TCriticalSection = nil);
    destructor Destroy; override;
    procedure Wait(aUnlocking: TCriticalSection = nil); overload;
    procedure Wait(aSpinUnlocking: TPasMPSpinLock); overload;
    procedure Signal;
    procedure Broadcast;
  end;

  TGSemaphoreImpl = class(TInterfacedObject, IGSemaphore)
  type
    EInvalidLimit = class(Exception);
  strict private
  type

    TDescr = class
    strict private
      FNotify: TGevent;
      FRecursion: Integer;
    public
      constructor Create;
      destructor Destroy; override;
      property Notify: TGevent read FNotify;
      property Recursion: Integer read FRecursion write FRecursion;
    end;

    THashTable = {$IFDEF DCC}
                 TDictionary<NativeUInt, TDescr>
                 {$ELSE}
                 TFPGMap<NativeUInt, TDescr>
                 {$ENDIF};
    TQueue = TList;
  var
    FLock: TCriticalSection;
    FQueue: TList;
    FAcqQueue: TList;
    FValue: LongWord;
    FLimit: LongWord;
    FHash: THashTable;
    procedure Enqueue(const Ctx: NativeUInt);
    function Dequeue(out Ctx: NativeUInt): Boolean;
    procedure Lock; inline;
    procedure Unlock; inline;
    function GetCurContext: NativeUInt;
    function AcquireCtx(const Ctx: NativeUint): TDescr;
    function ReleaseCtx(const Ctx: NativeUint): Boolean;
  public
    constructor Create(Limit: LongWord);
    destructor Destroy; override;
    procedure Acquire;
    procedure Release;
    function Limit: LongWord;
    function Value: LongWord;
  end;

  TGMutexImpl = class(TInterfacedObject, IGMutex)
  strict private
    FSem: IGSemaphore;
  public
    constructor Create;
    procedure Acquire;
    procedure Release;
  end;

  TGQueueImpl<T> = class(TInterfacedObject, IGQueue<T>)
  strict private
  type
    TItems = {$IFDEF DCC}TList<T>{$ELSE}TFPGList<T>{$ENDIF};
  var
    FItems: TItems;
    FLock: TCriticalSection;
    FCanDequeue: IGCondVariable;
    FCanEnqueue: IGCondVariable;
    FOnEnqueue: TGEvent;
    FOnDequeue: TGEvent;
    FMaxCount: LongWord;
    procedure RefreshGEvents;
  protected
    property OnEnqueue: TGEvent read FOnEnqueue;
    property OnDequeue: TGEvent read FOnDequeue;
  public
    constructor Create(MaxCount: LongWord = 0);
    destructor Destroy; override;
    procedure Enqueue(A: T);
    procedure Dequeue(out A: T);
    procedure Clear;
    function Count: Integer;
  end;

  TFutureImpl<RESULT, ERROR> = class(TInterfacedObject, IFuture<RESULT, ERROR>)
  private
    FOnFullFilled: TGevent;
    FOnRejected: TGevent;
    FResult: TSmartPointer<RESULT>;
    FErrorCode: TSmartPointer<ERROR>;
    FDefValue: RESULT;
    FErrorStr: string;
  public
    constructor Create;
    destructor Destroy; override;
    function OnFullFilled: TGevent;
    function OnRejected: TGevent;
    function GetResult: RESULT;
    function GetErrorCode: ERROR;
    function GetErrorStr: string;
  end;

  TPromiseImpl<RESULT, ERROR> = class(TInterfacedObject, IPromise<RESULT, ERROR>)
  strict private
    FFuture: TFutureImpl<RESULT, ERROR>;
    FActive: Boolean;
  public
    constructor Create(Future: TFutureImpl<RESULT, ERROR>);
    destructor Destroy; override;
    procedure SetResult(const A: RESULT);
    procedure SetErrorCode(Value: ERROR; const ErrorStr: string = '');
  end;

  TCollectionImpl<T> = class(TInterfacedObject, ICollection<T>)
  type
    TEnumerator<Y> = class(GInterfaces.TEnumerator<Y>)
    strict private
      FCollection: TCollectionImpl<Y>;
      FCurPos: Integer;
    protected
      function GetCurrent: Y; override;
    public
      constructor Create(Collection: TCollectionImpl<Y>);
      function MoveNext: Boolean; override;
      property Current: Y read GetCurrent;
      procedure Reset; override;
    end;
  private
    FList: TList<T>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Append(const A: T; const IgnoreDuplicates: Boolean); overload;
    procedure Append(const Other: ICollection<T>; const IgnoreDuplicates: Boolean); overload;
    procedure Remove(const A: T);
    function Count: Integer;
    function Get(Index: Integer): T;
    function Copy: ICollection<T>;
    procedure Clear;
    function GetEnumerator: GInterfaces.TEnumerator<T>;
  end;

  TCaseImpl = class(TInterfacedObject, ICase)
  strict private
    FIOOperation: TIOOperation;
    FOnSuccess: TGevent;
    FOnError: TGevent;
    FErrorHolder: IErrorHolder<TPendingError>;
    FWriteValueExists: Boolean;
  public
    destructor Destroy; override;
    function GetOperation: TIOOperation;
    procedure SetOperation(const Value: TIOOperation);
    function GetOnSuccess: TGevent;
    procedure SetOnSuccess(Value: TGevent);
    function GetOnError: TGevent;
    procedure SetOnError(Value: TGevent);
    function GetErrorHolder: IErrorHolder<TPendingError>;
    procedure SetErrorHolder(Value: IErrorHolder<TPendingError>);
    function GetWriteValueExists: Boolean;
    procedure SetWriteValueExists(const Value: Boolean);
  end;

  TGeventPImpl = class(TGevent);

{$IFDEF DEBUG}
var
  GreenletCounter: Integer;
  GeventCounter: Integer;

  procedure DebugString(const S: string);
  procedure DebugDump(const Prefix: string; const Ptr: Pointer; Size: LongWord; const Sep: Char = ' ');
{$ENDIF}


function TimeOut2Time(aTimeOut: LongWord): TTime;
function Time2TimeOut(aTime: TTime): LongWord;

// Преобразование TVarRec
function AsString(const Value: TVarRec): string; inline;
function AsObject(const Value: TVarRec): TObject; inline;
function AsInteger(const Value: TVarRec): Integer; inline;
function AsInt64(const Value: TVarRec): Int64; inline;
function AsSingle(const Value: TVarRec): Single; inline;
function AsDouble(const Value: TVarRec): Double; inline;
function AsBoolean(const Value: TVarRec): Boolean; inline;
function AsVariant(const Value: TVarRec): Variant; inline;
function AsDateTime(const Value: TVarRec): TDateTime; inline;
function AsClass(const Value: TVarRec): TClass; inline;
function AsPointer(const Value: TVarRec): Pointer; inline;
function AsInterface(const Value: TVarRec): IInterface; inline;
function AsAnsiString(const Value: TVarRec): AnsiString; inline;
// чек типа
function IsString(const Value: TVarRec): Boolean; inline;
function IsObject(const Value: TVarRec): Boolean; inline;
function IsInteger(const Value: TVarRec): Boolean; inline;
function IsInt64(const Value: TVarRec): Boolean; inline;
function IsSingle(const Value: TVarRec): Boolean; inline;
function IsDouble(const Value: TVarRec): Boolean; inline;
function IsBoolean(const Value: TVarRec): Boolean; inline;
function IsVariant(const Value: TVarRec): Boolean; inline;
function IsClass(const Value: TVarRec): Boolean; inline;
function IsPointer(const Value: TVarRec): Boolean; inline;
function IsInterface(const Value: TVarRec): Boolean; inline;
// finalize TVarRec
procedure Finalize(var Value: TVarRec); inline;

function GetJoiner(Hub: TCustomHub): TJoiner;

implementation
uses Math, TypInfo,
  {$IFDEF MSWINDOWS}
    {$IFDEF DCC}Winapi.Windows{$ELSE}windows{$ENDIF}
  {$ELSE}
    // TODO
  {$ENDIF};

const
  MAX_TUPLE_SIZE = 20;
  HUB_JOINER    = 'B2F22831-7AF8-4498-B0AE-278B1F2038F7';
  GREEN_ENV     = 'D1C68A29-4293-43C5-8CA8-D0C5E8B854DF';
  ATTRIB_DESCR = '8D627073-9CF8-433D-B268-581D9363E51B';

type
  ExceptionClass = class of Exception;

  TGreenletProxyImpl = class(TInterfacedObject, IGreenletProxy)
  strict private
    FBase: TRawGreenletImpl;
    FLock: SyncObjs.TCriticalSection;
    procedure Lock; inline;
    procedure Unlock; inline;
    procedure SetBase(Base: TRawGreenletImpl);
    function GetBase: TRawGreenletImpl;
  protected
    procedure ResumeBase;
    procedure SwitchBase;
    procedure SuspendBase;
    procedure KillBase;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(Base: TRawGreenletImpl);
    property Base: TRawGreenletImpl read GetBase write SetBase;
    destructor Destroy; override;
    procedure Pulse;
    procedure DelayedSwitch;
    procedure Resume;
    procedure Suspend;
    procedure Kill;
    function GetHub: TCustomHub;
    function GetState: tGreenletState;
    function GetException: Exception;
    function GetOnStateChanged: TGevent;
    function GetOnTerminate: TGevent;
    function GetUID: NativeUInt;
  end;

  TUniValue = class(TPersistent)
  strict private
    FStrValue: string;
    FIntValue: Integer;
    FFloatValue: Single;
    FDoubleValue: Double;
    FInt64Value: Int64;
  public
    procedure Assign(Source: TPersistent); override;
    property StrValue: string read FStrValue write FStrValue;
    property IntValue: Integer read FIntValue write FIntValue;
    property FloatValue: Single read FFloatValue write FFloatValue;
    property DoubleValue: Double read FDoubleValue write FDoubleValue;
    property Int64Value: Int64 read FInt64Value write FInt64Value;
  end;

  TGreenEnvironmentImpl = class(TInterfacedObject, IGreenEnvironment)
  strict private
    FStorage: TLocalStorage;
    FNames: TStrings;
    function GetUniValue(const Name: string): TUniValue;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetValue(const Name: string; Value: TPersistent);
    procedure UnsetValue(const Name: string);
    function GetValue(const Name: string): TPersistent;
    procedure SetIntValue(const Name: string; Value: Integer);
    procedure SetStrValue(const Name: string; Value: string);
    procedure SetFloatValue(const Name: string; Value: Single);
    procedure SetDoubleValue(const Name: string; const Value: Double);
    procedure SetInt64Value(const Name: string; const Value: Int64);
    function  GetIntValue(const Name: string): Integer;
    function  GetStrValue(const Name: string): string;
    function  GetFloatValue(const Name: string): Single;
    function  GetDoubleValue(const Name: string): Double;
    function  GetInt64Value(const Name: string): Int64;
    function Copy: TGreenEnvironmentImpl;
    procedure Clear;
  end;

  TKillToken = class(TInterfacedObject)
  strict private
    FKilling: TRawGreenletImpl;
  public
    constructor Create(Killing: TRawGreenletImpl);
    destructor Destroy; override;
    procedure DoIt;
  end;

// Thread Local Storage
threadvar
  Current: TRawGreenletImpl;
  CurrentYieldSz: Integer;
  CurrentYield: array[0..MAX_TUPLE_SIZE-1] of TVarRec;
  CurrentYieldClear: Boolean;
  CallStack: array[1..TRawGreenletImpl.MAX_CALL_PER_THREAD] of TRawGreenletImpl;
  CallIndex: Integer;
  DelayedCall: TThreadMethod;
  RootContext: Boost.TContext;

{$IFDEF USE_NATIVE_OS_API}
{$IFDEF FPC}
  {$I fpc.inc}
{$ENDIF}
function GetRootContext: Boost.TContext;  inline;
begin
  if not Assigned(RootContext) then
    RootContext := Pointer(ConvertThreadToFiber(nil));
  Result := RootContext;
end;
{$ENDIF}

function PushCaller(G: TRawGreenletImpl): Boolean;
begin
  Result := CallIndex < TRawGreenletImpl.MAX_CALL_PER_THREAD;
  if Result then begin
    Inc(CallIndex);
    CallStack[CallIndex] := G;
  end;
end;

function PopCaller: TRawGreenletImpl; inline;
begin
  if CallIndex > 0 then begin
    Result := CallStack[CallIndex];
    Dec(CallIndex);
  end
  else
    Result := nil
end;

function PeekCaller: TRawGreenletImpl; inline;
begin
  if CallIndex > 0 then begin
    Result := CallStack[CallIndex];
  end
  else
    Result := nil
end;

function GetJoiner(Hub: TCustomHub): TJoiner;
begin
  Result := TJoiner(Hub.HLS(HUB_JOINER));
  if not Assigned(Result) then begin
    Result := TJoiner.Create;
    Hub.HLS(HUB_JOINER, Result)
  end;
end;


function GetCurrent: TRawGreenletImpl;
begin
  Result := Current
end;

function GetCurrentYield: tTuple; inline;
begin
  SetLength(Result, CurrentYieldSz);
  if CurrentYieldSz > 0 then
    Move(CurrentYield[0], Result[0], CurrentYieldSz * SizeOf(TVarRec))
end;

{ TSymmetricImpl<T> }

constructor TSymmetricImpl<T>.Create(const Routine: TSymmetricRoutine<T>; const Arg: T; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg := TArgument<T>.Create(Arg);
  FRoutine := Routine;
end;

constructor TSymmetricImpl<T>.Create(
  const Routine:TSymmetricRoutineStatic<T>; const Arg: T; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg := TArgument<T>.Create(Arg);
  FRoutineStatic := Routine;
end;

procedure TSymmetricImpl<T>.Execute;
begin
  if Assigned(FRoutine) then
    FRoutine(FArg)
  else if Assigned(FRoutineStatic) then
    FRoutineStatic(FArg)
end;

function TimeOut2Time(aTimeOut: LongWord): TTime;
var
  H,M,S,MS: Word;
  Tmp: LongWord;
begin
  if aTimeOut = INFINITE then
    Exit(Now + 100000);
  MS := aTimeOut mod 1000;
  S := Trunc(aTimeOut / 1000) mod 60;
  // откинули сек и мсек
  Tmp := LongWord(aTimeOut - 1000*S - MS);
  if Tmp > 0 then begin
    // переводим в минуты
    Tmp := Tmp div (60*1000);
    M := Tmp mod 60;
    H := (Tmp - M) div 60;
  end
  else begin
    H := 0;
    M := 0;
  end;
  Result := EncodeTime(H, M, S, MS);
end;

function Time2TimeOut(aTime: TTime): LongWord;
var
  H,M,S,MS: Word;
begin
  if aTime < 0 then
    Exit(0);
  DecodeTime(aTime, H, M, S, MS);
  Result := MS + S*1000 + M*1000*60 + H*1000*60*60;
end;

{ TLocalStorage }

function TLocalStorage.ToArray: TValuesArray;
var
  I: Integer;
begin
  {$IFDEF DCC}
  SetLength(Result, Length(FStorage.ToArray));
  for I := 0 to High(Result) do
    Result[I] := FStorage.ToArray[I].Value
  {$ELSE}
  SetLength(Result, FStorage.Count);
  for I := 0 to FStorage.Count-1 do
    Result[I] := FStorage.Data[I];
  {$ENDIF}
end;

procedure TLocalStorage.Clear;
var
  Val: TObject;
  IntfInst: IInterface;
  {$IFDEF FPC}I: Integer;{$ENDIF}

  procedure Finalize(A: TObject);
  begin
    if A.GetInterface(IInterface, IntfInst) then
      IntfInst._Release
    else
      A.Free;
  end;

begin
  {$IFDEF DCC}
  for Val in FStorage.Values do
    if Assigned(Val) then begin
      Finalize(Val);
    end;
  {$ELSE}
  for I := 0 to FStorage.Count-1 do begin
    Val := FStorage.Data[I];
    if Assigned(Val) then
      Finalize(Val);
  end;
  {$ENDIF}
  FStorage.Clear;
end;

constructor TLocalStorage.Create;
begin
  {$IFDEF DCC}
  FStorage := TDictionary<string, TObject>.Create
  {$ELSE}
  FStorage := TFPGMap<string, TObject>.Create;
  {$ENDIF}
end;

destructor TLocalStorage.Destroy;
begin
  Clear;
  FStorage.Free;
  inherited;
end;

procedure TLocalStorage.SetValue(const Key: string; Value: TObject);
var
  Intf: IInterface;
begin
  if Value.GetInterface(IInterface, Intf) then
    Intf._AddRef;
  FStorage.Add(Key, Value)
end;

function TLocalStorage.GetValue(const Key: string): TObject;
{$IFDEF FPC}
var
  Index: Integer;
{$ENDIF}
begin
  {$IFDEF DCC}
  if FStorage.ContainsKey(Key) then
    Result := FStorage[Key]
  else
    Result := nil;
  {$ELSE}
  if FStorage.Find(Key, Index) then
    Result := FStorage.Data[Index]
  else
    Result := nil;
  {$ENDIF}
end;

procedure TLocalStorage.UnsetValue(const Key: string);
begin
  if IsExists(Key) then
    FStorage.Remove(Key);
end;

procedure TLocalStorage.UnsetValue(Value: TObject);
var
  {$IFDEF DCC}
  KV: TPair<string, TObject>;
  {$ELSE}
  Index: Integer;
  Key: string;
  {$ENDIF}
begin
  {$IFDEF DCC}
  if IsExists(Value) then begin
    for KV in FStorage.ToArray do
      if KV.Value = Value then begin
        FStorage.Remove(KV.Key);
        Break
      end;
  end;
  {$ELSE}
  Index := FStorage.IndexOfData(Value);
  if Index >= 0 then begin
    Key := FStorage.Keys[Index];
    FStorage.Remove(Key);
  end;
  {$ENDIF}
end;


function TLocalStorage.IsExists(const Key: string): Boolean;
{$IFDEF FPC}
var
  Index: Integer;
{$ENDIF}
begin
  {$IFDEF DCC}
  Result := FStorage.ContainsKey(Key)
  {$ELSE}
  Result := FStorage.Find(Key, Index);
  {$ENDIF}
end;

function TLocalStorage.IsExists(Value: TObject): Boolean;
begin
  {$IFDEF DCC}
  Result := FStorage.ContainsValue(Value);
  {$ELSE}
  Result:= FStorage.IndexOfData(Value) >= 0;
  {$ENDIF}
end;

function TLocalStorage.IsEmpty: Boolean;
begin
  Result := FStorage.Count = 0
end;

function IsString_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtString, vtPChar, vtAnsiString, vtUnicodeString,
    vtPWideChar];
end;

function AsString_(const Value: TVarRec): string; inline;
begin
  case Value.VType of
    vtInteger: Result := IntToStr(Value.VInteger);
    vtBoolean: Result := BoolToStr(Value.VBoolean, True);
    vtChar:    Result := string(Value.VChar);
    vtExtended:Result := FloatToStr(Value.VExtended^);
    vtString:  Result := string(Value.VString^);
    vtPChar:   Result := string(Value.VPChar);
    vtObject:  Result := Format('%s instance: %x', [Value.VObject.ClassName, Value.VObject]);
    vtClass:   Result := Value.VClass.ClassName;
    vtAnsiString: Result := string(Value.VAnsiString);
    vtUnicodeString: Result := string(Value.VUnicodeString);
    vtCurrency: Result := CurrToStr(Value.VCurrency^);
    vtVariant:  Result := string(Value.VVariant^);
    vtInt64:    Result := IntToStr(Value.VInt64^);
    vtPointer:  Result := Format('%x', [Value.VPointer]);
    vtPWideChar: Result := string(Value.VPWideChar);
    vtWideChar: Result := Value.VWideChar;
    else Assert(False, 'Can''t convert VarRec to String');
  end;
end;

function AsAnsiString_(const Value: TVarRec): AnsiString; inline;
begin
  if Value.VType in [vtAnsiString] then
    Result := AnsiString(Value.VAnsiString)
  else if Value.VType in [vtString] then
    Result := AnsiString(Value.VString^)
  else if Value.VType in [vtUnicodeString] then
    Result := AnsiString(Value.VPWideChar)
  else
    Result := '';
end;

function IsObject_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType = vtObject
end;

function AsObject_(const Value: TVarRec): TObject; inline;
begin
  Result := nil;
  case Value.VType of
    vtObject:  Result := Value.VObject;
    vtPointer: Result := TObject(Value.VPointer)
    else Assert(False, 'Can''t convert VarRec to Object');
  end;
end;

function IsInteger_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtInteger]
end;

function AsInteger_(const Value: TVarRec): Integer; inline;
begin
  Result := 0;
  case Value.VType of
    vtInteger: Result := Value.VInteger;
    vtBoolean:
      if Value.VBoolean then
        Result := 1
      else
        Result := 0;
    vtObject:   Result := Integer(Value.VObject);
    vtInt64:    Result := Integer(Value.VInt64^);
    vtPointer:  Result := Integer(Value.VPointer);
    vtVariant:  Result := Value.VVariant^;
    else Assert(False, 'Can''t convert VarRec to Integer');
  end;
end;

function IsInt64_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtInt64]
end;

function AsInt64_(const Value: TVarRec): Int64;  inline;
begin
  Result := 0;
  case Value.VType of
    vtInteger, vtBoolean: Result := aSiNTEGER(Value);
    vtObject:   Result := Int64(Value.VObject);
    vtInt64:    Result := Value.VInt64^;
    vtVariant:  Result := Value.VVariant^;
    else Assert(False, 'Can''t convert VarRec to Int64');
  end;
end;

function IsSingle_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtExtended]
end;

function AsSingle_(const Value: TVarRec): Single; inline;
begin
  Result := 0;
  case Value.VType of
    vtInteger, vtBoolean: Result := AsInteger(Value);
    vtExtended:Result := Value.VExtended^;
    vtCurrency: Result := Value.VCurrency^;
    vtVariant:  Result := Value.VVariant^;
    vtInt64:    Result := Value.VInt64^;
    else Assert(False, 'Can''t convert VarRec to Single');
  end;
end;

function IsDouble_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtExtended]
end;

function AsDouble_(const Value: TVarRec): Double; inline;
begin
  Result := 0;
  case Value.VType of
    vtInteger, vtBoolean: Result := AsInteger(Value);
    vtExtended: Result := Value.VExtended^;
    vtCurrency: Result := Value.VCurrency^;
    vtVariant:  Result := Value.VVariant^;
    vtInt64:    Result := Value.VInt64^;
    else Assert(False, 'Can''t convert VarRec to Double');
  end;
end;

function IsBoolean_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtBoolean]
end;

function AsBoolean_(const Value: TVarRec): Boolean; inline;
begin
  Result := False;
  case Value.VType of
    vtInteger:  Result := AsInteger(Value) <> 0;
    vtBoolean:  Result := Value.VBoolean;
    vtInt64:    Result := AsInt64(Value) <> 0;
    vtVariant:  Result := Value.VVariant^;
    else Assert(False, 'Can''t convert VarRec to Boolean');
  end;
end;

function IsVariant_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtVariant]
end;

function AsVariant_(const Value: TVarRec): Variant;  inline;
begin
  case Value.VType of
    vtInteger: Result := AsInteger(Value);
    vtBoolean: Result := AsBoolean(Value);
    vtChar, vtString,
      vtPChar, vtAnsiString,
      vtUnicodeString: Result := AsString(Value);
    vtExtended:Result := AsDouble(Value);
    vtCurrency: Result := Value.VCurrency^;
    vtVariant:  Result := Value.VVariant^;
    vtInt64:    Result := AsInt64(Value);
    else Assert(False, 'Can''t convert VarRec to Variant');
  end;
end;

function AsDateTime_(const Value: TVarRec): TDateTime;  inline;
begin
  Result := 0;
  case Value.VType of
    vtExtended: Result := AsDouble(Value);
    vtVariant:  Result := AsVariant(Value);
    else Assert(False, 'Can''t convert VarRec to TDateTime');
  end;
end;

function IsClass_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtClass]
end;

function AsClass_(const Value: TVarRec): TClass; inline;
begin
  Result := nil;
  if Value.VType = vtClass then
    Result := Value.VClass
  else
    Assert(False, 'Can''t convert VarRec to Class');
end;

function IsPointer_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtPointer]
end;

function IsInterface_(const Value: TVarRec): Boolean; inline;
begin
  Result := Value.VType in [vtInterface];
end;

procedure Finalize_(var Value: TVarRec); inline;
begin
  case Value.VType of
    vtExtended:   Value.VExtended := nil;
    vtString:     Value.VString^ := '';
    vtPChar:      Value.VPChar := '';
    vtPWideChar:  Value.VPWideChar := '';
    vtAnsiString: string(Value.VAnsiString) := '';
    vtUnicodeString: string(Value.VUnicodeString) := '';
    vtCurrency:   Dispose(Value.VCurrency);
    vtVariant: begin
      // почемуто вылетает ошибка Dispose(Value.VVariant);
      Value.VVariant^ := 0;
    end;
    vtInterface:  IInterface(Value.VInterface) := nil;
    vtWideString: WideString(Value.VWideString) := '';
    vtInt64:      Dispose(Value.VInt64);
    vtObject:     TObject(Value.VObject) := nil;
  end;
  Value.VInteger := 0;
  Value.VType := vtInteger;
end;

function AsPointer_(const Value: TVarRec): Pointer; inline;
begin
  Result := nil;
  case Value.VType of
    vtObject:  Result := Pointer(Value.VObject);
    vtPointer: Result := Value.VPointer
    else Assert(False, 'Can''t convert VarRec to Pointer');
  end;
end;

function AsInterface_(const Value: TVarRec): IInterface; inline;
begin
  Result := nil;
  case Value.VType of
    vtInterface: Result := IInterface(Value.VInterface);
    vtObject: begin
      if not Value.VObject.GetInterface(IInterface, Result) then
        Result := nil
    end;
  end;
end;

function AsString(const Value: TVarRec): string;
begin
  Result := AsString_(Value)
end;

function AsObject(const Value: TVarRec): TObject;
begin
  Result := AsObject_(Value)
end;

function AsInteger(const Value: TVarRec): Integer;
begin
  Result := AsInteger_(Value)
end;

function AsInt64(const Value: TVarRec): Int64;begin
  Result := AsInt64_(Value)
end;

function AsSingle(const Value: TVarRec): Single;
begin
  Result := AsSingle_(Value)
end;

function AsDouble(const Value: TVarRec): Double;
begin
  Result := AsDouble_(Value)
end;

function AsBoolean(const Value: TVarRec): Boolean;
begin
  Result := AsBoolean_(Value)
end;

function AsVariant(const Value: TVarRec): Variant;
begin
  Result := AsVariant_(Value)
end;

function AsDateTime(const Value: TVarRec): TDateTime;
begin
  Result := AsDateTime_(Value)
end;

function AsClass(const Value: TVarRec): TClass;
begin
  Result := AsClass_(Value)
end;

function AsPointer(const Value: TVarRec): Pointer;
begin
  Result := AsPointer_(Value)
end;

function AsInterface(const Value: TVarRec): IInterface;
begin
  Result := AsInterface_(Value)
end;

function AsAnsiString(const Value: TVarRec): AnsiString;
begin
  Result := AsAnsiString_(Value);
end;

function IsString(const Value: TVarRec): Boolean;
begin
  Result := IsString_(Value)
end;

function IsObject(const Value: TVarRec): Boolean;
begin
  Result := IsObject_(Value)
end;

function IsInteger(const Value: TVarRec): Boolean;
begin
  Result := IsInteger_(Value)
end;

function IsInt64(const Value: TVarRec): Boolean;
begin
  Result := IsInt64_(Value)
end;

function IsSingle(const Value: TVarRec): Boolean;
begin
  Result := IsSingle_(Value)
end;

function IsDouble(const Value: TVarRec): Boolean;
begin
  Result := IsDouble_(Value)
end;

function IsBoolean(const Value: TVarRec): Boolean;
begin
  Result := IsBoolean_(Value)
end;

function IsVariant(const Value: TVarRec): Boolean;
begin
  Result := IsVariant_(Value)
end;

function IsClass(const Value: TVarRec): Boolean;
begin
  Result := IsClass_(Value)
end;

function IsPointer(const Value: TVarRec): Boolean;
begin
  Result := IsPointer_(Value)
end;

function IsInterface(const Value: TVarRec): Boolean;
begin
  Result := IsInterface_(Value)
end;

procedure Finalize(var Value: TVarRec);
begin
  Finalize_(Value);
end;


{ TRawGreenletImpl }

constructor TRawGreenletImpl.Create;
var
  Env: TGreenEnvironmentImpl;
begin
  inherited Create;
  FLS := TLocalStorage.Create;
  FGC := TGarbageCollector.Create;
  FState := gsReady;
  {$IFDEF USE_NATIVE_OS_API}
    {$IFDEF DCC}
      FContext := CreateFiber(GetStackSize, @EnterProcFiber, Self);
    {$ELSE}
      FContext := CreateFiber(GetStackSize, TFNFiberStartRoutine(EnterProcFiber), Self);
    {$ENDIF}
  {$ELSE}
  FStack := Allocatestack(GetStackSize);
  FStackSize := GetStackSize;
  FContext := Boost.make_fcontext(FStack, FStackSize, EnterProc);
  {$ENDIF}
  FCurrentContext := FContext;
  FOnStateChange := TGevent.Create;
  TGeventPImpl(FOnStateChange)._AddRef;
  FOnTerminate := TGevent.Create(True);
  TGeventPImpl(FOnTerminate)._AddRef;
  FLock := SyncObjs.TCriticalSection.Create;
  FProxy := TGreenletProxyImpl.Create(Self);
  TGreenletProxyImpl(FProxy)._AddRef;
  SetHub(GetCurrentHub);
  if Current = nil then begin
    Env := TGreenEnvironmentImpl(Hub.HLS(GREEN_ENV));
    if not Assigned(Env) then begin
      Env := TGreenEnvironmentImpl.Create;
      Hub.HLS(GREEN_ENV, Env);
    end;
    FEnviron := Env.Copy;
  end
  else begin
    FEnviron := TGreenEnvironmentImpl(Current.FEnviron).Copy;
  end;
  TGreenEnvironmentImpl(FEnviron)._AddRef;
  FObjArguments := TList.Create;
end;

destructor TRawGreenletImpl.Destroy;
begin
  if FState in [gsExecute, gsSuspended] then
    Kill;
  SetHub(nil);
  if Assigned(FBeginThread) then begin
    FBeginThread.FreeOnTerminate := True;
    FBeginThread.Kill(False);
  end;
  if Assigned(FInjectException) then
    FInjectException.Free;
  if Assigned(FSleepEv) then
    FSleepEv.Free;
  TGreenletProxyImpl(FProxy).Base := nil;
  TGreenletProxyImpl(FProxy)._Release;
  FLS.Free;
  FGC.Free;
  TGreenEnvironmentImpl(FEnviron)._Release;
  TGeventPImpl(FOnStateChange)._Release;
  TGeventPImpl(FOnTerminate)._Release;
  if Assigned(FException) then
    FException.Free;
  {$IFDEF USE_NATIVE_OS_API}
  DeleteFiber(FContext);
  {$ELSE}
  DeallocateStack(FStack, FStackSize);
  FStack := nil;
  {$ENDIF}
  {$IFDEF DEBUG}
  FContext := nil;
  FCurrentContext := nil;
  {$ENDIF}
  FLock.Free;
  FObjArguments.Free;
  inherited;
end;

procedure TRawGreenletImpl.EndThread;
begin
  if FState <> gsExecute then
    Exit;
  if Assigned(FBeginThread) then begin
    if FState = gsExecute then begin
      if Assigned(FBeginThread) then begin
        MoveTo(FOrigThread);
        FBeginThread.Kill(False);
        FBeginThread := nil;
      end;
    end;
  end;
end;

class procedure TRawGreenletImpl.EnterProc(Param: Pointer);
var
  Me: TRawGreenletImpl;
  NewState: tGreenletState;
  I: Integer;
  Ref: IGCObject;
begin
  Me := TRawGreenletImpl(Param);
  Me.SetState(gsExecute);
  NewState := Me.GetState;
  try
    try
      // регистрируем ссылки сборщика мусора у себя тоже
      for I := 0 to Me.FObjArguments.Count-1 do begin
        if TGarbageCollector.ExistsInGlobal(TObject(Me.FObjArguments[I])) then
          Ref := Me.GC.SetValue(TObject(Me.FObjArguments[I]));
      end;
      Ref := nil;
      Me.ContextSetup;
      Me.Execute;
      NewState := gsTerminated;
      Me.FKillTriggers.RaiseAll;
    except
      On e: SysUtils.Exception do begin
        if e.ClassType <> AExit then begin
          Me.FException := e;
          Me.FException.Message := e.Message;
          Me.FException.HelpContext := e.HelpContext;
          AcquireExceptionObject;
          NewState := gsException;
        end
        else begin
          NewState := gsKilled;
        end;
      end;
    end;
  finally
    try
      if Assigned(Me.FBeginThread) then begin
        Me.FBeginThread.Kill(False);
        Me.FBeginThread := nil;
      end;
      Me.FGC.Clear;
      Me.SetState(NewState);
      Me.FOnTerminate.SetEvent;
      // Hub потеряет ссылку на гринлет
      //Me.RemoveFromJoiner - нельзя вызывать, т.к хаб теряет ссылку и получим утечку;
      Me.Yield;
    except
      Me.Switch2RootContext
    end;
  end;
end;

{$IFDEF USE_NATIVE_OS_API}
class procedure TRawGreenletImpl.EnterProcFiber(Param: Pointer);
begin
  EnterProc(Param)
end;

{$ELSE}
function TRawGreenletImpl.Allocatestack(Size: NativeUInt): Pointer;
var
  Limit: Pointer;
begin
  Limit := AllocMem(Size);
  Result := Pointer(NativeUInt(Limit) + Size);
end;

procedure TRawGreenletImpl.DeallocateStack(Stack: Pointer; Size: NativeUInt);
var
  Limit: Pointer;
begin
  if Assigned(Stack) then begin
    Limit := Pointer(NativeUInt(Stack) - Size);
    FreeMemory(Limit);
  end;
end;
{$ENDIF}

function TRawGreenletImpl.GC: TGarbageCollector;
begin
  Result := FGC;
end;

class function TRawGreenletImpl.GetCallStackIndex: Integer;
begin
  Result := CallIndex
end;

class function TRawGreenletImpl.GetCurrent: TRawGreenletImpl;
begin
  Result := Current
end;

procedure TRawGreenletImpl.MoveTo(NewHub: THub);
var
  G: TRawGreenletImpl;
begin
  if NewHub <> nil then begin
    if GetState = gsExecute then begin
      SetHub(NewHub);
    end;
    G := PopCaller;
    if Assigned(G) then begin
      G.GetProxy.DelayedSwitch;
    end;
    Switch2RootContext(TGreenletProxyImpl(Self.FProxy).Pulse);
  end;
end;

procedure TRawGreenletImpl.MoveTo(Thread: TThread);
var
  NewHub: THub;
begin
  if Assigned(Thread) then begin
    NewHub := DefHub(Thread);
    MoveTo(NewHub);
  end;
end;

class function TRawGreenletImpl.GetEnviron: IGreenEnvironment;
var
  Impl: TGreenEnvironmentImpl;
begin
  if Current = nil then begin
    Result := TGreenEnvironmentImpl(GetCurrentHub.HLS(GREEN_ENV));
    if not Assigned(Result) then begin
      Impl := TGreenEnvironmentImpl.Create;
      GetCurrentHub.HLS(GREEN_ENV, Impl);
      Result := Impl;
    end;
  end
  else
    Result := TGreenEnvironmentImpl(Current.FEnviron);
end;

function TRawGreenletImpl.GetException: Exception;
begin
  Result := FException
end;

function TRawGreenletImpl.GetHub: TCustomHub;
begin
  FLock.Acquire;
  Result := FHub;
  FLock.Release;
end;

function TRawGreenletImpl.GetInstance: TObject;
begin
  Result := Self;
end;

function TRawGreenletImpl.GetName: string;
begin
  Lock;
  Result := FName;
  Unlock;
end;

function TRawGreenletImpl.GetOnStateChanged: TGevent;
begin
  Result := FOnStateChange
end;

function TRawGreenletImpl.GetOnTerminate: TGevent;
begin
  Result := FOnTerminate
end;

function TRawGreenletImpl.GetProxy: IGreenletProxy;
begin
  Result := TGreenletProxyImpl(FProxy);
end;

class function TRawGreenletImpl.GetStackSize: LongWord;
begin
  Result := $4000;  // при нативных вызовах в Windows можно уменьшить в 10 раз
end;

function TRawGreenletImpl.GetState: tGreenletState;
begin
  Result := FState
end;

function TRawGreenletImpl.GetUID: NativeUInt;
begin
  Result := NativeUInt(Self)
end;

function TRawGreenletImpl.GLS: TLocalStorage;
begin
  Result := FLS;
end;

procedure TRawGreenletImpl.HubChanging(OldHub, NewHub: TCustomHub);
begin
  if HubInfrasctuctureEnable then begin
    if Assigned(OldHub) then
      GetJoiner(OldHub).Remove(Self);
    if Assigned(NewHub) then
      GetJoiner(NewHub).Append(Self);
  end;
  FHubTriggers.RaiseAll;
  GetOnStateChanged.SetEvent;
  if Assigned(FSleepEv) then
    FreeAndNil(FSleepEv);
end;

procedure TRawGreenletImpl.Inject(E: Exception);
begin
  FInjectException := E;
  Switch;
end;

procedure TRawGreenletImpl.Inject(const Routine: TSymmetricRoutine);
begin
  FInjectRoutine := Routine;
  Switch;
  FInjectRoutine := nil;
end;

class function TRawGreenletImpl.IsNativeAPI: Boolean;
begin
  {$IFDEF USE_NATIVE_OS_API}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TRawGreenletImpl.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TRawGreenletImpl.Kill;
var
  Hub: TCustomHub;
begin
  if (Current.GetInstance = Self) and (FState = gsExecute) then
    raise AExit.Create('trerminated')
  else begin
    Hub := GetHub;
    if FForcingKill then begin
      Inject(AExit.Create('termination'))
    end
    else if FState in [gsExecute, gsSuspended, gsKilling] then begin
      FState := gsKilling;
      if (Hub = GetCurrentHub) or (Hub = nil)  then begin
        Inject(AExit.Create('termination'))
      end
      else begin
        GetProxy.Kill
      end;
    end;
  end;
end;

procedure TRawGreenletImpl.Lock;
begin
  FLock.Acquire;
end;

{$IFDEF DEBUG}
function TRawGreenletImpl.RefCount: Integer;
begin
  Result := FRefCount
end;
{$ENDIF}

procedure TRawGreenletImpl.ReraiseException;
begin
  if Assigned(FException) then begin
    raise ExceptionClass(FException.ClassType).Create(FException.Message);
  end;
end;

procedure TRawGreenletImpl.Resume;
begin
  if FState = gsSuspended then begin
    SetState(gsExecute);
    if GetCurrent <> Self then
      Switch;
  end;
end;

procedure TRawGreenletImpl.SetHub(Value: TCustomHub);
begin
  FLock.Acquire;
  try
    if FHub <> Value then begin
      HubChanging(FHub, Value);
      FHub := Value;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TRawGreenletImpl.SetName(const Value: string);
begin
  Lock;
  FName := Value;
  Unlock;
end;

procedure TRawGreenletImpl.SetState(const Value: tGreenletState);
begin
  Lock;
  try
    if FState <> Value then begin
      FState := Value;
      FOnStateChange.SetEvent;
    end;
  finally
    Unlock;
  end;
end;

procedure TRawGreenletImpl.Sleep(const Timeout: LongWord);
var
  TimeoutHnd: THandle;
begin
  {$IFDEF DEBUG}
  Assert(Current = Self);
  Assert(FHub <> nil);
  {$ENDIF}
  if Assigned(FSleepEv) then
    FSleepEv.Free;
  if Timeout = 0 then begin
    GetProxy.DelayedSwitch;
    Self.Yield;
  end
  else begin
    TimeoutHnd := 0;
    FSleepEv := TGEvent.Create;
    try
      FSleepEv.WaitFor(Timeout)
    finally
      if Timeout <> 0 then
        FHub.DestroyTimeout(TimeoutHnd);
      FreeAndNil(FSleepEv);
    end;
  end;
end;

procedure TRawGreenletImpl.Suspend;
begin
  if FState in [gsReady, gsExecute] then
    SetState(gsSuspended)
end;

procedure TRawGreenletImpl.Switch;
var
  Caller: TRawGreenletImpl;
  GP: IGreenletProxy;
begin
  if not ((GetState in [gsReady, gsExecute]) or Assigned(FInjectException)) then
    Exit;
  if Current = Self then
    raise ESelfSwitch.Create('Self switch denied');
  Caller := Current;
  {$IFDEF USE_NATIVE_OS_API}
  if Current = nil then begin
    GetRootContext;
    CallIndex := 0;
  end;
  if Self = PeekCaller then
    PopCaller;
  if PushCaller(Current) then begin
    Current := Self;
    SwitchToFiber(FCurrentContext);
  end
  else begin
    CallIndex := 0;
    // боремся с memoryleak при исп аноним функций
    GP := GetProxy;
    GP.DelayedSwitch;  // в след цикле продолжим работу
    GP := nil;
    SwitchToFiber(GetRootContext);
  end;
  {$ELSE}
  if Current = nil then begin
    CallIndex := 0;
  end;
  if Self = PeekCaller then
    PopCaller;
  if PushCaller(Current) then begin
    Current := Self;
    if Caller = nil then
      Boost.jump_fcontext(RootContext, FCurrentContext, Self, True)
    else
      Boost.jump_fcontext(Caller.FCurrentContext, FCurrentContext, Self, True);
  end
  else begin
    CallIndex := 0;
    GP := GetProxy;
    GP.DelayedSwitch;  // в след цикле продолжим работу
    GP := nil;
    if Caller <> nil then
      Boost.jump_fcontext(Caller.FCurrentContext, RootContext, Self, True);
  end;
  {$ENDIF}
  Current := Caller;
  if (Current = nil) and Assigned(DelayedCall) then begin
    try
      DelayedCall();
    finally
      DelayedCall := nil;
    end;
  end;
end;

class procedure TRawGreenletImpl.Switch2RootContext(const aDelayedCall: TThreadMethod);
begin
  CallIndex := 0;
  DelayedCall := aDelayedCall;
  {$IFDEF USE_NATIVE_OS_API}
  SwitchToFiber(GetRootContext);
  {$ELSE}
  Boost.jump_fcontext(Current.FCurrentContext, RootContext, GetCurrent, True);
  {$ENDIF}
end;

procedure TRawGreenletImpl.Unlock;
begin
  FLock.Release;
end;

procedure TRawGreenletImpl.Yield;
var
  Caller: TRawGreenletImpl;
begin
  repeat
    Caller := PopCaller;
  until (Caller = nil) or (Caller.GetState in [gsExecute, gsKilling]);
  {$IFDEF USE_NATIVE_OS_API}
  if Caller <> nil then
    SwitchToFiber(Caller.FCurrentContext)
  else
    SwitchToFiber(GetRootContext);
  {$ELSE}
  if Caller <> nil then
    Boost.jump_fcontext(FCurrentContext, Caller.FCurrentContext, Self, True)
  else
    Boost.jump_fcontext(FCurrentContext, RootContext, Self, True);
  {$ENDIF}
  ContextSetup;
end;

function TRawGreenletImpl._AddRef: Integer;
begin
  {$IFDEF DCC}
  Result := AtomicIncrement(FRefCount);
  {$ELSE}
  Result := interlockedincrement(FRefCount);
  {$ENDIF}
  {$IFDEF DEBUG}
  AtomicIncrement(GreenletCounter);
  {$ENDIF}
end;

function TRawGreenletImpl._Release: Integer;
var
  Hub: TCustomHub;
begin
  {$IFDEF DEBUG}
  AtomicDecrement(GreenletCounter);
  {$ENDIF}
  {$IFDEF DCC}
  Result := AtomicDecrement(FRefCount);
  {$ELSE}
  Result := interlockeddecrement(FRefCount);
  {$ENDIF}
  if Result = 0 then begin
    Lock;
    Hub := GetHub;
    if (Hub <> GetCurrentHub) and (Hub <> nil) and (not FForcingKill) then begin
      Hub.EnqueueTask(TKillToken.Create(Self).DoIt);
      Result := 1;
      Unlock;
    end
    else begin
      Unlock;
      Destroy;
    end;
  end;
end;

procedure TRawGreenletImpl.BeginThread;
begin
  if Assigned(FBeginThread) then
    Exit;
  FOrigThread := TThread.CurrentThread;
  FBeginThread := TGreenThread.Create;
  FBeginThread.FreeOnTerminate := True;
  MoveTo(FBeginThread);
end;

class procedure TRawGreenletImpl.ClearContexts;
begin
  {Current := nil;
  CallIndex := 0;
  DelayedCall := nil;
  CurrentYieldClear := False;  }
  //RootContext := nil;
end;

function TRawGreenletImpl.Context: TLocalStorage;
begin
  Result := FLS
end;

procedure TRawGreenletImpl.ContextSetup;
var
  E: Exception;
begin
  if Assigned(FInjectException) then begin
    E := FInjectException;
    FInjectException := nil;
    raise E;
  end;
  while Assigned(FInjectRoutine) do begin
    FInjectRoutine();
    FInjectRoutine := nil;
    Yield;
  end;
end;

{ TSymmetricImpl<T1, T2> }

constructor TSymmetricImpl<T1, T2>.Create(
  const Routine: TSymmetricRoutine<T1, T2>; const Arg1: T1; const Arg2: T2; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FRoutine := Routine;
end;

constructor TSymmetricImpl<T1, T2>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2>; const Arg1: T1; const Arg2: T2; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FRoutineStatic := Routine;
end;

procedure TSymmetricImpl<T1, T2>.Execute;
begin
  if Assigned(FRoutine) then
    FRoutine(FArg1, FArg2)
  else if Assigned(FRoutineStatic) then
    FRoutineStatic(FArg1, FArg2)
end;

{ TSymmetricImpl<T1, T2, T3> }

constructor TSymmetricImpl<T1, T2, T3>.Create(
  const Routine: TSymmetricRoutine<T1, T2, T3>; const Arg1: T1; const Arg2: T2;
  const Arg3: T3; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FArg3 := TArgument<T3>.Create(Arg3);
  FRoutine := Routine;
end;

constructor TSymmetricImpl<T1, T2, T3>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FArg3 := TArgument<T3>.Create(Arg3);
  FRoutineStatic := Routine;
end;

procedure TSymmetricImpl<T1, T2, T3>.Execute;
begin
  if Assigned(FRoutine) then
    FRoutine(FArg1, FArg2, FArg3)
  else if Assigned(FRoutineStatic) then
    FRoutineStatic(FArg1, FArg2, FArg3)
end;

{ TSymmetricImpl<T1, T2, T3, T4> }

constructor TSymmetricImpl<T1, T2, T3, T4>.Create(
  const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const Arg1: T1; const Arg2: T2;
  const Arg3: T3; const Arg4: T4; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FArg3 := TArgument<T3>.Create(Arg3);
  FArg4 := TArgument<T4>.Create(Arg4);
  FRoutine := Routine;
end;

constructor TSymmetricImpl<T1, T2, T3, T4>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1);
  FArg2 := TArgument<T2>.Create(Arg2);
  FArg3 := TArgument<T3>.Create(Arg3);
  FArg4 := TArgument<T4>.Create(Arg4);
  FRoutineStatic := Routine;
end;

procedure TSymmetricImpl<T1, T2, T3, T4>.Execute;
begin
  if Assigned(FRoutine) then
    FRoutine(FArg1, FArg2, FArg3, FArg4)
  else if Assigned(FRoutineStatic) then
    FRoutineStatic(FArg1, FArg2, FArg3, FArg4)
end;

{ TGreenletProxyImpl }

constructor TGreenletProxyImpl.Create(Base: TRawGreenletImpl);
begin
  FBase := Base;
  FLock := SyncObjs.TCriticalSection.Create;
end;

procedure TGreenletProxyImpl.ResumeBase;
var
  Base: TRawGreenletImpl;
begin
  FLock.Acquire;
  Base := FBase;
  FLock.Release;
  if Assigned(Base) then
    Base.Resume;
end;

procedure TGreenletProxyImpl.SwitchBase;
var
  Base: TRawGreenletImpl;
begin
  FLock.Acquire;
  Base := FBase;
  FLock.Release;
  if Assigned(Base) then
    Base.Switch;
end;

procedure TGreenletProxyImpl.KillBase;
var
  Base: TRawGreenletImpl;
begin
  FLock.Acquire;
  Base := FBase;
  FLock.Release;
  if Assigned(Base) then
    Base.Kill;
end;

procedure TGreenletProxyImpl.SuspendBase;
var
  Base: TRawGreenletImpl;
begin
  FLock.Acquire;
  Base := FBase;
  FLock.Release;
  if Assigned(Base) then
    Base.Suspend;
end;

procedure TGreenletProxyImpl.DelayedSwitch;
begin
  FLock.Acquire;
  try
    if FBase = nil then
      Exit;
    FBase.Lock;
    try
      if Assigned(FBase.Hub) and (FBase.GetState in [gsReady, gsExecute, gsKilling]) then begin
        FBase.Hub.EnqueueTask(Self.SwitchBase);
      end;
    finally
      FBase.Unlock;
    end;
  finally
    FLock.Release
  end;
end;

destructor TGreenletProxyImpl.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TGreenletProxyImpl.GetBase: TRawGreenletImpl;
begin
  Lock;
  Result := FBase;
  Unlock;
end;

function TGreenletProxyImpl.GetException: Exception;
begin
  Lock;
  Result := FBase.GetException;
  Unlock;
end;

function TGreenletProxyImpl.GetHub: TCustomHub;
begin
  Lock;
  Result := FBase.Hub;
  Unlock;
end;

function TGreenletProxyImpl.GetOnStateChanged: TGevent;
begin
  Lock;
  Result := FBase.GetOnStateChanged;
  Unlock;
end;

function TGreenletProxyImpl.GetOnTerminate: TGevent;
begin
  Lock;
  Result := FBase.GetOnTerminate;
  Unlock;
end;

function TGreenletProxyImpl.GetState: tGreenletState;
begin
  Lock;
  if FBase = nil then
    Result := gsTerminated
  else
    Result := FBase.GetState;
  Unlock;
end;

function TGreenletProxyImpl.GetUID: NativeUInt;
begin
  Lock;
  Result := FBase.GetUID;
  Unlock;
end;

procedure TGreenletProxyImpl.Kill;
var
  SameHub: Boolean;
  Base: TRawGreenletImpl;
begin
  SameHub := False;
  FLock.Acquire;
  try
    Base := FBase;
    if Base = nil then
      Exit;
    FBase.Lock;
    try
      if Assigned(FBase.Hub) then begin
        SameHub := GetCurrentHub = FBase.Hub;
        if Assigned(FBase.Hub) then
          FBase.Hub.EnqueueTask(Self.KillBase);
      end;
    finally
      FBase.Unlock;
    end;
  finally
    FLock.Release
  end;
  if SameHub then
    Base.Kill;
end;

procedure TGreenletProxyImpl.Lock;
begin
  FLock.Acquire;
end;

procedure TGreenletProxyImpl.Pulse;
var
  SameHub: Boolean;
begin
  SameHub := False;
  FLock.Acquire;
  try
    if FBase = nil then
      Exit;
    FBase.Lock;
    try
      if Assigned(FBase.Hub) and (FBase.GetState in [gsReady, gsExecute, gsKilling]) then begin
        SameHub := FBase.Hub = GetCurrentHub;
        // если обслуживается в удаленном хабе
        if not SameHub then
          FBase.Hub.EnqueueTask(Self.SwitchBase);
      end;
    finally
      FBase.Unlock;
    end;
  finally
    FLock.Release
  end;
  // если обслуживается в тек. хабе то смело отдаем процессор прямо сейчас
  if SameHub  then
    FBase.Switch
end;

procedure TGreenletProxyImpl.Resume;
begin
  FLock.Acquire;
  try
    if not Assigned(FBase) then
      Exit;
    if Assigned(FBase.Hub) then begin
      // пробуждение всегда через хаб
      FBase.Hub.EnqueueTask(Self.ResumeBase);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TGreenletProxyImpl.SetBase(Base: TRawGreenletImpl);
begin
  Lock;
  try
    if Base <> FBase then begin
      FBase := Base;
      if Assigned(FBase) then
        GetOnStateChanged.SetEvent;
    end;
  finally
    Unlock;
  end;
end;

procedure TGreenletProxyImpl.Suspend;
begin
  FLock.Acquire;
  try
    if FBase = nil then
      Exit;
    FBase.Lock;
    try
      FBase.Hub.EnqueueTask(Self.SuspendBase);
    finally
      FBase.Unlock;
    end;
  finally
    FLock.Release
  end;
end;

procedure TGreenletProxyImpl.Unlock;
begin
  FLock.Release;
end;

function TGreenletProxyImpl._AddRef: Integer;
begin
  Result := inherited _AddRef
end;

function TGreenletProxyImpl._Release: Integer;
begin
  Result := inherited _Release
end;

{ TGreenletImpl }

constructor TGreenletImpl.Create(const Routine: TSymmetricRoutine);
begin
  inherited Create;
  FRoutine := Routine;
end;

constructor TGreenletImpl.Create(const Routine: TSymmetricArgsRoutine;
  const Args: array of const);
var
  I: Integer;
begin
  inherited Create;
  FArgsSz := Min(Length(Args), MAX_ARG_SZ);
  for I := 0 to FArgsSz-1 do begin
    FArgs[I] := Args[I];
    if (Args[I].VType = vtObject) then begin
      if TGarbageCollector.ExistsInGlobal(Args[I].VObject) then
        FSmartArgs[I] := Greenlets.GC(Args[I].VObject);
      if ObjArguments.IndexOf(Args[I].VObject) = -1 then
        ObjArguments.Add(Args[I].VObject);
    end;
  end;
  FArgRoutine := Routine;
end;

constructor TGreenletImpl.Create(const Routine: TSymmetricArgsStatic;
  const Args: array of const);
var
  I: Integer;
begin
  inherited Create;
  FArgsSz := Min(Length(Args), MAX_ARG_SZ);
  for I := 0 to FArgsSz-1 do begin
    FArgs[I] := Args[I];
    if (Args[I].VType = vtObject) then begin
      if TGarbageCollector.ExistsInGlobal(Args[I].VObject) then
        FSmartArgs[I] := Greenlets.GC(Args[I].VObject);
      if ObjArguments.IndexOf(Args[I].VObject) = -1 then
        ObjArguments.Add(Args[I].VObject);
    end;
  end;
  FArgStaticRoutine := Routine;
end;

procedure TGreenletImpl.Execute;
var
  SlicedArgs: array of TVarRec;
  I: Integer;
begin
  SetLength(SlicedArgs, FArgsSz);
  for I := 0 to FArgsSz-1 do
    SlicedArgs[I] := FArgs[I];
  if Assigned(FRoutine) then
    FRoutine
  else if Assigned(FArgRoutine) then
    FArgRoutine(SlicedArgs)
  else if Assigned(FArgStaticRoutine) then
    FArgStaticRoutine(SlicedArgs);
end;

function TGreenletImpl.Switch(const Args: array of const): tTuple;
var
  I: Integer;
begin
  CurrentYieldSz := Length(Args);
  for I := 0 to High(Args) do
    CurrentYield[I] := Args[I];
  CurrentYieldClear := False;
  Result := Self.Switch;
end;

function TGreenletImpl.Yield: tTuple;
begin
  CurrentYieldClear := True;
  CurrentYieldSz := 0;
  if Current <> nil then begin
    Current.Yield;
    Result := GetCurrentYield;
  end;
end;

function TGreenletImpl.Yield(const A: array of const): tTuple;
var
  I: Integer;
begin
  CurrentYieldClear := True;
  CurrentYieldSz := Length(A);
  for I := 0 to High(A) do
    CurrentYield[I] := A[I];
  if Current <> nil then
    Current.Yield;
  Result := GetCurrentYield;
end;

function TGreenletImpl.Switch: tTuple;
begin
  if CurrentYieldClear then
    CurrentYieldSz := 0;
  if GetState in [gsReady, gsExecute] then
    inherited Switch
  else begin
    CurrentYieldSz := 0;
  end;
  Result := GetCurrentYield;
end;

{ TAsymmetricImpl<T> }

constructor TAsymmetricImpl<Y>.Create(const Routine: TAsymmetricRoutine<Y>; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FRoutine := Routine;
end;

constructor TAsymmetricImpl<Y>.Create(
  const Routine: TAsymmetricRoutineStatic<Y>; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FRoutinestatic := Routine;
end;

destructor TAsymmetricImpl<Y>.Destroy;
begin
  //TFinalizer<Y>.Fin(FResult);
  inherited;
end;

procedure TAsymmetricImpl<Y>.Execute;
begin
  if Assigned(FRoutine) then
    FResult := TResult<Y>.Create(FRoutine, Self)
  else if Assigned(FRoutineStatic) then
    FResult := TResult<Y>.Create(FRoutineStatic, Self);
end;

function TAsymmetricImpl<Y>.GetResult(const Block: Boolean): Y;
begin
  if Block then begin
    Join(True);
    case GetState of
      gsTerminated:
        Result := FResult;
      gsException:
        ReraiseException
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end else begin
    case GetState of
      gsTerminated:
        Result := FResult
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end;
end;

{ TAsymmetricImpl<T, Y> }

constructor TAsymmetricImpl<T, Y>.Create(const Routine: TAsymmetricRoutine<T, Y>;
  const Arg: T; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg := TArgument<T>.Create(Arg, Self);
  FRoutine := Routine;
end;

constructor TAsymmetricImpl<T, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T, Y>; const Arg: T; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg := TArgument<T>.Create(Arg, Self);
  FRoutineStatic := Routine;
end;

destructor TAsymmetricImpl<T, Y>.Destroy;
begin
  //TFinalizer<Y>.Fin(FResult);
  inherited;
end;

procedure TAsymmetricImpl<T, Y>.Execute;
begin
  if Assigned(FRoutine) then
    FResult := TResult<Y>.Create(FRoutine(FArg), Self)
  else if Assigned(FRoutineStatic) then
    FResult := TResult<Y>.Create(FRoutineStatic(FArg), Self);
end;

function TAsymmetricImpl<T, Y>.GetResult(const Block: Boolean): Y;
begin
  if Block then begin
    Join(True);
    case GetState of
      gsTerminated:
        Result := FResult;
      gsException:
        ReraiseException
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end else begin
    case GetState of
      gsTerminated:
        Result := FResult
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end;
end;

{ TAsymmetricImpl<T1, T2, Y> }

constructor TAsymmetricImpl<T1, T2, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, Y>; const Arg1: T1; const Arg2: T2; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FRoutine := Routine;
end;

constructor TAsymmetricImpl<T1, T2, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const Arg1: T1;
  const Arg2: T2; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FRoutineStatic := Routine;
end;

destructor TAsymmetricImpl<T1, T2, Y>.Destroy;
begin
  //TFinalizer<Y>.Fin(FResult);
  inherited;
end;

procedure TAsymmetricImpl<T1, T2, Y>.Execute;
begin
  if Assigned(FRoutine) then
    FResult := TResult<Y>.Create(FRoutine(FArg1, FArg2), Self)
  else if Assigned(FRoutineStatic) then
    FResult := TResult<Y>.Create(FRoutinestatic(FArg1, FArg2), Self);
end;

function TAsymmetricImpl<T1, T2, Y>.GetResult(const Block: Boolean): Y;
begin
  if Block then begin
    Join(True);
    case GetState of
      gsTerminated:
        Result := FResult;
      gsException:
        ReraiseException
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end else begin
    case GetState of
      gsTerminated:
        Result := FResult
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end;
end;

{ TSymmetricImpl }

constructor TSymmetricImpl.Create(const Routine: TSymmetricRoutine; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FRoutine := Routine
end;

constructor TSymmetricImpl.Create(const Routine: TSymmetricRoutineStatic; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FRoutineStatic := Routine
end;

procedure TSymmetricImpl.Execute;
begin
  if Assigned(FRoutine) then
    FRoutine()
  else if Assigned(FRoutineStatic) then
    FRoutineStatic();
end;

{$IFDEF DEBUG}

procedure DebugString(const S: string);
var
  P: PChar;
  Str: string;
begin
  Str := S;
  P := PChar(Str);
  OutputDebugString(P);
end;

procedure DebugDump(const Prefix: string; const Ptr: Pointer; Size: LongWord; const Sep: Char);
var
  Data: PByteArray;
  S: TStrings;
  B: Byte;
  I: LongWord;
  AStr: AnsiString;
  P: PChar;
  Str: string;
begin
  if (Size = 0) or (Ptr= nil) then
    Exit;
  Data := PByteArray(Ptr);
  S := TStringList.Create;
  try
    S.Delimiter := Sep;
    for I := 0 to Size-1 do begin
      B := Data[I];
      S.Add(IntToStr(B));
    end;
    SetLength(AStr, Size);
    Move(Ptr^, Pointer(AStr)^, Size);
    Str := Prefix + S.DelimitedText + '   (' + string(AStr) + ')';
    P := pchar(Str);
    OutputDebugString(P);
  finally
    S.Free
  end;
end;

{$ENDIF}

{ TJoiner }

procedure TJoiner.Append(G: TRawGreenletImpl);
begin
  FLock.Acquire;
  try
    FList.Add(G);
  finally
    FLock.Release;
    FOnUpdate.SetEvent;
  end;
end;

procedure TJoiner.Clear;
var
  G: TRawGreenletImpl;
  I: Integer;
begin
  FLock.Acquire;
  try
    for I := 0 to FList.Count-1 do begin
      G := TRawGreenletImpl(FList[I]);
      G.Hub := nil;
    end;
    FList.Clear;
  finally
    FLock.Release;
  end;
  FOnUpdate.SetEvent;
end;

constructor TJoiner.Create;
begin
  FLock := SyncObjs.TCriticalSection.Create;
  FList := TList.Create;
  FOnUpdate := TGevent.Create;
  TGeventPImpl(FOnUpdate)._AddRef;
end;

destructor TJoiner.Destroy;
begin
  if HubInfrasctuctureEnable then
    Clear;
  FList.Free;
  TGeventPImpl(FOnUpdate)._Release;
  FLock.Free;
  inherited;
end;

function TJoiner.Find(G: TRawGreenletImpl; out Index: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FList.Count-1 do
    if FList[I] = G then begin
      Index := I;
      Exit(True);
    end;
end;

function TJoiner.GetAll: tArrayOfGreenlet;
var
  I: Integer;
begin
  FLock.Acquire;
  SetLength(Result, FList.Count);
  for I := 0 to FList.Count-1 do
    Result[I] := TRawGreenletImpl(FList[I]);
  FLock.Release;
end;

function TJoiner.GetCount: Integer;
begin
  FLock.Acquire;
  Result := FList.Count;
  FLock.Release;
end;

function TJoiner.GetItem(Index: Integer): TRawGreenletImpl;
begin
  FLock.Acquire;
  if Index < FList.Count then
    Result := TRawGreenletImpl(FList[Index])
  else
    Result := nil;
  FLock.Release;
end;

function TJoiner.GetStateEvents: tArrayOfGevent;
var
  I: Integer;
begin
  FLock.Acquire;
  SetLength(Result, FList.Count+1);
  Result[0] := FOnUpdate;
  for I := 0 to FList.Count-1 do
    Result[I+1] := TRawGreenletImpl(FList[I]).GetOnStateChanged;
  FLock.Release;
end;

function TJoiner.HasExecutions: Boolean;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    Result := False;
    for I := 0 to FList.Count-1 do
      if Item[I].GetState = gsExecute then
        Exit(True)
  finally
    FLock.Release
  end;
end;

procedure TJoiner.KillAll;
var
  G: TRawGreenletImpl;
begin
  FLock.Acquire;
  try
    while FList.Count > 0 do begin
      G := TRawGreenletImpl(FList[0]);
      FList.Delete(0);
      G.Kill;
      G.Hub := nil;
    end;
  finally
    FLock.Release
  end;
end;

procedure TJoiner.Remove(G: TRawGreenletImpl);
var
  Index: Integer;
begin
  FLock.Acquire;
  try
    if Find(G, Index) then begin
      FList.Delete(Index);
      FOnUpdate.SetEvent;
    end;
  finally
    FLock.Release;
  end;
end;

{ TAsymmetricImpl<T1, T2, T3, Y> }

constructor TAsymmetricImpl<T1, T2, T3, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FArg3 := TArgument<T3>.Create(Arg3, Self);
  FRoutine := Routine;
end;

constructor TAsymmetricImpl<T1, T2, T3, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FArg3 := TArgument<T3>.Create(Arg3, Self);
  FRoutineStatic := Routine;
end;

destructor TAsymmetricImpl<T1, T2, T3, Y>.Destroy;
begin
  //TFinalizer<Y>.Fin(FResult);
  inherited;
end;

procedure TAsymmetricImpl<T1, T2, T3, Y>.Execute;
begin
  if Assigned(FRoutine) then
    FResult := TResult<Y>.Create(FRoutine(FArg1, FArg2, FArg3), Self)
  else if Assigned(FRoutineStatic) then
    FResult := TResult<Y>.Create(FRoutinestatic(FArg1, FArg2, FArg3), Self);
end;

function TAsymmetricImpl<T1, T2, T3, Y>.GetResult(const Block: Boolean): Y;
begin
  if Block then begin
    Join(True);
    case GetState of
      gsTerminated:
        Result := FResult;
      gsException:
        ReraiseException
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end else begin
    case GetState of
      gsTerminated:
        Result := FResult
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end;
end;

{ TAsymmetricImpl<T1, T2, T3, T4, Y> }

constructor TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FArg3 := TArgument<T3>.Create(Arg3, Self);
  FArg4 := TArgument<T4>.Create(Arg4, Self);
  FRoutine := Routine;
end;

constructor TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const Arg1: T1;
  const Arg2: T2; const Arg3: T3; const Arg4: T4; Hub: THub);
begin
  inherited Create;
  if Assigned(Hub) then
    Self.Hub := Hub;
  FArg1 := TArgument<T1>.Create(Arg1, Self);
  FArg2 := TArgument<T2>.Create(Arg2, Self);
  FArg3 := TArgument<T3>.Create(Arg3, Self);
  FArg4 := TArgument<T4>.Create(Arg4, Self);
  FRoutineStatic := Routine;
end;

destructor TAsymmetricImpl<T1, T2, T3, T4, Y>.Destroy;
begin
  //TFinalizer<Y>.Fin(FResult);
  inherited;
end;

procedure TAsymmetricImpl<T1, T2, T3, T4, Y>.Execute;
begin
  if Assigned(FRoutine) then
    FResult := TResult<Y>.Create(FRoutine(FArg1, FArg2, FArg3, FArg4), Self)
  else if Assigned(FRoutineStatic) then
    FResult := TResult<Y>.Create(FRoutinestatic(FArg1, FArg2, FArg3, FArg4), Self);
end;

function TAsymmetricImpl<T1, T2, T3, T4, Y>.GetResult(const Block: Boolean): Y;
begin
  if Block then begin
    Join(True);
    case GetState of
      gsTerminated:
        Result := FResult;
      gsException:
        ReraiseException
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end else begin
    case GetState of
      gsTerminated:
        Result := FResult
      else
        raise EResultIsEmpty.Create('Result is Empty. Check state of greenlet');
    end;
  end;
end;

{ TGeneratorImpl<T> }

constructor TGeneratorImpl<T>.Create(const Routine: TSymmetricRoutine);
var
  Inst: TGenGreenletImpl;
begin
  CheckMetaInfo;
  Inst := TGenGreenletImpl.Create(Routine);
  Inst.FGen := Self;
  FGreenlet := Inst;
end;

constructor TGeneratorImpl<T>.Create(const Routine: TSymmetricArgsRoutine;
  const Args: array of const);
var
  Inst: TGenGreenletImpl;
begin
  CheckMetaInfo;
  Inst := TGenGreenletImpl.Create(Routine, Args);
  Inst.FGen := Self;
  FGreenlet := Inst;
end;

procedure TGeneratorImpl<T>.CheckMetaInfo;
var
  ti: PTypeInfo;
  ObjValuePtr: PObject;
begin
  ti := TypeInfo(T);
  if (ti.Kind = tkClass) then begin
    FIsObject := True;
  end
end;

constructor TGeneratorImpl<T>.Create(const Routine: TSymmetricArgsStatic;
  const Args: array of const);
var
  Inst: TGenGreenletImpl;
begin
  CheckMetaInfo;
  Inst := TGenGreenletImpl.Create(Routine, Args);
  Inst.FGen := Self;
  FGreenlet := Inst;
end;

destructor TGeneratorImpl<T>.Destroy;
begin
  FGreenlet.Kill;
  inherited;
end;

procedure TGeneratorImpl<T>.GarbageCollect(const Old, New: T);
var
  ObjValuePtr: PObject;
  vOld, vNew: TObject;
begin
  if FIsObject then begin
    ObjValuePtr := @Old;
    vOld := ObjValuePtr^;
    ObjValuePtr := @New;
    vNew := ObjValuePtr^;
    FSmartPtr := vNew
  end;
end;

function TGeneratorImpl<T>.GetEnumerator: GInterfaces.TEnumerator<T>;
var
  Inst: TGenEnumerator;
begin
  Inst := TGenEnumerator.Create;
  Inst.FGen := Self;
  Result := Inst;
end;

function TGeneratorImpl<T>.MoveNext: Boolean;
var
  Inst: TGreenletImpl;
begin
  // Делаем 1 цикл
  FGreenlet.Switch;
  // И смотрим что получилось
  while True do begin
    case FGreenlet.GetState of
      gsExecute: begin
        if FYieldExists then
          Exit(True)
        else
          Exit(False);
      end;
      gsSuspended: begin
        FGreenlet.GetOnStateChanged.WaitFor
      end
      else
        Exit(False)
    end;
  end;
end;

procedure TGeneratorImpl<T>.Reset;
begin
  FYieldExists := False;
  FGreenlet.Kill;
end;

procedure TGeneratorImpl<T>.Setup(const Args: array of const);
var
  G: TGreenletImpl;
begin
  G := TGreenletImpl(FGreenlet.GetInstance);
  FGreenlet.Switch(Args);
end;

class function TGeneratorImpl<T>.Yield(const Value: T): tTuple;
var
  Gen: TGeneratorImpl<T>;
  Greenlet: TGenGreenletImpl;
  Current: TRawGreenletImpl;
begin
  Current := TRawGreenletImpl.GetCurrent;
  if Current = nil then
    Exit;
  if Current.ClassType = TGenGreenletImpl then begin
    Greenlet := TGenGreenletImpl(Current);
    Gen := TGeneratorImpl<T>(Greenlet.FGen)
  end
  else
    Gen := nil;
  if Assigned(Gen) then begin
    // Кладем наши данные
    Gen.FYieldExists := True;
    Gen.GarbageCollect(Gen.FCurrent, Value);
    Gen.FCurrent := Value;
    Result := Greenlet.Yield;
    // эта строка выполнится уже после след вызова Switch
    Gen.FYieldExists := False;
  end
  else begin
    Current.Yield;
  end;
end;

{ TGeneratorImpl<T>.TEnumerator }

function TGeneratorImpl<T>.TGenEnumerator.GetCurrent: T;
begin
  Result := FGen.FCurrent
end;

function TGeneratorImpl<T>.TGenEnumerator.MoveNext: Boolean;
begin
  Result := FGen.MoveNext
end;

procedure TGeneratorImpl<T>.TGenEnumerator.Reset;
begin
  FGen.Reset
end;

{ TUniValue }

procedure TUniValue.Assign(Source: TPersistent);
begin
  if InheritsFrom(Source.ClassType) then begin
    FStrValue := TUniValue(Source).FStrValue;
    FIntValue := TUniValue(Source).FIntValue;
    FFloatValue := TUniValue(Source).FFloatValue;
    FDoubleValue := TUniValue(Source).FDoubleValue;
    FInt64Value := TUniValue(Source).FInt64Value;
  end;
end;

{ TGreenEnvironmentImpl }

procedure TGreenEnvironmentImpl.Clear;
begin
  while FNames.Count > 0 do
    UnsetValue(FNames[0]);
end;

function TGreenEnvironmentImpl.Copy: TGreenEnvironmentImpl;
var
  I: Integer;
  CpyValue, Value: TPersistent;
begin
  Result := TGreenEnvironmentImpl.Create;
  for I := 0 to FNames.Count-1 do begin
    Value := GetValue(FNames[I]);
    CpyValue := TPersistentClass(Value.ClassType).Create;
    CpyValue.Assign(Value);
    Result.SetValue(FNames[I], CpyValue);
  end;
end;

constructor TGreenEnvironmentImpl.Create;
begin
  FStorage := TLocalStorage.Create;
  FNames := TStringList.Create;
end;

destructor TGreenEnvironmentImpl.Destroy;
var
  AllNames: array of string;
  I: Integer;
begin
  SetLength(AllNames, FNames.Count);
  for I := 0 to FNames.Count-1 do
    AllNames[I] := FNames[I];
  for I := 0 to High(AllNames) do
    UnsetValue(AllNames[I]);
  FStorage.Free;
  FNames.Free;
  inherited;
end;

function TGreenEnvironmentImpl.GetDoubleValue(const Name: string): Double;
begin
  Result := GetUniValue(Name).DoubleValue
end;

function TGreenEnvironmentImpl.GetFloatValue(const Name: string): Single;
begin
  Result := GetUniValue(Name).FloatValue
end;

function TGreenEnvironmentImpl.GetInt64Value(const Name: string): Int64;
begin
  Result := GetUniValue(Name).Int64Value
end;

function TGreenEnvironmentImpl.GetIntValue(const Name: string): Integer;
begin
  Result := GetUniValue(Name).IntValue
end;

function TGreenEnvironmentImpl.GetStrValue(const Name: string): string;
begin
  Result := GetUniValue(Name).StrValue
end;

function TGreenEnvironmentImpl.GetUniValue(const Name: string): TUniValue;
var
  P: TPersistent;
begin
  P := GetValue(Name);
  if Assigned(P) then begin
    if not P.InheritsFrom(TUniValue) then begin
      UnsetValue(Name);
      Result := TUniValue(P);
    end
    else
      Result := TUniValue(P);
  end
  else begin
    Result := TUniValue.Create;
    SetValue(Name, Result);
  end;
end;

function TGreenEnvironmentImpl.GetValue(const Name: string): TPersistent;
begin
  Result := TPersistent(FStorage.GetValue(Name));
end;

procedure TGreenEnvironmentImpl.SetDoubleValue(const Name: string;
  const Value: Double);
begin
  GetUniValue(Name).DoubleValue := Value
end;

procedure TGreenEnvironmentImpl.SetFloatValue(const Name: string;
  Value: Single);
begin
  GetUniValue(Name).FloatValue := Value
end;

procedure TGreenEnvironmentImpl.SetInt64Value(const Name: string;
  const Value: Int64);
begin
  GetUniValue(Name).Int64Value := Value
end;

procedure TGreenEnvironmentImpl.SetIntValue(const Name: string; Value: Integer);
begin
  GetUniValue(Name).IntValue := Value
end;

procedure TGreenEnvironmentImpl.SetStrValue(const Name: string; Value: string);
begin
  GetUniValue(Name).StrValue := Value;
end;

procedure TGreenEnvironmentImpl.SetValue(const Name: string;
  Value: TPersistent);
var
  OldValue: TPersistent;
begin
  OldValue := TPersistent(FStorage.GetValue(Name));
  if Assigned(OldValue) then
    OldValue.Free
  else
    FNames.Add(Name);
  FStorage.SetValue(Name, Value);
end;

procedure TGreenEnvironmentImpl.UnsetValue(const Name: string);
var
  Value: TObject;
begin
  Value := FStorage.GetValue(Name);
  if Assigned(Value) then begin
    FNames.Delete(FNames.IndexOf(Name));
    FStorage.UnsetValue(Value);
    Value.Free;
  end
end;


{ TKillToken }

constructor TKillToken.Create(Killing: TRawGreenletImpl);
begin
  FKilling := Killing;
  FKilling._AddRef;
end;

destructor TKillToken.Destroy;
begin
  if Assigned(FKilling) then
    DoIt;
  inherited;
end;

procedure TKillToken.DoIt;
begin
  FKilling.FForcingKill := True;
  if FKilling.GetState in [gsExecute, gsSuspended] then begin
    FKilling.Kill;
  end;
  FKilling._Release;
  FKilling := nil;
  Self._Release;
end;

{ TTriggers }

function TTriggers.Find(const Cb: TThreadMethod; out Index: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FCollection) do
    if @FCollection[I] = @Cb then
      Exit(True);
  Result := False;
end;

procedure TTriggers.OffCb(const Cb: TThreadMethod);
var
  Index: Integer;
begin
  if Find(Cb, Index) then begin
    if Index = High(FCollection) then
      SetLength(FCollection, Length(FCollection)-1)
    else begin
      Move(FCollection[Index+1], FCollection[Index], Length(FCollection)-Index-1);
      SetLength(FCollection, Length(FCollection)-1);
    end
  end;
end;

procedure TTriggers.OnCb(const Cb: TThreadMethod);
var
  Index: Integer;
begin
  if not Find(Cb, Index) then begin
    SetLength(FCollection, Length(FCollection) + 1);
    FCollection[High(FCollection)] := Cb
  end;
end;

procedure TTriggers.RaiseAll;
var
  I: Integer;
begin
  for I := 0 to High(FCollection) do
    FCollection[I]();
end;

{ IGreenGroup<KEY> }

procedure TGreenGroupImpl<KEY>.Append(const Key: KEY; G: IRawGreenlet);
var
  Ptr: Pointer;
begin
  FMap.Add(Key, G);
  Ptr := Pointer(G);
  FList.Add(Ptr);
  G._AddRef;
  FOnUpdated.SetEvent;
end;

procedure TGreenGroupImpl<KEY>.Clear;
var
  I: Integer;
  G: IRawGreenlet;
begin
  FMap.Clear;
  try
    for I := 0 to FList.Count-1 do begin
      G := IRawGreenlet(FList[I]);
      G._Release;
    end;
  finally
    FList.Clear;
  end;
  FOnUpdated.SetEvent;
end;

function TGreenGroupImpl<KEY>.Copy: IGreenGroup<KEY>;
var
  Cpy: TGreenGroupImpl<KEY>;
  G: IRawGreenlet;
  Ptr: Pointer;
  I: Integer;
  {$IFDEF DCC}
  KV: TPair<KEY, IRawGreenlet>;
  {$ELSE}
  Index: Integer;
  Key: KEY;
  {$ENDIF}
begin
  Cpy := TGreenGroupImpl<KEY>.Create;
  for I := 0 to Self.FList.Count-1 do begin
    G := IRawGreenlet(FList[I]);
    Ptr := Pointer(G);
    G._AddRef;
    Cpy.FList.Add(Ptr);
  end;
  {$IFDEF DCC}
  for KV in Self.FMap do
    Cpy.FMap.Add(KV.Key, KV.Value);
  {$ELSE}
  for Index := 0 to Self.FMap.Count-1 do begin
    Key := Self.FMap.Keys[Index];
    Cpy.FMap.Add(Key, Self.FMap[Key]);
  end;
  {$ENDIF}
  Result := Cpy;
end;

constructor TGreenGroupImpl<KEY>.Create;
begin
  inherited Create;
  {$IFDEF DCC}
  FMap := TDictionary<KEY, IRawGreenlet>.Create;
  {$ELSE}
  FMap := TFPGMap<KEY, IRawGreenlet>.Create;
  {$ENDIF}
  FOnUpdated := TGevent.Create;
  TGeventPImpl(FOnUpdated)._AddRef;
  FList := TList.Create;
end;

destructor TGreenGroupImpl<KEY>.Destroy;
begin
  Clear;
  FMap.Free;
  TGeventPImpl(FOnUpdated)._Release;
  FList.Free;
  inherited;
end;

function TGreenGroupImpl<KEY>.Count: Integer;
begin
  Result := FList.Count
end;

function TGreenGroupImpl<KEY>.GetValue(const Key: KEY): IRawGreenlet;
begin
  if IsExists(Key) then
    Result := FMap[Key]
  else
    Result := nil;
end;

function TGreenGroupImpl<KEY>.IsEmpty: Boolean;
begin
  Result := FMap.Count = 0
end;

function TGreenGroupImpl<KEY>.IsExists(const Key: KEY): Boolean;
{$IFDEF FPC}
var
  Index: Integer;
{$ENDIF}
begin
  {$IFDEF DCC}
  Result := FMap.ContainsKey(Key)
  {$ELSE}
  Result := FMap.Find(Key, Index);
  {$ENDIF}
end;

function TGreenGroupImpl<KEY>.Join(Timeout: LongWord; const RaiseError: Boolean): Boolean;
var
  Workers: array of IRawGreenlet;
  I: Integer;
begin
  SetLength(Workers, FList.Count);
  for I := 0 to FList.Count-1 do
    Workers[I] := IRawGreenlet(FList[I]);
  Result := Greenlets.Join(Workers, Timeout, RaiseError)
end;

procedure TGreenGroupImpl<KEY>.KillAll;
var
  I: Integer;
  G: IRawGreenlet;
begin
  try
    for I := 0 to FList.Count-1 do begin
      G := IRawGreenlet(FList[I]);
      G.Kill;
    end;
  finally
    FList.Clear;
  end;
  FOnUpdated.SetEvent;
end;

procedure TGreenGroupImpl<KEY>.Remove(const Key: KEY);
var
  G: IRawGreenlet;
  Ptr: Pointer;
  Index: Integer;
begin
  G := FMap[Key];
  Ptr := Pointer(G);
  Index := FList.IndexOf(Ptr);
  if Index >= 0 then begin
    FList.Delete(Index);
    G._Release;
  end;
  FMap.Remove(Key);
  FOnUpdated.SetEvent;
end;

procedure TGreenGroupImpl<KEY>.SetValue(const Key: KEY; G: IRawGreenlet);
begin
  if IsExists(Key) then
    Remove(Key);
  if Assigned(G) then
    Append(Key, G);
end;

{ TArgument<T> }

constructor TArgument<T>.Create(const Value: T; Owner: TRawGreenletImpl);
type
  TDynArr = TArray<T>;
  PDynArr = ^TDynArr;
  PInterface = ^IInterface;
var
  ti: PTypeInfo;
  td: PTypeData;
  ValuePtr: PValue;
  B: TBoundArray;
  DynLen, DynDim: NativeInt;
  PArrValueIn, PArrValueOut: PDynArr;
  // rtti
  rtype: TRTTIType;
  fields: TArray<TRttiField>;
  I: Integer;
  Intf: IInterface;
  Chan: IAbstractChannel;
  PIntf: PInterface;
  RW: IChannel<T>;
  R: IReadOnly<T>;
  W: IWriteOnly<T>;

begin
  FIsObject := False;
  FIsDynArr := False;
  ti := TypeInfo(T);

  if ti.Kind = tkRecord then begin
    rtype := TRTTIContext.Create.GetType(TypeInfo(T));
    fields := rtype.GetFields;
    for I := 0 to High(fields) do begin
      if fields[I].FieldType.Handle.Kind = tkInterface then begin
        Intf := fields[I].GetValue(@Value).AsInterface;
        if Assigned(Intf) then begin
          if Intf.QueryInterface(IChannel<T>, RW) = 0 then
            FChanBasket := TChannelRefBasket.Create(RW, 2, 2)
          else if Intf.QueryInterface(IReadOnly<T>, R) = 0 then
            FChanBasket := TChannelRefBasket.Create(R, 2, 0)
          else if Intf.QueryInterface(IWriteOnly<T>, W) = 0 then
            FChanBasket := TChannelRefBasket.Create(W, 0, 2)
        end;
      end;
    end;
  end
  else if ti.Kind = tkInterface then begin
    PIntf := PInterface(@Value);
    Intf := PIntf^;
    if Assigned(Intf) then begin
      if Intf.QueryInterface(IChannel<T>, RW) = 0 then
        FChanBasket := TChannelRefBasket.Create(RW, 2, 2)
      else if Intf.QueryInterface(IReadOnly<T>, R) = 0 then
        FChanBasket := TChannelRefBasket.Create(R, 2, 0)
      else if Intf.QueryInterface(IWriteOnly<T>, W) = 0 then
        FChanBasket := TChannelRefBasket.Create(W, 0, 2)
    end;
  end;

  if (ti.Kind = tkClass) then begin
    ValuePtr := @Value;
    FObject := PObject(ValuePtr)^;
    FIsObject := True;
    if Assigned(FObject) and FObject.InheritsFrom(TPersistent) then begin
      if FObject.InheritsFrom(TComponent) then begin
        FObject := TComponentClass(FObject.ClassType).Create(nil);
      end
      else begin
        FObject := TPersistentClass(FObject.ClassType).Create;
      end;
      TPersistent(FObject).Assign(TPersistent(PObject(ValuePtr)^));
      Self.FSmartObj := TGCPointerImpl<TObject>.Create(FObject);
    end
    else begin
      if TGarbageCollector.ExistsInGlobal(FObject) then begin
        FSmartObj := GC(FObject);
      end
      else begin
        // nothing
      end;
    end;
    ValuePtr := PValue(@FObject);
    FValue := ValuePtr^;
    if Assigned(Owner) then
      if Owner.ObjArguments.IndexOf(FObject) = -1 then begin
        Owner.ObjArguments.Add(FObject);
      end;
  end
  else if ti.Kind = tkDynArray then begin
    FIsDynArr := True;
    td := GetTypeData(ti);
    if DynArrayDim(ti) = 1 then begin
      if Assigned(td.elType) and (td.elType^.Kind in [tkString, tkUString, tkLString,
          tkWString, tkInterface]) then
      begin
        FValue := Value;
      end
      else begin
        PArrValueIn := PDynArr(@Value);
        PArrValueOut := PDynArr(@FValue);
        DynLen := Length(PArrValueIn^);
        SetLength(PArrValueOut^, DynLen);
        Move(PArrValueIn^[0], PArrValueOut^[0], DynLen * td.elSize)
      end;
    end
    else
      FValue := Value
  end
  else
    FValue := Value;
end;

class operator TArgument<T>.Implicit(const A: TArgument<T>): T;
begin
  Result := A.FValue
end;

{ TResult<T> }

constructor TResult<T>.Create(const Value: T; Owner: TRawGreenletImpl);
var
  ti: PTypeInfo;
  ValuePtr: PValue;
begin
  FIsObject := False;
  FValue := Value;
  ti := TypeInfo(T);
  if (ti.Kind = tkClass) then begin
    ValuePtr := @Value;
    FObject := PObject(ValuePtr)^;
    FIsObject := True;
    if (Owner.ObjArguments.IndexOf(FObject) <> -1) and TGarbageCollector.ExistsInGlobal(FObject) then
      FSmartObj := GC(FObject);
  end;
end;

class operator TResult<T>.Implicit(const A: TResult<T>): T;
begin
  Result := A.FValue
end;

{ TChannelRefBasket }

constructor TChannelRefBasket.Create(Channel: IAbstractChannel; ReaderFactor, WriterFactor: Integer);
begin
  FChannel := Channel;
  FReaderFactor := ReaderFactor;
  FWriterFactor := WriterFactor;
  FChannel.ReleaseRefs(ReaderFactor, WriterFactor);
end;

destructor TChannelRefBasket.Destroy;
begin
  if Assigned(FChannel) then
    FChannel.AccumRefs(FReaderFactor, FWriterFactor);
  inherited;
end;

{ TGCondVariableImpl }

procedure TGCondVariableImpl.Broadcast;
var
  D: TCoDescr;
begin
  while Dequeue(D) do begin
    D.Cond^ := True;
    D.GEv.SetEvent(FSync)
  end;
end;

constructor TGCondVariableImpl.Create(aExternalMutex: TCriticalSection);
begin
  FQueue := TItems.Create;
  FExternalMutex := Assigned(aExternalMutex);
  if FExternalMutex then
    FMutex := aExternalMutex
  else
    FMutex := TCriticalSection.Create;
  FSync := True;
end;

function TGCondVariableImpl.Dequeue(out D: TCoDescr): Boolean;
begin
  FMutex.Acquire;
  try
    Result := FQueue.Count > 0;
    if Result then begin
      D := FQueue[0];
      FQueue.Delete(0);
    end;
  finally
    FMutex.Release;
  end;
end;

destructor TGCondVariableImpl.Destroy;
var
  I: Integer;
begin
  for I := 0 to FQueue.Count-1 do
    if Assigned(FQueue[I].IsDestroyed) then
      FQueue[I].IsDestroyed^ := True;
  FQueue.Free;
  if not FExternalMutex then
    FMutex.Free;
  inherited;
end;

procedure TGCondVariableImpl.Enqueue(const D: TCoDescr;
  aUnlocking: TCriticalSection; aSpinUnlocking: TPasMPSpinLock);
begin
  FMutex.Acquire;
  try
    FQueue.Add(D);
  finally
    if Assigned(aUnlocking) then
      aUnlocking.Release;
    if Assigned(aSpinUnlocking) then
      aSpinUnlocking.Release;
    FMutex.Release;
  end;
end;

procedure TGCondVariableImpl.ForceDequeue(Ctx: NativeUInt; Thread: TThread);
var
  I: Integer;
begin
  FMutex.Acquire;
  try
    I := 0;
    while I < FQueue.Count do begin
      if (FQueue[I].Ctx = Ctx) and (FQueue[I].Thread = Thread) then
        FQueue.Delete(I)
      else
        Inc(I)
    end;
  finally
    FMutex.Release;
  end;
end;

function TGCondVariableImpl.GetSync: Boolean;
begin
  Result := FSync
end;

procedure TGCondVariableImpl.SetSync(const Value: Boolean);
begin
  FSync := Value
end;

procedure TGCondVariableImpl.Signal;
var
  D: TCoDescr;
begin
  if Dequeue(D) then begin
    D.Cond^ := True;
    D.GEv.SetEvent(FSync);
  end;
end;

procedure TGCondVariableImpl.Wait(aSpinUnlocking: TPasMPSpinLock);
begin
  WaitInternal(nil, aSpinUnlocking)
end;

procedure TGCondVariableImpl.Wait(aUnlocking: TCriticalSection);
begin
  WaitInternal(aUnlocking, nil);
end;

procedure TGCondVariableImpl.WaitInternal(aUnlocking: TCriticalSection;
  aSpinUnlocking: TPasMPSpinLock; Gevent: TGevent);
var
  Cond: Boolean;
  Descr: TCoDescr;
  Destroyed: Boolean;
begin
  Cond := False;
  if Greenlets.GetCurrent <> nil then
    Descr.Ctx := TRawGreenletImpl(Greenlets.GetCurrent).GetUID
  else
    Descr.Ctx := NativeUInt(GetCurrentHub);
  Descr.Thread := TThread.CurrentThread;
  Descr.Cond := @Cond;
  Destroyed := False;
  Descr.IsDestroyed := @Destroyed;
  if Greenlets.GetCurrent = nil then begin
    // Случай если ждет нитка
    if Assigned(Gevent) then
      Descr.GEv := Gevent
    else
      Descr.GEv := TGEvent.Create(False, False);
    Enqueue(Descr, aUnlocking, aSpinUnlocking);
    while not Cond do
      Descr.GEv.WaitFor(INFINITE);
    ForceDequeue(Descr.Ctx, Descr.Thread);
    if not Assigned(Gevent) then
      Descr.GEv.Free;
  end
  else begin
    // Хитрость - ставим блокировку через переменную выделенную на стеке
    // мы так можем сделать потому что у сопрограммы свой стек
    Descr.Cond := @Cond;
    if Assigned(Gevent) then
      Descr.GEv := Gevent
    else
      Descr.GEv := TGEvent.Create;
    try
      Enqueue(Descr, aUnlocking, aSpinUnlocking);
      while not Cond do
        Descr.GEv.WaitFor(INFINITE);
    finally
      if not Destroyed then
        ForceDequeue(Descr.Ctx, Descr.Thread);
      if not Assigned(Gevent) then
        Descr.GEv.Free;
    end;
  end;
end;

{ TGSemaphoreImpl }

procedure TGSemaphoreImpl.Acquire;
var
  Descr: TDescr;
begin
  Descr := AcquireCtx(GetCurContext);
  while True do begin
    Lock;
    if (FAcqQueue.Count > 0) and (NativeUint(FAcqQueue[0]) = GetCurContext) then begin
      FAcqQueue.Delete(0);
      Break;
    end;
    if (FValue < FLimit) and (FAcqQueue.Count = 0) and (FQueue.Count = 0) then
      Break;
    Enqueue(GetCurContext);
    Unlock;
    if Descr.Notify.WaitFor <> wrSignaled then
      Exit;
  end;
  Inc(FValue);
  Unlock;
end;

function TGSemaphoreImpl.AcquireCtx(const Ctx: NativeUint): TDescr;
begin
  Lock;
  try
    if FHash.ContainsKey(Ctx) then begin
      Result := FHash[Ctx];
      Result.Recursion := Result.Recursion + 1;
    end
    else begin
      Result := TDescr.Create;
      Result.Recursion := 1;
      FHash.Add(Ctx, Result)
    end;
  finally
    Unlock;
  end;
end;

constructor TGSemaphoreImpl.Create(Limit: LongWord);
begin
  if Limit = 0 then
    raise EInvalidLimit.Create('Limit must be greater than 0');
  FLimit := Limit;
  FQueue := TList.Create;
  FAcqQueue := TList.Create;
  FHash := THashTable.Create;
  FLock := TCriticalSection.Create;
end;

function TGSemaphoreImpl.Dequeue(out Ctx: NativeUInt): Boolean;
begin
  Lock;
  try
    Result := FQueue.Count > 0;
    if Result then begin
      Ctx := NativeUInt(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    Unlock;
  end;
end;

destructor TGSemaphoreImpl.Destroy;
begin
  FHash.Free;
  FQueue.Free;
  FAcqQueue.Free;
  FLock.Free;
  inherited;
end;

procedure TGSemaphoreImpl.Enqueue(const Ctx: NativeUInt);
begin
  Lock;
  try
    FQueue.Add(Pointer(Ctx))
  finally
    Unlock;
  end;
end;

function TGSemaphoreImpl.GetCurContext: NativeUInt;
begin
  if Greenlets.GetCurrent = nil then
    Result := NativeUInt(GetCurrentHub)
  else
    Result := TRawGreenletImpl(Greenlets.GetCurrent).GetUID;
end;

function TGSemaphoreImpl.Limit: LongWord;
begin
  Result := FLimit
end;

procedure TGSemaphoreImpl.Lock;
begin
  FLock.Acquire;
end;

procedure TGSemaphoreImpl.Release;
var
  Ctx: NativeUInt;
begin
  Lock;
  try
    if ReleaseCtx(GetCurContext) then begin
      Dec(FValue);
      if (FValue < FLimit) and Dequeue(Ctx) then begin
        FAcqQueue.Add(Pointer(Ctx));
        FHash[Ctx].Notify.SetEvent;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TGSemaphoreImpl.ReleaseCtx(const Ctx: NativeUint): Boolean;
var
  Descr: TDescr;
begin
  Result := False;
  Lock;
  try
    if FHash.ContainsKey(Ctx) then begin
      Descr := FHash[Ctx];
      Descr.Recursion := Descr.Recursion - 1;
      if Descr.Recursion = 0 then begin
        Descr.Free;
        FHash.Remove(Ctx);
        while FQueue.IndexOf(Pointer(Ctx)) <> -1 do
          FQueue.Delete(FQueue.IndexOf(Pointer(Ctx)));
        end;
      Result := True;
    end;
  finally
    Unlock;
  end;
end;

procedure TGSemaphoreImpl.Unlock;
begin
  FLock.Release;
end;

function TGSemaphoreImpl.Value: LongWord;
begin
  Result := FValue
end;

{ TGSemaphoreImpl.TDescr }

constructor TGSemaphoreImpl.TDescr.Create;
begin
  FNotify := TGevent.Create;
end;

destructor TGSemaphoreImpl.TDescr.Destroy;
begin
  FNotify.Free;
  inherited;
end;

{ TGMutexImpl }

procedure TGMutexImpl.Acquire;
begin
  FSem.Acquire
end;

constructor TGMutexImpl.Create;
begin
  FSem := TGSemaphoreImpl.Create(1);
end;

procedure TGMutexImpl.Release;
begin
  FSem.Release
end;

{ TGQueueImpl<T> }

procedure TGQueueImpl<T>.Clear;
var
  I: Integer;
  Val: T;
begin
  FLock.Acquire;
  try
    for I := 0 to FItems.Count-1 do begin
      Val := FItems[I];
      TFinalizer<T>.Fin(Val);
    end;
    FItems.Clear;
  finally
    FLock.Release;
  end;
end;

function TGQueueImpl<T>.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := FItems.Count;
  finally
    FLock.Release
  end;
end;

constructor TGQueueImpl<T>.Create(MaxCount: LongWord);
begin
  FItems := TItems.Create;
  FLock := TCriticalSection.Create;
  FCanDequeue := TGCondVariableImpl.Create(FLock);
  FCanEnqueue := TGCondVariableImpl.Create(FLock);
  FOnEnqueue := TGEvent.Create(True, True);
  TGeventPImpl(FOnEnqueue)._AddRef;
  FOnDequeue := TGEvent.Create(True, False);
  TGeventPImpl(FOnDequeue)._AddRef;
  if MaxCount = 0 then
    FMaxCount := INFINITE
  else
    FMaxCount := MaxCount;
end;

procedure TGQueueImpl<T>.Dequeue(out A: T);
var
  OK: Boolean;
  ti: PTypeInfo;
begin
  FOnDequeue.SetEvent;
  repeat
    FLock.Acquire;
    // Comment: из-за вызова Cond.Wait(FLock)
    // можно получить состояние полупредиката если в A := FItems[0]; FItems.Delete(0);
    // вылетит исключение, но лучшего способа для сохранения
    // целостности состояния не нашел
    OK := FItems.Count > 0;
    if OK then begin
      A := FItems[0];
      FItems.Delete(0);
      RefreshGEvents;
      FLock.Release;
    end
    else begin
      FCanDequeue.Wait(FLock);
    end;
  until OK;
  FCanEnqueue.Signal;
end;

destructor TGQueueImpl<T>.Destroy;
begin
  Clear;
  FItems.Free;
  FLock.Free;
  TGeventPImpl(FOnEnqueue)._Release;
  TGeventPImpl(FOnDequeue)._Release;
  inherited;
end;

procedure TGQueueImpl<T>.Enqueue(A: T);
var
  OK: Boolean;
begin
  // Писать может кто угодно - и сопрограмма и нитка
  repeat
    FLock.Acquire;
    OK := LongWord(FItems.Count) < FMaxCount;
    if OK then begin
      FItems.Add(A);
      RefreshGEvents;
      FLock.Release;
    end
    else begin
      FCanEnqueue.Wait(FLock);
    end;
  until OK;
  FCanDequeue.Signal;
end;

procedure TGQueueImpl<T>.RefreshGEvents;
begin
  FLock.Acquire;
  try
    if FItems.Count > 0 then
      FOnDequeue.SetEvent
    else
      FOnDequeue.ResetEvent;
    if LongWord(FItems.Count) < FMaxCount then
      FOnEnqueue.SetEvent
    else
      FOnEnqueue.ResetEvent
  finally
    FLock.Release;
  end;
end;

{ TFutureImpl<RESULT, ERROR> }

constructor TFutureImpl<RESULT, ERROR>.Create;
begin
  FOnFullFilled := TGevent.Create(True);
  TGeventPImpl(FOnFullFilled)._AddRef;
  FOnRejected := TGevent.Create(True);
  TGeventPImpl(FOnRejected)._AddRef;
  FResult := FDefValue;
end;

destructor TFutureImpl<RESULT, ERROR>.Destroy;
begin
  TGeventPImpl(FOnFullFilled)._Release;
  TGeventPImpl(FOnRejected)._Release;
  inherited;
end;

function TFutureImpl<RESULT, ERROR>.GetErrorCode: ERROR;
begin
  Result := FErrorCode
end;

function TFutureImpl<RESULT, ERROR>.GetErrorStr: string;
begin
  Result := FErrorStr
end;

function TFutureImpl<RESULT, ERROR>.GetResult: RESULT;
begin
  Result := FResult
end;

function TFutureImpl<RESULT, ERROR>.OnRejected: TGevent;
begin
  Result := FOnRejected;
end;

function TFutureImpl<RESULT, ERROR>.OnFullFilled: TGevent;
begin
  Result := FOnFullFilled
end;

{ TPromiseImpl<T> }

constructor TPromiseImpl<RESULT, ERROR>.Create(Future: TFutureImpl<RESULT, ERROR>);
begin
  FFuture := Future;
  FFuture._AddRef;
  FActive := True;
end;

destructor TPromiseImpl<RESULT, ERROR>.Destroy;
begin
  FFuture._Release;
  inherited;
end;

procedure TPromiseImpl<RESULT, ERROR>.SetErrorCode(Value: ERROR; const ErrorStr: string);
begin
  if not FActive then
    Exit;
  FActive := False;
  FFuture.FErrorCode := Value;
  FFuture.FOnRejected.SetEvent;
  FFuture.FErrorStr := ErrorStr;
end;

procedure TPromiseImpl<RESULT, ERROR>.SetResult(const A: RESULT);
begin
  if not FActive then
    Exit;
  FActive := False;
  FFuture.FResult := A;
  FFuture.FOnFullFilled.SetEvent;
end;

{ TCollectionImpl<T> }

procedure TCollectionImpl<T>.Append(const A: T;
  const IgnoreDuplicates: Boolean);
var
  Succ: Boolean;
begin
  if IgnoreDuplicates then
    Succ := not FList.Contains(A)
  else
    Succ := True;
  if Succ then
    FList.Add(A);
end;

procedure TCollectionImpl<T>.Append(const Other: ICollection<T>;
  const IgnoreDuplicates: Boolean);
var
  I: T;
begin
  for I in Other do
    Self.Append(I, IgnoreDuplicates)
end;

procedure TCollectionImpl<T>.Clear;
begin
  FList.Clear;
end;

function TCollectionImpl<T>.Copy: ICollection<T>;
begin
  Result := TCollectionImpl<T>.Create;
  Result.Append(Self, True);
end;

function TCollectionImpl<T>.Count: Integer;
begin
  Result := FList.Count
end;

constructor TCollectionImpl<T>.Create;
begin
  FList := TList<T>.Create
end;

destructor TCollectionImpl<T>.Destroy;
begin
  FList.Free;
  inherited;
end;

function TCollectionImpl<T>.Get(Index: Integer): T;
begin
  Result := FList[Index]
end;

function TCollectionImpl<T>.GetEnumerator: GInterfaces.TEnumerator<T>;
begin
  Result := TEnumerator<T>.Create(Self)
end;

procedure TCollectionImpl<T>.Remove(const A: T);
begin
  if FList.Contains(A) then
    FList.Remove(A);
end;

{ TCollectionImpl<T>.TEnumerator<T> }

constructor TCollectionImpl<T>.TEnumerator<Y>.Create(
  Collection: TCollectionImpl<Y>);
begin
  FCollection := Collection;
  FCurPos := -1;
end;

function TCollectionImpl<T>.TEnumerator<Y>.GetCurrent: Y;
begin
  Result := FCollection.FList[FCurPos];
end;

function TCollectionImpl<T>.TEnumerator<Y>.MoveNext: Boolean;
begin
  Result := (FCurPos + 1) < FCollection.FList.Count;
  if Result then
    Inc(FCurPos)
end;

procedure TCollectionImpl<T>.TEnumerator<Y>.Reset;
begin
  FCurPos := -1;
end;

{ TCaseImpl }

destructor TCaseImpl.Destroy;
begin
  if Assigned(FOnSuccess) then
    TGeventPImpl(FOnSuccess)._Release;
  if Assigned(FOnError) then
    TGeventPImpl(FOnError)._Release;
  inherited;
end;

function TCaseImpl.GetErrorHolder: IErrorHolder<TPendingError>;
begin
  Result := FErrorHolder
end;

function TCaseImpl.GetOnError: TGevent;
begin
  Result := FOnError
end;

function TCaseImpl.GetOnSuccess: TGevent;
begin
  Result := FOnSuccess
end;

function TCaseImpl.GetOperation: TIOOperation;
begin
  Result := FIOOperation;
end;

function TCaseImpl.GetWriteValueExists: Boolean;
begin
  Result := FWriteValueExists
end;

procedure TCaseImpl.SetErrorHolder(Value: IErrorHolder<TPendingError>);
begin
  FErrorHolder := Value
end;

procedure TCaseImpl.SetOnError(Value: TGevent);
begin
  if Value <> FOnError then begin
    if Assigned(FOnError) then
      TGeventPImpl(FOnError)._Release;
    FOnError := Value;
    if Assigned(FOnError) then
      TGeventPImpl(FOnError)._AddRef;
  end;
end;

procedure TCaseImpl.SetOnSuccess(Value: TGevent);
begin
  if Value <> FOnSuccess then begin
    if Assigned(FOnSuccess) then
      TGeventPImpl(FOnSuccess)._Release;
    FOnSuccess := Value;
    if Assigned(FOnSuccess) then
      TGeventPImpl(FOnSuccess)._AddRef;
  end;
end;

procedure TCaseImpl.SetOperation(const Value: TIOOperation);
begin
  if Value = ioNotSet then
    raise EArgumentException.Create('set io operation');
  FIOOperation := Value
end;

procedure TCaseImpl.SetWriteValueExists(const Value: Boolean);
begin
  FWriteValueExists := Value
end;

end.
