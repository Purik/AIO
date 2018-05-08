unit GInterfaces;

interface
uses SysUtils, GarbageCollector, Classes, Gevent, SyncObjs, PasMP;
type
  {$IFDEF DCC}
  TSymmetricRoutine = reference to procedure;
  TSymmetricArgsRoutine = reference to procedure(const Args: array of const);
  TSymmetricRoutine<T> = reference to procedure(const A: T);
  TSymmetricRoutine<T1, T2> = reference to procedure(const A1: T1; const A2: T2);
  TSymmetricRoutine<T1, T2, T3> = reference to procedure(const A1: T1; const A2: T2; const A3: T3);
  TSymmetricRoutine<T1, T2, T3, T4> = reference to procedure(const A1: T1; const A2: T2; const A3: T3; const A4: T4);
  TAsymmetricRoutine<RES> = reference to function: RES;
  TAsymmetricRoutine<T, RES> = reference to function(const A: T): RES;
  TAsymmetricRoutine<T1, T2, RES> = reference to function(const A1: T1; const A2: T2): RES;
  TAsymmetricRoutine<T1, T2, T3, RES> = reference to function(const A1: T1; const A2: T2; const A3: T3): RES;
  TAsymmetricRoutine<T1, T2, T3, T4, RES> = reference to function(const A1: T1; const A2: T2; const A3: T3; const A4: T4): RES;
  {$ELSE}
  TSymmetricRoutine = procedure of object;
  TSymmetricArgsRoutine = procedure(const Args: array of const) of object;
  TSymmetricRoutine<T> = procedure(const A: T) of object;
  TSymmetricRoutine<T1, T2> = procedure(const A1: T1; const A2: T2) of object;
  TSymmetricRoutine<T1, T2, T3> = procedure(const A1: T1; const A2: T2; const A3: T3) of object;
  TSymmetricRoutine<T1, T2, T3, T4> = procedure(const A1: T1; const A2: T2; const A3: T3; const A4: T4) of object;
  TAsymmetricRoutine<RES> = function: RES of object;
  TAsymmetricRoutine<T, RES> = function(const A: T): RES of object;
  TAsymmetricRoutine<T1, T2, RES> = function(const A1: T1; const A2: T2): RES of object;
  TAsymmetricRoutine<T1, T2, T3, RES> = function(const A1: T1; const A2: T2; const A3: T3): RES of object;
  TAsymmetricRoutine<T1, T2, T3, T4, RES> = function(const A1: T1; const A2: T2; const A3: T3; const A4: T4): RES of object;
  {$ENDIF}
  TSymmetricRoutineStatic = procedure;
  TSymmetricArgsStatic = procedure(const Args: array of const);
  TSymmetricRoutineStatic<T> = procedure(const A: T);
  TSymmetricRoutineStatic<T1, T2> = procedure(const A1: T1; const A2: T2);
  TSymmetricRoutineStatic<T1, T2, T3> = procedure(const A1: T1; const A2: T2; const A3: T3);
  TSymmetricRoutineStatic<T1, T2, T3, T4> = procedure(const A1: T1; const A2: T2; const A3: T3; const A4: T4);
  TAsymmetricRoutineStatic<RES> = function: RES;
  TAsymmetricRoutineStatic<T, RES> = function(const A: T): RES;
  TAsymmetricRoutineStatic<T1, T2, RES> = function(const A1: T1; const A2: T2): RES;
  TAsymmetricRoutineStatic<T1, T2, T3, RES> = function(const A1: T1; const A2: T2; const A3: T3): RES;
  TAsymmetricRoutineStatic<T1, T2, T3, T4, RES> = function(const A1: T1; const A2: T2; const A3: T3; const A4: T4): RES;

  // tuple of parameters
  tTuple = array of TVarRec;

  // greenlet state
  tGreenletState = (
    gsReady,       // ready for the first launch
    gsExecute,     // is executing
    gsTerminated,  // greenlet is ended on its own
    gsKilled,      // greenlet is killed outside
    gsException,   // greenlet is ended with Exception
    gsSuspended,   // greenlet is suspended
    gsKilling      // greenlet is in killing state
  );

  TEnumerator<T> = class
  protected
    function GetCurrent: T; virtual; abstract;
  public
    function MoveNext: Boolean; dynamic; abstract;
    property Current: T read GetCurrent;
    procedure Reset; dynamic; abstract;
  end;

  IGenerator<T> = interface
    function GetEnumerator: TEnumerator<T>;
    procedure Setup(const Args: array of const);
  end;

  TExceptionClass = class of Exception;

  TIOOperation = (ioNotSet, ioRead, ioWrite);
  TIOCallback = procedure(Fd: THandle; const Op: TIOOperation; Data: Pointer;
    ErrorCode: Integer; NumOfBytes: LongWord);
  TEventCallback = procedure(Hnd: THandle; Data: Pointer; const Aborted: Boolean);
  TInervalCallback = procedure(Id: THandle; Data: Pointer);

  EHubError = class(Exception);

  TTaskProc = procedure(Arg: Pointer);

  TExitCondition = function: Boolean of object;
  TExitConditionStatic = function: Boolean;

  TAnyAddress = record
    AddrPtr: Pointer;
    AddrLen: Integer;
  end;

  IIoHandler = interface
    ['{9FD7E7C2-B328-4F75-9E8F-E3F201B4462A}']
    function Emitter: IGevent;
    procedure Lock;
    procedure Unlock;
    function ReallocBuf(Size: LongWord): Pointer;
    function GetBufSize: LongWord;
  end;

  TCustomHub = class
  strict private
    FIsSuspended: Boolean;
    FName: string;
  public
    property Name: string read FName write FName;
    property IsSuspended: Boolean read FIsSuspended write FIsSuspended;
    function  HLS(const Key: string): TObject; overload; dynamic; abstract;
    procedure HLS(const Key: string; Value: TObject); overload; dynamic; abstract;
    function  GC(A: TObject): IGCObject; dynamic; abstract;
    // tasks
    procedure EnqueueTask(const Task: TThreadMethod); overload; dynamic; abstract;
    procedure EnqueueTask(const Task: TTaskProc; Arg: Pointer); overload; dynamic; abstract;
    // IO files and sockets
    procedure Cancel(Fd: THandle); dynamic; abstract;
    function Write(Fd: THandle; Buf: Pointer; Len: LongWord; const Cb: TIOCallback; Data: Pointer; Offset: Int64 = -1): Boolean; dynamic; abstract;
    function WriteTo(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean; dynamic; abstract;
    function Read(Fd: THandle; Buf: Pointer; Len: LongWord; const Cb: TIOCallback; Data: Pointer; Offset: Int64 = -1): Boolean; dynamic; abstract;
    function ReadFrom(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean; dynamic; abstract;
    // IO timeouts and timers
    function CreateTimer(const Cb: TInervalCallback; Data: Pointer; Interval: LongWord): THandle; dynamic; abstract;
    procedure DestroyTimer(Id: THandle); dynamic; abstract;
    function CreateTimeout(const Cb: TInervalCallback; Data: Pointer; Interval: LongWord): THandle; dynamic; abstract;
    procedure DestroyTimeout(Id: THandle); dynamic; abstract;
    // Event objects
    function  AddEvent(Ev: THandle; const Cb: TEventCallback; Data: Pointer): Boolean; dynamic; abstract;
    procedure RemEvent(Ev: THandle); dynamic; abstract;
    // loop
    function Serve(TimeOut: LongWord): Boolean; dynamic; abstract;
    // pulse hub
    procedure Pulse; dynamic; abstract;
    // Loop
    procedure LoopExit; dynamic; abstract;
    procedure Loop(const Cond: TExitCondition; Timeout: LongWord = INFINITE); overload; dynamic; abstract;
    procedure Loop(const Cond: TExitConditionStatic; Timeout: LongWord = INFINITE); overload; dynamic; abstract;
    // switch to thread root context
    procedure Switch; dynamic; abstract;
  end;

  IGreenletProxy = interface
    procedure Pulse;
    procedure DelayedSwitch;
    procedure Resume;
    procedure Suspend;
    procedure Kill;
    function  GetHub: TCustomHub;
    function  GetState: tGreenletState;
    function  GetException: Exception;
    function  GetOnStateChanged: TGevent;
    function  GetOnTerminate: TGevent;
    function  GetUID: NativeUInt;
  end;

  IRawGreenlet = interface
    function  GetUID: NativeUInt;
    function  GetProxy: IGreenletProxy;
    procedure Switch;
    procedure Yield;
    procedure Kill;
    procedure Suspend;
    procedure Resume;
    procedure Inject(E: Exception); overload;
    procedure Inject(const Routune: TSymmetricRoutine); overload;
    function  GetState: tGreenletState;
    function  GetException: Exception;
    function  GetInstance: TObject;
    function  GetOnStateChanged: TGevent;
    function  GetOnTerminate: TGevent;
    function  GetName: string;
    procedure SetName(const Value: string);
    procedure Join(const RaiseErrors: Boolean = False);
    procedure ReraiseException;
    {$IFDEF DEBUG}
    function RefCount: Integer;
    {$ENDIF}
  end;

  IGreenGroup<KEY> = interface
    procedure SetValue(const Key: KEY; G: IRawGreenlet);
    function  GetValue(const Key: KEY): IRawGreenlet;
    procedure Clear;
    procedure KillAll;
    function IsEmpty: Boolean;
    function Join(Timeout: LongWord = INFINITE; const RaiseError: Boolean = False): Boolean;
    function Copy: IGreenGroup<KEY>;
    function Count: Integer;
  end;

  IGreenlet = interface(IRawGreenlet)
    function  Switch: tTuple; overload;
    function  Switch(const Args: array of const): tTuple; overload;
    function Yield: tTuple; overload;
    function Yield(const A: array of const): tTuple; overload;
  end;

  IAsymmetric<T> = interface(IRawGreenlet)
    function GetResult(const Block: Boolean = True): T;
  end;

  IGCondVariable = interface
    ['{BB479A02-A201-4339-B600-26043F523FDB}']
    procedure SetSync(const Value: Boolean);
    function GetSync: Boolean;
    property Sync: Boolean read GetSync write SetSync;
    procedure Wait(aUnlocking: TCriticalSection = nil); overload;
    procedure Wait(aSpinUnlocking: TPasMPSpinLock); overload;
    procedure Signal;
    procedure Broadcast;
  end;

  IGSemaphore = interface
    ['{098C6819-DE79-4A7D-9840-DB4747C581AC}']
    procedure Acquire;
    procedure Release;
    function Limit: LongWord;
    function Value: LongWord;
  end;

  IGMutex = interface
    ['{2CD93CD7-E3B6-4DB5-ABBC-9D764EC2D82E}']
    procedure Acquire;
    procedure Release;
  end;

  IGQueue<T> = interface
    ['{28CABD15-521C-4BE0-AC2A-031BA29C2FDF}']
    procedure Enqueue(A: T);
    procedure Dequeue(out A: T);
    procedure Clear;
    function Count: Integer;
  end;

  IAbstractChannel = interface
  ['{4BA64DCF-5E5F-46D0-B74C-8F8A6F370917}']
    procedure AccumRefs(ReadRefCount, WriteRefCount: Integer);
    procedure ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
    procedure SetDeadlockExceptionClass(Cls: TExceptionClass);
    function  GetDeadlockExceptionClass: TExceptionClass;
  end;

  EResultIsEmpty = class(Exception);

  // channel allows you to catch DeadLock
  EChannelDeadLock = class(Exception);
  EChannelLeaveLock = class(Exception);
  EChannelClosed = class(Exception);

  IErrorHolder<ERROR> = interface
    ['{252FD6CA-D691-4D45-BDFB-FC3C769D7EE0}']
    function GetErrorCode: ERROR;
    function GetErrorStr: string;
  end;

  IFuture<RESULT, ERROR> = interface(IErrorHolder<ERROR>)
    ['{00A2154A-0B80-4267-9E44-1E68430E48A6}']
    function OnFullFilled: TGevent;
    function OnRejected: TGevent;
    function GetResult: RESULT;
  end;

  IPromise<RESULT, STATUS> = interface
    ['{33FF6CE8-4B84-4911-A7A5-FEB67C646C25}']
    procedure SetResult(const A: RESULT);
    procedure SetErrorCode(Value: STATUS; const ErrorStr: string = '');
  end;

  TPendingError = (psUnknown, psClosed, psDeadlock, psTimeout, psException, psSuccess);

  IReadOnly<T> = interface(IAbstractChannel)
  ['{ACD057AD-B28A-4232-98D9-6ABC0732A732}']
    function Read(out A: T): Boolean;
    function ReadPending: IFuture<T, TPendingError>;
    procedure Close;
    function IsClosed: Boolean;
    function GetEnumerator: TEnumerator<T>;
    function Get: T;
    function GetBufSize: LongWord;
  end;

  IWriteOnly<T> =  interface(IAbstractChannel)
  ['{2CD85C7A-6BDB-454F-BF54-9F260DA237B4}']
    function Write(const A: T): Boolean;
    function WritePending(const A: T): IFuture<T, TPendingError>;
    procedure Close;
    function IsClosed: Boolean;
    function GetBufSize: LongWord;
  end;

  IChannel<T> = interface(IAbstractChannel)
  ['{275B1ED7-0927-497C-8689-5030AAE94341}']
    function Read(out A: T): Boolean;
    function Write(const A: T): Boolean;
    function ReadOnly: IReadOnly<T>;
    function WriteOnly: IWriteOnly<T>;
    procedure Close;
    function IsClosed: Boolean;
    function GetEnumerator: TEnumerator<T>;
    function Get: T;
    function GetBufSize: LongWord;
    function ReadPending: IFuture<T, TPendingError>;
    function WritePending(const A: T): IFuture<T, TPendingError>;
  end;

  IFanOut<T> = interface
    function Inflate(const BufSize: Integer=-1): IReadOnly<T>;
  end;

  ICase = interface
    ['{20C53130-1104-4644-BE7B-C06249FC0631}']
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
    // props
    property Operation: TIOOperation read GetOperation write SetOperation;
    property OnSuccess: TGevent read GetOnSuccess write SetOnSuccess;
    property OnError: TGevent read GetOnError write SetOnError;
    property ErrorHolder: IErrorHolder<TPendingError> read GetErrorHolder write SetErrorHolder;
    property WriteValueExists: Boolean read GetWriteValueExists write SetWriteValueExists;
  end;

  ICollection<T> = interface
    ['{8C5840E8-A67D-40A6-9733-62087EAAE8D6}']
    procedure Append(const A: T; const IgnoreDuplicates: Boolean); overload;
    procedure Append(const Other: ICollection<T>; const IgnoreDuplicates: Boolean); overload;
    procedure Remove(const A: T);
    function Count: Integer;
    function Get(Index: Integer): T;
    function Copy: ICollection<T>;
    procedure Clear;
    function GetEnumerator: TEnumerator<T>;
  end;

implementation

end.
