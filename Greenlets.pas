unit Greenlets;

interface
uses GInterfaces, SyncObjs, SysUtils, Classes, Gevent, GarbageCollector,
  Hub, PasMP;

type

  TSmartPointer<T> = record
  strict private
    FObjRef: IGCObject;
    FRef: T;
    class function IsClass: Boolean; static;
  public
    class operator Implicit(A: TSmartPointer<T>): T;
    class operator Implicit(A: T): TSmartPointer<T>;
    function Get: T;
  end;

  ///	<summary>
  /// Ensures that the coroutines addressed to the resource
  /// will be queued and in the same order will be
  /// access when Condition is reset. state
  /// Thanks to the participation of the mutex / critical section can save ABA problems
  ///	</summary>
  { code example:
      ___ greenlet/thread no.1
      Cond := TGCondVariable.Create;
      ....
        do somethings
      ....
      Cond.Broadcast;

      ___ greenlet/thread no.2
      Cond.Wait;  ... wait signal

      ___ greenlet/thread no.3
      Cond.Wait; ... wait signal

  }
  TGCondVariable = record
  strict private
    Impl: IGCondVariable;
    function GetImpl: IGCondVariable;
  public
    class function Make(aExternalMutex: TCriticalSection = nil): TGCondVariable; static;
    ///	<summary>
    ///   Wait for the signal state
    ///	</summary>
    ///	<remarks>
    /// If the decision about Wait is received inside the Lock
    /// will safely escape this lock inside the call Wait
    /// because getting into the waiting queue must happen
    /// to unLock-a and not lose state
    ///	</remarks>
    procedure Wait(aUnlocking: TCriticalSection = nil); overload; inline;
    procedure Wait(aSpinUnlocking: TPasMPSpinLock); overload; inline;
    ///	<summary>
    ///   Toss the first in the queue (if there is one)
    ///	</summary>
    procedure Signal; inline;
    ///	<summary>
    ///   To pull all queue
    ///	</summary>
    procedure Broadcast; inline;
  end;

  ///	<summary>
  ///   Semaphore
  ///	</summary>
  TGSemaphore = record
  strict private
    Impl: IGSemaphore;
  public
    class function Make(Limit: LongWord): TGSemaphore; static;
    procedure Acquire; inline;
    procedure Release; inline;
    function Limit: LongWord; inline;
    function Value: LongWord; inline;
  end;

  TGMutex = record
  strict private
    Impl: IGMutex;
    function GetImpl: IGMutex;
  public
    procedure Acquire; inline;
    procedure Release; inline;
  end;

  ///	<summary>
  ///   A queue for synchronizing coroutines or coroutines with a thread
  ///	</summary>
  TGQueue<T> = record
  strict private
    Impl: IGQueue<T>;
  public
    class function Make(MaxCount: LongWord = 0): TGQueue<T>; static;
    procedure Enqueue(A: T); inline;
    procedure Dequeue(out A: T); inline;
    procedure Clear; inline;
    function Count: Integer; inline;
  end;

  {*
    The environment allows grinlets created in the text. context inherit
     environment variables
  *}
  IGreenEnvironment = interface
    procedure SetValue(const Name: string; Value: TPersistent);
    function  GetValue(const Name: string): TPersistent;
    procedure UnsetValue(const Name: string);
    procedure Clear;
    // simple values
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
  end;

  {*
    Coroutine - starts the procedure on its stack
     with its CPU registers with its exception handler tree
  *}

  TGreenlet = record
  private
    Impl: IGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine); overload;
    constructor Create(const Routine: TSymmetricArgsRoutine; const Args: array of const); overload;
    constructor Create(const Routine: TSymmetricArgsStatic; const Args: array of const); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine): TGreenlet; overload; static;
    class function Spawn(const Routine: TSymmetricArgsRoutine;
      const Args: array of const): TGreenlet; overload; static;
    class function Spawn(const Routine: TSymmetricArgsStatic;
      const Args: array of const): TGreenlet; overload; static;
    procedure Kill;
    procedure Join;
    class operator Implicit(const A: TGreenlet): IGreenlet; overload;
    class operator Implicit(const A: TGreenlet): TGevent; overload;
    ///	<summary>
    ///	  Give Processor
    ///	</summary>
    function Switch: tTuple; overload;
    // You can transfer parameters on the move, which are Greenlet
    // get through ... var X: tTuple; X: = Yield; ...
    // (useful when tuning the generator on the fly)
    function Switch(const Args: array of const): tTuple; overload;
    // Вернуть управление вызвавшему
    class function Yield: tTuple; overload; static;
    // Вернуть управление вызвавшей микронитке и передать данные через очередь Thread-а
    // (удобно при маппинге данных)
    class function Yield(const A: array of const): tTuple; overload; static;
  end;

  // Generator
  { code example:
  var
    Gen := TGenerator<Integer>
    I: Integer;
  begin
    Gen := TGenerator<Integer>.Create(Increment, [4, 11, 3])
    for I in Gen do begin  // will produce 4, 7, 10 witout allocation data in memory
      -> do somethings
    end
  end;

  procedure Increment(const Args: array of const);
  var
    Value, Stop, IncValue: Integer;
  begin
    Value := Args[0].AsInteger;
    Stop := Args[1].AsInteger;
    IncValue := Args[2].AsInteger;
    repeat
      TGenerator<Integer>.Yield(Value);
      Value := Value + IncValue;
    until Value > Stop;
  end;
  }

  TGenerator<T> = record
  private
    Impl: IGenerator<T>;
  public
    constructor Create(const Routine: TSymmetricRoutine); overload;
    constructor Create(const Routine: TSymmetricArgsRoutine;const Args: array of const); overload;
    constructor Create(const Routine: TSymmetricArgsStatic; const Args: array of const); overload;
    procedure Setup(const Args: array of const);
    function GetEnumerator: GInterfaces.TEnumerator<T>;
    class procedure Yield(const Value: T); static;
  end;

  {*
    Allows you to combine machines into a group and simultaneously destroy / wait
  *}

  TGreenGroup<KEY> = record
  private
    Impl: IGreenGroup<KEY>;
    function GetImpl: IGreenGroup<KEY>;
    procedure SetValue(const Key: KEY; G: IRawGreenlet);
    function  GetValue(const Key: KEY): IRawGreenlet;
  public
    property Item[const Index: KEY]: IRawGreenlet read GetValue write SetValue; default;
    function Join(Timeout: LongWord = INFINITE; const RaiseError: Boolean = False): Boolean;
    procedure Clear;
    procedure KillAll;
    function IsEmpty: Boolean;
    function Copy: TGreenGroup<KEY>;
    function Count: Integer;
  end;

  TSymmetric = record
  private
    Impl: IRawGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine): TSymmetric; overload; static;
    class function Spawn(const Routine: TSymmetricRoutineStatic): TSymmetric; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TSymmetric): IRawGreenlet; overload;
    class operator Implicit(const A: TSymmetric): TGevent; overload;
  end;

  TSymmetric<T> = record
  private
    Impl: IRawGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine<T>; const A: T); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T>; const A: T); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine<T>; const A: T): TSymmetric<T>; overload; static;
    class function Spawn(const Routine: TSymmetricRoutineStatic<T>; const A: T): TSymmetric<T>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TSymmetric<T>): IRawGreenlet; overload;
    class operator Implicit(const A: TSymmetric<T>): TGevent; overload;
  end;

  TSymmetric<T1, T2> = record
  private
    Impl: IRawGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2>; const A1: T1; const A2: T2); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1; const A2: T2); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine<T1, T2>; const A1: T1; const A2: T2): TSymmetric<T1, T2>; overload; static;
    class function Spawn(const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1; const A2: T2): TSymmetric<T1, T2>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TSymmetric<T1, T2>): IRawGreenlet; overload;
    class operator Implicit(const A: TSymmetric<T1, T2>): TGevent; overload;
  end;

  TSymmetric<T1, T2, T3> = record
  private
    Impl: IRawGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>; overload; static;
    class function Spawn(const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TSymmetric<T1, T2, T3>): IRawGreenlet; overload;
    class operator Implicit(const A: TSymmetric<T1, T2, T3>): TGevent; overload;
  end;

  TSymmetric<T1, T2, T3, T4> = record
  private
    Impl: IRawGreenlet;
  public
    constructor Create(const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4); overload;
    constructor Create(const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4); overload;
    procedure Run;
    class function Spawn(const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>; overload; static;
    class function Spawn(const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TSymmetric<T1, T2, T3, T4>): IRawGreenlet; overload;
    class operator Implicit(const A: TSymmetric<T1, T2, T3, T4>): TGevent; overload;
  end;

  TAsymmetric<Y> = record
  private
    Impl: IAsymmetric<Y>;
  public
    constructor Create(const Routine: TAsymmetricRoutine<Y>); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<Y>); overload;
    procedure Run;
    class function Spawn(const Routine: TAsymmetricRoutine<Y>): TAsymmetric<Y>; overload; static;
    class function Spawn(const Routine: TAsymmetricRoutineStatic<Y>): TAsymmetric<Y>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TAsymmetric<Y>): IRawGreenlet; overload;
    class operator Implicit(const A: TAsymmetric<Y>): IAsymmetric<Y>; overload;
    class operator Implicit(const A: TAsymmetric<Y>): TGevent; overload;
    function GetResult(const Block: Boolean = True): Y;
    {$IFDEF DCC}
    class function Spawn<T>(const Routine: TAsymmetricRoutine<T, Y>; const A: T): TAsymmetric<Y>; overload; static;
    class function Spawn<T>(const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2>(const Routine: TAsymmetricRoutine<T1,T2,Y>; const A1: T1; const A2: T2): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2>(const Routine: TAsymmetricRoutineStatic<T1,T2,Y>; const A1: T1; const A2: T2): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2,T3>(const Routine: TAsymmetricRoutine<T1,T2,T3,Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2,T3>(const Routine: TAsymmetricRoutineStatic<T1,T2,T3,Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2,T3,T4>(const Routine: TAsymmetricRoutine<T1,T2,T3,T4,Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>; overload; static;
    class function Spawn<T1,T2,T3,T4>(const Routine: TAsymmetricRoutineStatic<T1,T2,T3,T4,Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>; overload; static;
    {$ENDIF}
  end;

  TAsymmetric<T, Y> = record
  private
    Impl: IAsymmetric<Y>;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T, Y>; const A: T); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T); overload;
    procedure Run;
    class function Spawn(const Routine: TAsymmetricRoutine<T, Y>; const A: T): TAsymmetric<T, Y>; overload; static;
    class function Spawn(const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<T, Y>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TAsymmetric<T, Y>): IRawGreenlet; overload;
    class operator Implicit(const A: TAsymmetric<T, Y>): IAsymmetric<Y>; overload;
    class operator Implicit(const A: TAsymmetric<T, Y>): TGevent; overload;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetric<T1, T2, Y> = record
  private
    Impl: IAsymmetric<Y>;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1; const A2: T2); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1; const A2: T2); overload;
    procedure Run;
    class function Spawn(const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<T1, T2, Y>; overload; static;
    class function Spawn(const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<T1, T2, Y>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TAsymmetric<T1, T2, Y>): IRawGreenlet; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, Y>): IAsymmetric<Y>; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, Y>): TGevent; overload;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetric<T1, T2, T3, Y> = record
  private
    Impl: IAsymmetric<Y>;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3); overload;
    procedure Run;
    class function Spawn(const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<T1, T2, T3, Y>; overload; static;
    class function Spawn(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<T1, T2, T3, Y>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, Y>): IRawGreenlet; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, Y>): IAsymmetric<Y>; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, Y>): TGevent; overload;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TAsymmetric<T1, T2, T3, T4, Y> = record
  private
    Impl: IAsymmetric<Y>;
  public
    constructor Create(const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4); overload;
    constructor Create(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4); overload;
    procedure Run;
    class function Spawn(const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<T1, T2, T3, T4, Y>; overload; static;
    class function Spawn(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<T1, T2, T3, T4, Y>; overload; static;
    procedure Kill;
    procedure Join(const RaiseErrors: Boolean = False);
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, T4, Y>): IRawGreenlet; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, T4, Y>): IAsymmetric<Y>; overload;
    class operator Implicit(const A: TAsymmetric<T1, T2, T3, T4, Y>): TGevent; overload;
    function GetResult(const Block: Boolean = True): Y;
  end;

  TSymmetricFactory = class
  strict private
    FHub: THub;
  public
    constructor Create(Hub: THub);
    function Spawn(const Routine: TSymmetricRoutine): TSymmetric; overload;
    function Spawn(const Routine: TSymmetricRoutineStatic): TSymmetric; overload;
    function Spawn<T>(const Routine: TSymmetricRoutine<T>; const A: T): TSymmetric<T>; overload;
    function Spawn<T>(const Routine: TSymmetricRoutineStatic<T>; const A: T): TSymmetric<T>; overload;
    function Spawn<T1, T2>(const Routine: TSymmetricRoutine<T1, T2>; const A1: T1; const A2: T2): TSymmetric<T1, T2>; overload;
    function Spawn<T1, T2>(const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1; const A2: T2): TSymmetric<T1, T2>; overload;
    function Spawn<T1, T2, T3>(const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>; overload;
    function Spawn<T1, T2, T3>(const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1; const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>; overload;
    function Spawn<T1, T2, T3, T4>(const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>; overload;
    function Spawn<T1, T2, T3, T4>(const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>; overload;
  end;

  TAsymmetricFactory<Y> = class
  strict private
    FHub: THub;
  public
    constructor Create(Hub: THub);
    function Spawn(const Routine: TAsymmetricRoutine<Y>): TAsymmetric<Y>; overload;
    function Spawn(const Routine: TAsymmetricRoutineStatic<Y>): TAsymmetric<Y>; overload;
    function Spawn<T>(const Routine: TAsymmetricRoutine<T, Y>; const A: T): TAsymmetric<Y>; overload;
    function Spawn<T>(const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<Y>; overload;
    function Spawn<T1, T2>(const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<Y>; overload;
    function Spawn<T1, T2>(const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<Y>; overload;
    function Spawn<T1, T2, T3>(const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>; overload;
    function Spawn<T1, T2, T3>(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>; overload;
    function Spawn<T1, T2, T3, T4>(const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>; overload;
    function Spawn<T1, T2, T3, T4>(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>; overload;
  end;

  TGreenThread = class(TThread)
  class var
    NumberOfInstances: Integer;
  strict private
    FOnTerminate: TGevent;
    FHub: TSingleThreadHub;
    FSymmetrics: TSymmetricFactory;
    FHash: TObject;
    function ExitCond: Boolean;
    procedure DoAbort;
  protected
    procedure Execute; override;
  public
    constructor Create; overload;
    destructor Destroy; override;
    procedure Kill(const GreenBlock: Boolean = True);
    function Symmetrics: TSymmetricFactory;
    function Asymmetrics<Y>: TAsymmetricFactory<Y>;
  end;

  ///	<summary>
  /// Allows nonblocking write / read for channels through Select
  /// </summary>
  TCase<T> = record
  private
    Impl: ICase;
    FValueHolder: TSmartPointer<T>;
    FValueToWrite: IFuture<T, TPendingError>;
    FValueToRead: IFuture<T, TPendingError>;
  public
    class operator Implicit(var A: TCase<T>): ICase;
    class operator Implicit(const A: TCase<T>): T;
    class operator Implicit(const A: T): TCase<T>;
    class operator Equal(a: TCase<T>; b: T) : Boolean; overload;
    class operator Equal(a: T; b: TCase<T>) : Boolean; overload;
    function Get: T;
  end;

  ///	<summary>
  /// transmission channel, allows data to be exchanged between actors
  /// 1) you can catch the closing of the channel
  /// 2) As in Erlang and Scala, you can build graphs of processing from actors (implemented on greenlets)
  /// linked channels
  /// 3) the solution to the problem of lost-update -> after the channel is closed, you can "add" the latest data
  /// 4) you can catch DeadLock-and or LeaveLock-and
  /// 5) synchronous. channel with ThreadSafe = False - minimum of overheads for data transmission
  ///	</summary>
  { code example:

      ___ geenlet/thread no.1 (producer) ___
      Ch := TChannel<Integer>.Make;
      repeat
        A := MakeData(...)
      unlil not Ch.Write(A);
      Ch.Close;

      ___ geenlet/thread no.2 (consumer) ___
      while Ch.Read(Value) do begin
        ...  // do somethings
      end;
  }

  TChannel<T> = record
  type
    // readonly side
    TReadOnly = record
    private
      Impl: IReadOnly<T>;
      function GetDeadlockException: TExceptionClass;
      procedure SetDeadlockEsxception(const Value: TExceptionClass);
    public
      class operator Implicit(const Ch: TReadOnly): IAbstractChannel;
      class operator LessThan(var a: TCase<T>; const b: TReadOnly): Boolean;
      function Read(out A: T): Boolean;
      function ReadPending: IFuture<T, TPendingError>;
      function GetEnumerator: TEnumerator<T>;
      function Get: T;
      procedure Close;
      function IsClosed: Boolean;
      property DeadlockEsxception: TExceptionClass read GetDeadlockException write SetDeadlockEsxception;
      function IsNull: Boolean;
    end;
    // writeonly side
    TWriteOnly = record
    private
      Impl: IWriteOnly<T>;
      function GetDeadlockException: TExceptionClass;
      procedure SetDeadlockEsxception(const Value: TExceptionClass);
    public
      class operator Implicit(const Ch: TWriteOnly): IAbstractChannel;
      class operator LessThan(const a: TWriteOnly; var b: TCase<T>): Boolean;
      function Write(const A: T): Boolean;
      function WritePending(const A: T): IFuture<T, TPendingError>;
      procedure Close;
      function IsClosed: Boolean;
      property DeadlockEsxception: TExceptionClass read GetDeadlockException write SetDeadlockEsxception;
      function IsNull: Boolean;
    end;
  private
    Impl: IChannel<T>;
    function GetDeadlockException: TExceptionClass;
    procedure SetDeadlockEsxception(const Value: TExceptionClass);
  public
    class function Make(Size: LongWord = 0; const ThreadSafe: Boolean = True): TChannel<T>; static;
    class operator Implicit(const Ch: TChannel<T>): IChannel<T>;
    class operator LessThan(var a: TCase<T>; const b: TChannel<T>): Boolean;
    class operator LessThan(const a: TChannel<T>; var b: TCase<T>): Boolean;
    function Read(out A: T): Boolean;
    function ReadPending: IFuture<T, TPendingError>;
    function Write(const A: T): Boolean;
    function WritePending(const A: T): IFuture<T, TPendingError>;
    function ReadOnly: TReadOnly;
    function WriteOnly: TWriteOnly;
    procedure Close;
    function IsClosed: Boolean;
    function GetEnumerator: TEnumerator<T>;
    function Get: T;
    property DeadlockEsxception: TExceptionClass read GetDeadlockException write SetDeadlockEsxception;
    function IsNull: Boolean;
  end;

  ///	<summary>
  ///  Fan - allows to duplicate copies on channels
  ///	</summary>
  { code example:

      Ch := TChannel<Integer>.Make;
      FanOut := TFanOut<Integer>.Make(Ch.ReadOnly);

      Consumer1 := Spawn(Routine1, FanOut.Inflate);
      Consumer2 := Spawn(Routine2, FanOut.Inflate);
      ....
      ConsumerN := Spawn(RoutineN, FanOut.Inflate);

      ...

      Ch.Write(1);
      Ch.Write(2);
      ...
      Ch.Write(M);
  }

  TFanOut<T> = record
  strict private
    Impl: IFanOut<T>;
  public
    constructor Make(const Input: TChannel<T>.TReadOnly);
    function Inflate(const BufSize: Integer=-1): TChannel<T>.TReadOnly;
  end;

  TFuturePromise<RESULT, STATUS> = record
  strict private
    FFuture: IFuture<RESULT, STATUS>;
    FPromise: IPromise<RESULT, STATUS>;
    procedure Init;
    function GetFuture: IFuture<RESULT, STATUS>;
    function GetPromise: IPromise<RESULT, STATUS>;
  public
    property Future: IFuture<RESULT, STATUS> read GetFuture;
    property Promise: IPromise<RESULT, STATUS> read GetPromise;
  end;

  TSwitchResult = (srClosed, srDeadlock, srTimeout,
    srReadSuccess, srWriteSuccess, srException, srError);

  TCaseSet = record
  private
    Collection: ICollection<ICase>;
    function GetCollection: ICollection<ICase>;
  public
    class function Make(const Cases: array of ICase): TCaseSet; static;
    class operator Implicit(const A: ICase): TCaseSet;
    class operator Add(a: TCaseSet; b: ICase): TCaseSet;
    class operator Add(a: TCaseSet; b: TCaseSet): TCaseSet;
    class operator Subtract(a: TCaseSet; b: ICase) : TCaseSet;
    class operator Subtract(a: TCaseSet; b: TCaseSet) : TCaseSet;
    function IsEmpty: Boolean;
    procedure Clear;
    function Has(a: ICase): Boolean;
    class operator In(a: ICase; b: TCaseSet) : Boolean;
  end;

function Slice(const Args: array of const; FromIndex: Integer;
  ToIndex: Integer = -1): tTuple;
// current context
function GetCurrent: TObject;
function GetEnvironment: IGreenEnvironment;
// Greenlet context access
function  Context(const Key: string): TObject; overload; // достать значение по ключу
procedure Context(const Key: string; Value: TObject); overload; // установить по ключу
// Garbage collector
function GC(A: TObject): IGCObject; overload;
// Return control from current Greenlet context
procedure Yield;
// Put greenlets on service in the current context
// RaiseErrors=True -> Exception in some of greenlet will be thrown out
function Join(const Workers: array of IRawGreenlet;
  const Timeout: LongWord=INFINITE; const RaiseErrors: Boolean = False): Boolean;
// Join all grinlets launched in on current HUB. hub by default
function JoinAll(const Timeout: LongWord=INFINITE; const RaiseErrors: Boolean = False): Boolean;
// demultiplexer for a set of events, Index - index of the first signaled
function Select(const Events: array of TGevent; out Index: Integer;
  const Timeout: LongWord=INFINITE): TWaitResult; overload;
function Select(const Events: array of THandle; out Index: Integer;
  const Timeout: LongWord=INFINITE): Boolean; overload;
// Demultiplexer for channels, for nonblocking input-output
function Switch(const Cases: array of ICase; out Index: Integer;
  const Timeout: LongWord=INFINITE): TSwitchResult; overload;
function Switch(var ReadSet: TCaseSet; var WriteSet: TCaseSet; var ErrorSet: TCaseSet;
  const Timeout: LongWord=INFINITE): TSwitchResult; overload;
// Put the coroutine / thread on aTimeOut msec
// this does not block the work of other machines
procedure GreenSleep(aTimeOut: LongWord = INFINITE);

// jump over to another thread
procedure MoveTo(Thread: TGreenThread);
procedure BeginThread;
procedure EndThread;

// context handlers
procedure RegisterKillHandler(Cb: TThreadMethod);
procedure RegisterHubHandler(Cb: TThreadMethod);

type

  TVarRecHelper = record helper for TVarRec
    function IsString: Boolean;
    function IsObject: Boolean;
    function IsInteger: Boolean;
    function IsInt64: Boolean;
    function IsSingle: Boolean;
    function IsDouble: Boolean;
    function IsBoolean: Boolean;
    function IsVariant: Boolean;
    function IsClass: Boolean;
    function IsPointer: Boolean;
    function IsInterface: Boolean;
    function AsString: string;
    function AsObject: TObject;
    function AsLongWord: LongWord;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsSingle: Single;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function AsVariant: Variant;
    function AsDateTime: TDateTime;
    function AsClass: TClass;
    function AsPointer: Pointer;
    function AsInterface: IInterface;
    function AsAnsiString: AnsiString;
    procedure Finalize;
  end;

implementation
uses Math, ChannelImpl, GreenletsImpl, TypInfo,
  {$IFDEF FPC}
  contnrs, fgl
  {$ELSE}Generics.Collections, Generics.Defaults
  {$ENDIF};

const
  READ_SET_GUID  = '{809964D9-7F70-42AE-AA37-366120DEE5A6}';
  WRITE_SET_GUID = '{6FAB5314-C59A-473D-8871-E30F44CBF5C4}';
  ERROR_SET_GUID = '{5768E2B8-BB72-4A87-BC06-9BCD282BE588}';

type
  TRawGreenletPimpl = class(TRawGreenletImpl);

threadvar
  YieldsFlag: Boolean;

function GetCurrent: TObject;
begin
  Result := TRawGreenletPimpl.GetCurrent
end;

function GetEnvironment: IGreenEnvironment;
begin
  Result := TRawGreenletPimpl.GetEnviron;
end;

function Context(const Key: string): TObject;
begin
  if GetCurrent = nil then
    Result := GetCurrentHub.HLS(Key)
  else begin
    Result := TRawGreenletImpl(GetCurrent).Context.GetValue(Key)
  end;
end;

procedure Context(const Key: string; Value: TObject);
var
  Current: TRawGreenletImpl;
  Obj: TObject;
  CurHub: TCustomHub;
begin
  Current := TRawGreenletImpl(GetCurrent);
  if Current = nil then begin
    if Hub.HubInfrasctuctureEnable then begin
      CurHub := GetCurrentHub;
      if Assigned(CurHub) then
        CurHub.HLS(Key, Value)
    end;
  end
  else begin
    if Current.Context.IsExists(Key) then begin
      Obj := Current.Context.GetValue(Key);
      Obj.Free;
      Current.Context.UnsetValue(Key);
    end;
    if Assigned(Value) then
      Current.Context.SetValue(Key, Value)
  end;
end;

function GC(A: TObject): IGCObject;
var
  Current: TRawGreenletImpl;
begin
  Current := TRawGreenletImpl(GetCurrent);
  if Current = nil then begin
    if HubInfrasctuctureEnable then
      Result := GetCurrentHub.GC(A)
    else
      Result := nil
  end
  else begin
    if Current.GetState <> gsKilling then
      Result := Current.GC.SetValue(A)
    else
      Result := nil;
  end;
end;

function Slice(const Args: array of const; FromIndex: Integer;
  ToIndex: Integer = -1): tTuple;
var
  vToIndex, vFromIndex, I, vLen, Ind: Integer;
begin
  SetLength(Result, 0);
  if ToIndex = -1 then
    vToIndex := High(Args)
  else
    vToIndex := Min(High(Args), ToIndex);
  vFromIndex := FromIndex;
  vLen := vToIndex - vFromIndex + 1;
  if vLen > 0 then begin
    SetLength(Result, vLen);
    Ind := 0;
    for I := vFromIndex to vToIndex do begin
      Result[Ind] := Args[I];
      Inc(Ind);
    end;
  end
end;

function PendingError2SwitchStatus(const Input: TPendingError; const IO: TIOOperation): TSwitchResult;
begin
  Result := srError;
  case Input of
    psClosed:
      Result := srClosed;
    psDeadlock:
      Result := srDeadlock;
    psTimeout:
      Result := srTimeout;
    psException:
      Result := srException;
    psSuccess: begin
      case IO of
        ioNotSet:
          Result := srError;
        ioRead:
          Result := srReadSuccess;
        ioWrite:
          Result := srWriteSuccess;
      end;
    end
    else
      Result := srError
  end;
end;

{ TVarRecHelper }

function TVarRecHelper.AsAnsiString: AnsiString;
begin
  Result := GreenletsImpl.AsAnsiString(Self);
end;

function TVarRecHelper.AsBoolean: Boolean;
begin
  Result := GreenletsImpl.AsBoolean(Self)
end;

function TVarRecHelper.AsClass: TClass;
begin
  Result := GreenletsImpl.AsClass(Self)
end;

function TVarRecHelper.AsDateTime: TDateTime;
begin
  Result := GreenletsImpl.AsDateTime(Self)
end;

function TVarRecHelper.AsDouble: Double;
begin
  Result := GreenletsImpl.AsDouble(Self)
end;

function TVarRecHelper.AsInt64: Int64;
begin
  Result := GreenletsImpl.AsInt64(Self)
end;

function TVarRecHelper.AsInteger: Integer;
begin
  Result := GreenletsImpl.AsInteger(Self)
end;

function TVarRecHelper.AsInterface: IInterface;
begin
  Result := GreenletsImpl.AsInterface(Self)
end;

function TVarRecHelper.AsLongWord: LongWord;
begin
  Result := LongWord(Self.AsInteger)
end;

function TVarRecHelper.AsObject: TObject;
begin
  Result := GreenletsImpl.AsObject(Self)
end;

function TVarRecHelper.AsPointer: Pointer;
begin
  Result := GreenletsImpl.AsPointer(Self)
end;

function TVarRecHelper.AsSingle: Single;
begin
  Result := GreenletsImpl.AsSingle(Self)
end;

function TVarRecHelper.AsString: string;
begin
  Result := GreenletsImpl.AsString(Self)
end;

function TVarRecHelper.AsVariant: Variant;
begin
  Result := GreenletsImpl.AsVariant(Self)
end;

procedure TVarRecHelper.Finalize;
begin
  GreenletsImpl.Finalize(Self);
end;

function TVarRecHelper.IsBoolean: Boolean;
begin
  Result := GreenletsImpl.IsBoolean(Self)
end;

function TVarRecHelper.IsClass: Boolean;
begin
  Result := GreenletsImpl.IsClass(Self)
end;

function TVarRecHelper.IsDouble: Boolean;
begin
  Result := GreenletsImpl.IsDouble(Self)
end;

function TVarRecHelper.IsInt64: Boolean;
begin
  Result := GreenletsImpl.IsInt64(Self)
end;

function TVarRecHelper.IsInteger: Boolean;
begin
  Result := GreenletsImpl.IsInteger(Self)
end;

function TVarRecHelper.IsInterface: Boolean;
begin
  Result := GreenletsImpl.IsInterface(Self)
end;

function TVarRecHelper.IsObject: Boolean;
begin
  Result := GreenletsImpl.IsObject(Self)
end;

function TVarRecHelper.IsPointer: Boolean;
begin
  Result := GreenletsImpl.IsPointer(Self)
end;

function TVarRecHelper.IsSingle: Boolean;
begin
  Result := GreenletsImpl.IsSingle(Self)
end;

function TVarRecHelper.IsString: Boolean;
begin
  Result := GreenletsImpl.IsString(Self)
end;

function TVarRecHelper.IsVariant: Boolean;
begin
  Result := GreenletsImpl.IsVariant(Self)
end;

{ TGreenlet }

constructor TGreenlet.Create(const Routine: TSymmetricRoutine);
begin
  Impl := TGreenletImpl.Create(Routine);
end;

constructor TGreenlet.Create(const Routine: TSymmetricArgsRoutine;
  const Args: array of const);
begin
  Impl := TGreenletImpl.Create(Routine, Args);
end;

constructor TGreenlet.Create(const Routine: TSymmetricArgsStatic;
  const Args: array of const);
begin
  Impl := TGreenletImpl.Create(Routine, Args);
end;

class operator TGreenlet.Implicit(const A: TGreenlet): IGreenlet;
begin
  Result := A.Impl
end;

class operator TGreenlet.Implicit(const A: TGreenlet): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

procedure TGreenlet.Join;
begin
  Greenlets.Join([Self])
end;

procedure TGreenlet.Kill;
begin
  Impl.Kill
end;

procedure TGreenlet.Run;
begin
  if Impl.GetState = gsReady then
    Impl.Switch
end;

class function TGreenlet.Spawn(const Routine: TSymmetricRoutine): TGreenlet;
begin
  Result := TGreenlet.Create(Routine);
  Result.Switch;
end;

class function TGreenlet.Spawn(const Routine: TSymmetricArgsRoutine;
  const Args: array of const): TGreenlet;
begin
  Result := TGreenlet.Create(Routine, Args);
  Result.Switch;
end;

class function TGreenlet.Spawn(const Routine: TSymmetricArgsStatic;
  const Args: array of const): TGreenlet;
begin
  Result := TGreenlet.Create(Routine, Args);
  Result.Switch;
end;

function TGreenlet.Switch(const Args: array of const): tTuple;
begin
  YieldsFlag := True;
  Result := Impl.Switch(Args);
  YieldsFlag := False;
end;

function TGreenlet.Switch: tTuple;
begin
  YieldsFlag := True;
  Result := Impl.Switch;
  YieldsFlag := False;
end;

class function TGreenlet.Yield(const A: array of const): tTuple;
begin
  if YieldsFlag then
    if GetCurrent.InheritsFrom(TGreenletImpl) then
      Result := TGreenletImpl(GetCurrent).Yield(A)
    else
      Greenlets.Yield
  else
    Greenlets.Yield
end;

class function TGreenlet.Yield: tTuple;
begin
  if YieldsFlag then
    if GetCurrent.InheritsFrom(TGreenletImpl) then
      Result := TGreenletImpl(GetCurrent).Yield
    else
      Greenlets.Yield
  else
    Greenlets.Yield
end;

{ TChannel<T> }

procedure TChannel<T>.Close;
begin
  if Assigned(Impl) then
    Impl.Close
end;

function TChannel<T>.Get: T;
begin
  Result := Impl.Get
end;

function TChannel<T>.GetDeadlockException: TExceptionClass;
begin
  Result := Impl.GetDeadlockExceptionClass;
end;

function TChannel<T>.GetEnumerator: GInterfaces.TEnumerator<T>;
begin
  Result := Impl.GetEnumerator
end;

class operator TChannel<T>.Implicit(const Ch: TChannel<T>): IChannel<T>;
begin
  Result := Ch.Impl
end;

function TChannel<T>.IsClosed: Boolean;
begin
  if Assigned(Impl) then
    Result := Impl.IsClosed
  else
    Result := False
end;

function TChannel<T>.IsNull: Boolean;
begin
  Result := not Assigned(Impl)
end;

class operator TChannel<T>.LessThan(const a: TChannel<T>;
  var b: TCase<T>): Boolean;
begin
  Result := a.WriteOnly < b;
end;

class operator TChannel<T>.LessThan(var a: TCase<T>;
  const b: TChannel<T>): Boolean;
begin
  Result := a < b.ReadOnly
end;

class function TChannel<T>.Make(Size: LongWord; const ThreadSafe: Boolean): TChannel<T>;
begin
  if Size = 0 then
    Result.Impl := TSyncChannel<T>.Create(ThreadSafe)
  else
    Result.Impl := TAsyncChannel<T>.Create(Size)
end;

function TChannel<T>.Read(out A: T): Boolean;
begin
  Result := Impl.Read(A)
end;

function TChannel<T>.ReadOnly: TReadOnly;
begin
  Result.Impl := Self.Impl.ReadOnly
end;

function TChannel<T>.ReadPending: IFuture<T, TPendingError>;
begin
  Result := Impl.ReadPending;
end;

procedure TChannel<T>.SetDeadlockEsxception(const Value: TExceptionClass);
begin
  Impl.SetDeadlockExceptionClass(Value);
end;

function TChannel<T>.Write(const A: T): Boolean;
begin
  Result := Impl.Write(A)
end;

function TChannel<T>.WriteOnly: TWriteOnly;
begin
  Result.Impl := Self.Impl.WriteOnly
end;

function TChannel<T>.WritePending(const A: T): IFuture<T, TPendingError>;
begin
  Result := Impl.WritePending(A);
end;

function Join(const Workers: array of IRawGreenlet;
  const Timeout: LongWord=INFINITE; const RaiseErrors: Boolean = False): Boolean;
var
  I: Integer;
  List, TermList: TList<IRawGreenlet>;
  StateEv: TGevent;
  G: IRawGreenlet;
  StopTime: TTime;

  procedure ProcessActiveList;
  var
    I, ActiveCnt: Integer;
    StopTime, NowStamp: TTime;
    CurHub: TCustomHub;
  begin
    CurHub := GetCurrentHub;
    StopTime := TimeOut2Time(Timeout) + Now;
    ActiveCnt := List.Count - TermList.Count;
    NowStamp := Now;
    while (ActiveCnt > 0) and (NowStamp <= StopTime) do begin
      for I := 0 to List.Count-1 do begin
        G := List[I];
        if G.GetProxy.GetHub = nil then begin
          if TermList.IndexOf(G) = -1 then begin
            TermList.Add(G);
            Dec(ActiveCnt);
          end;
        end
        else if G.GetProxy.GetHub = CurHub then begin
          // this hub
          if G.GetState in [gsReady, gsExecute] then
            G.Switch;
          if G.GetProxy.GetHub = CurHub then begin
            case G.GetState of
              gsException: begin
                if RaiseErrors then
                  G.ReraiseException
                else if TermList.IndexOf(G) = -1 then begin
                  TermList.Add(G);
                  Dec(ActiveCnt);
                end;
              end;
              gsReady, gsExecute: begin
                // nothing to do
              end;
              gsSuspended: begin
                Dec(ActiveCnt);
              end
              else begin
                if TermList.IndexOf(G) = -1 then begin
                  TermList.Add(G);
                  Dec(ActiveCnt);
                end;
              end;
            end;
          end;
          G := nil;
        end
        else begin
          // other hub
          case G.GetState of
            gsException: begin
              if RaiseErrors then
                G.ReraiseException
              else if TermList.IndexOf(G) = -1 then begin
                TermList.Add(G);
                Dec(ActiveCnt);
              end;
            end;
            gsTerminated, gsKilled: begin
              if TermList.IndexOf(G) = -1 then begin
                TermList.Add(G);
                Dec(ActiveCnt);
              end;
            end
            else
              Dec(ActiveCnt);
          end;
        end;
        NowStamp := Now;
      end;
      if (ActiveCnt > 0) then begin
        if GetCurrent = nil then
          // we will give an opportunity to work out the demultiplexer
          CurHub.Serve(0)
        else
          // let's work out the neighboring contexts
          TRawGreenletImpl(GetCurrent).Yield;
      end
    end;
  end;

begin
  if Length(Workers) = 0 then
    Exit(True);
  List := TList<IRawGreenlet>.Create;
  TermList := TList<IRawGreenlet>.Create;
  StateEv := TGevent.Create;
  try
    for I := 0 to High(Workers) do begin
      if Assigned(Workers[I]) and (Workers[I].GetInstance <> GetCurrent) then begin
        G := Workers[I];
        List.Add(G);
        StateEv.Associate(G.GetOnStateChanged, I);
      end;
    end;
    if Timeout = INFINITE then begin
      while TermList.Count < List.Count do begin
        ProcessActiveList;
        if TermList.Count < List.Count then
          StateEv.WaitFor
      end;
    end
    else if Timeout = 0 then begin
      ProcessActiveList
    end
    else begin
      StopTime := Now + GreenletsImpl.TimeOut2Time(Timeout);
      while (StopTime > Now) and (TermList.Count < List.Count) do begin
        ProcessActiveList;
        if TermList.Count < List.Count then
          StateEv.WaitFor(GreenletsImpl.Time2TimeOut(StopTime-Now));
      end;
    end;
    Result := TermList.Count = List.Count;
  finally
    List.Free;
    TermList.Free;
    StateEv.Free;
  end;
end;

function JoinAll(const Timeout: LongWord=INFINITE; const RaiseErrors: Boolean = False): Boolean;
var
  StopTime: TTime;
  All: tArrayOfGreenlet;
  Joiner: TJoiner;
  Index: Integer;

  procedure ReraiseExceptions;
  var
    I: Integer;
  begin
    for I := 0 to High(All) do
      if All[I].GetState = gsException then
        TGreenletImpl(All[I].GetInstance).ReraiseException;
  end;

begin
  Assert(GetCurrent = nil, 'You can not call JoinAll from Greenlet context');
  Result := False;
  Joiner := GetJoiner(GetCurrentHub);
  StopTime := Now + TimeOut2Time(Timeout);
  repeat
    All := Joiner.GetAll;
    ReraiseExceptions;
    if Join(All, 0, RaiseErrors) then begin
      Exit(True);
    end;
    if (not Joiner.HasExecutions) and (Now < StopTime) then
      Select(Joiner.GetStateEvents, Index, Time2TimeOut(StopTime - Now));
    ReraiseExceptions;
  until Now >= StopTime;
end;

function Select(const Events: array of TGevent; out Index: Integer;
  const Timeout: LongWord=INFINITE): TWaitResult;
begin
  Result := TGevent.WaitMultiple(Events, Index, Timeout)
end;

function Switch(const Cases: array of ICase; out Index: Integer;
  const Timeout: LongWord=INFINITE): TSwitchResult;
var
  Events: array of TGevent;
  InternalIndex, I: Integer;
  WaitRes: TWaitResult;
begin
  if Length(Cases) = 0 then
    raise EArgumentException.Create('Cases sequence is empty');
  SetLength(Events, 2*Length(Cases));
  for I := 0 to High(Cases) do begin
    Events[2*I] := Cases[I].GetOnSuccess;
    Events[2*I+1] := Cases[I].GetOnError;
  end;
  Index := -1;
  WaitRes := Select(Events, InternalIndex, Timeout);
  case WaitRes of
    wrSignaled: begin
      Index := InternalIndex div 2;
      if (InternalIndex mod 2) = 0 then
        Result := PendingError2SwitchStatus(psSuccess, Cases[Index].Operation)
      else
        Result := PendingError2SwitchStatus(Cases[Index].GetErrorHolder.GetErrorCode,
          Cases[Index].Operation)
    end;
    wrTimeout:
      Result := srTimeout;
    else
      Result := srError
  end;
end;

function Switch(var ReadSet: TCaseSet; var WriteSet: TCaseSet; var ErrorSet: TCaseSet;
  const Timeout: LongWord=INFINITE): TSwitchResult;
var
  Iter: ICase;
  I, WriteOffs, ErrOffs, InternalIndex, Index: Integer;
  ReadEvents, WriteEvents, ErrorEvents, AllEvents: array of TGevent;
  WaitRes: TWaitResult;
begin
  for Iter in ReadSet.GetCollection do
    if Iter.Operation <> ioRead then
      raise EArgumentException.Create('ReadSet must contain initialized cases');

  for Iter in WriteSet.GetCollection do
    if Iter.Operation <> ioWrite then
      raise EArgumentException.Create('WriteSet must contain initialized cases');

  if ReadSet.IsEmpty and WriteSet.IsEmpty and ErrorSet.IsEmpty then
    raise EArgumentException.Create('ReadSet, WriteSet, ErrorSet are is empty');

  SetLength(ReadEvents, ReadSet.GetCollection.Count);
  for I := 0 to High(ReadEvents) do
    ReadEvents[I] := ReadSet.GetCollection.Get(I).OnSuccess;
  WriteOffs := Length(ReadEvents);
  SetLength(WriteEvents, WriteSet.GetCollection.Count);
  for I := 0 to High(WriteEvents) do
    WriteEvents[I] := WriteSet.GetCollection.Get(I).OnSuccess;
  ErrOffs := Length(WriteEvents) + Length(ReadEvents);
  SetLength(ErrorEvents, ErrorSet.GetCollection.Count);
  for I := 0 to High(ErrorEvents) do
    ErrorEvents[I] := ErrorSet.GetCollection.Get(I).OnError;

  SetLength(AllEvents, Length(ReadEvents) + Length(WriteEvents) + Length(ErrorEvents));
  Move(ReadEvents[0], AllEvents[0], Length(ReadEvents)*SizeOf(TGevent));
  Move(WriteEvents[0], AllEvents[WriteOffs], Length(WriteEvents)*SizeOf(TGevent));
  Move(ErrorEvents[0], AllEvents[ErrOffs], Length(ErrorEvents)*SizeOf(TGevent));

  InternalIndex := -1;
  WaitRes := Select(AllEvents, InternalIndex, Timeout);
  case WaitRes of
    wrSignaled: begin
      if InRange(InternalIndex, 0, WriteOffs-1) then begin
        Index := InternalIndex;
        Iter := ReadSet.GetCollection.Get(Index);
        Result := srReadSuccess;
        WriteSet.Clear;
        ErrorSet.Clear;
        ReadSet := TCaseSet.Make([Iter]);
      end
      else if InRange(InternalIndex, WriteOffs, ErrOffs-1) then begin
        Index := InternalIndex - WriteOffs;
        Iter := WriteSet.GetCollection.Get(Index);
        Result := srWriteSuccess;
        ReadSet.Clear;
        ErrorSet.Clear;
        WriteSet := TCaseSet.Make([Iter])
      end
      else begin
        Index := InternalIndex - ErrOffs;
        Iter := ErrorSet.GetCollection.Get(Index);
        Result := PendingError2SwitchStatus(Iter.ErrorHolder.GetErrorCode, Iter.Operation);
        ReadSet.Clear;
        WriteSet.Clear;
        ErrorSet := TCaseSet.Make([Iter])
      end
    end;
    wrTimeout:
      Result := srTimeout;
    else
      Result := srError
  end;
end;

function Select(const Events: array of THandle; out Index: Integer;
  const Timeout: LongWord=INFINITE): Boolean;
var
  Gevents: array of TGevent;
  I: Integer;
begin
  SetLength(Gevents, Length(Events));
  for I := 0 to High(Gevents) do begin
    Gevents[I] := TGevent.Create(Events[I]);
  end;
  try
    Result := Select(Gevents, Index) = wrSignaled
  finally
    for I := 0 to High(Gevents) do
      Gevents[I].Free
  end;
end;

procedure TimeoutCb(Id: THandle; Data: Pointer);
begin
  TGevent(Data).SetEvent(True);
end;

procedure GreenSleep(aTimeOut: LongWord = INFINITE);
var
  Ev: TGevent;
  Timeout: THandle;
begin
  if GetCurrent = nil then begin
    Timeout := 0;
    Ev := TGEvent.Create;
    try
      if aTimeOut = 0 then begin
        Timeout := Hub.GetCurrentHub.CreateTimeout(TimeoutCb, Ev, aTimeOut);
        Ev.WaitFor
      end
      else
        Ev.WaitFor(aTimeOut)
    finally
      if Timeout <> 0 then
        Hub.GetCurrentHub.DestroyTimeout(Timeout);
      Ev.Free;
    end;
  end
  else begin
    TRawGreenletPimpl(GetCurrent).Sleep(aTimeOut);
  end;
end;

procedure MoveTo(Thread: TGreenThread);
begin
  if GetCurrent <> nil then
    TRawGreenletPimpl(GetCurrent).MoveTo(Thread);
end;

procedure BeginThread;
begin
  if GetCurrent <> nil then
    TRawGreenletPimpl(GetCurrent).BeginThread;
end;

procedure EndThread;
begin
  if GetCurrent <> nil then
    TRawGreenletPimpl(GetCurrent).EndThread;
end;

procedure RegisterKillHandler(Cb: TThreadMethod);
begin
  if GetCurrent = nil then begin

  end
  else begin
    TRawGreenletPimpl(GetCurrent).KillTriggers.OnCb(Cb);
  end;
end;

procedure RegisterHubHandler(Cb: TThreadMethod);
begin
  if GetCurrent = nil then begin
    // nothing
  end
  else begin
    TRawGreenletPimpl(GetCurrent).HubTriggers.OnCb(Cb);
  end;
end;

procedure Yield;
begin
  if GetCurrent <> nil then
    TRawGreenletImpl(GetCurrent).Yield
  else begin
    GetCurrentHub.Serve(INFINITE)
  end;
end;

{ TSymmetric<T> }

constructor TSymmetric<T>.Create(const Routine: TSymmetricRoutine<T>;
  const A: T);
begin
  Impl := TSymmetricImpl<T>.Create(Routine, A);
end;

constructor TSymmetric<T>.Create(const Routine: TSymmetricRoutineStatic<T>;
  const A: T);
begin
  Impl := TSymmetricImpl<T>.Create(Routine, A);
end;

class operator TSymmetric<T>.Implicit(const A: TSymmetric<T>): IRawGreenlet;
begin
  Result := A.Impl
end;

class operator TSymmetric<T>.Implicit(const A: TSymmetric<T>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

procedure TSymmetric<T>.Join(const RaiseErrors: Boolean);
begin
  Impl.Join(RaiseErrors);
end;

procedure TSymmetric<T>.Kill;
begin
  Impl.Kill
end;

procedure TSymmetric<T>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TSymmetric<T>.Spawn(const Routine: TSymmetricRoutineStatic<T>;
  const A: T): TSymmetric<T>;
begin
  Result := TSymmetric<T>.Create(Routine, A);
  Result.Impl.Switch;
end;

class function TSymmetric<T>.Spawn(const Routine: TSymmetricRoutine<T>;
  const A: T): TSymmetric<T>;
begin
  Result := TSymmetric<T>.Create(Routine, A);
  Result.Impl.Switch;
end;


{ TChannel<T>.TReadOnly }

function TChannel<T>.TReadOnly.Get: T;
begin
  Result := Impl.Get
end;

procedure TChannel<T>.TReadOnly.Close;
begin
  Impl.Close
end;

function TChannel<T>.TReadOnly.GetDeadlockException: TExceptionClass;
begin
  Result := Impl.GetDeadlockExceptionClass;
end;

function TChannel<T>.TReadOnly.GetEnumerator: GInterfaces.TEnumerator<T>;
begin
  Result := Impl.GetEnumerator
end;

class operator TChannel<T>.TReadOnly.Implicit(const Ch: TReadOnly): IAbstractChannel;
begin
  Result := Ch.Impl
end;

function TChannel<T>.TReadOnly.IsClosed: Boolean;
begin
  Result := Impl.IsClosed
end;

function TChannel<T>.TReadOnly.IsNull: Boolean;
begin
  Result := not Assigned(Impl)
end;

class operator TChannel<T>.TReadOnly.LessThan(var a: TCase<T>;
  const b: TReadOnly): Boolean;
var
  Future: IFuture<T, TPendingError>;
  CaseImpl: ICase;
  Index: Integer;
begin
  CaseImpl := a;
  if b.IsNull then
    Exit(False);
  if (CaseImpl.Operation <> ioNotSet) then begin
    if Select([CaseImpl.OnSuccess, CaseImpl.OnError], Index, 0) = wrTimeout then
      raise EReadError.Create('This case already reserved for pending IO operation');
  end;
  Future := b.Impl.ReadPending;
  a.FValueToRead := Future;
  CaseImpl.Operation := ioRead;
  CaseImpl.OnSuccess := Future.OnFullFilled;
  CaseImpl.OnError := Future.OnRejected;
  CaseImpl.ErrorHolder := Future;
  Result := True;
end;

function TChannel<T>.TReadOnly.Read(out A: T): Boolean;
begin
  Result := Impl.Read(A)
end;

function TChannel<T>.TReadOnly.ReadPending: IFuture<T, TPendingError>;
begin
  Result := Impl.ReadPending;
end;

procedure TChannel<T>.TReadOnly.SetDeadlockEsxception(
  const Value: TExceptionClass);
begin
  Impl.SetDeadlockExceptionClass(Value);
end;

{ TChannel<T>.TWriteOnly }

procedure TChannel<T>.TWriteOnly.Close;
begin
  Impl.Close
end;

function TChannel<T>.TWriteOnly.GetDeadlockException: TExceptionClass;
begin
  Result := Impl.GetDeadlockExceptionClass
end;

class operator TChannel<T>.TWriteOnly.Implicit(
  const Ch: TWriteOnly): IAbstractChannel;
begin
  Result := Ch.Impl
end;

function TChannel<T>.TWriteOnly.IsClosed: Boolean;
begin
  Result := Impl.IsClosed
end;

function TChannel<T>.TWriteOnly.IsNull: Boolean;
begin
  Result := not Assigned(Impl)
end;

class operator TChannel<T>.TWriteOnly.LessThan(const a: TWriteOnly;
  var b: TCase<T>): Boolean;
var
  Future: IFuture<T, TPendingError>;
  CaseImpl: ICase;
  Index: Integer;
begin
  CaseImpl := b;
  if a.IsNull then
    Exit(False);
  if (CaseImpl.Operation <> ioNotSet) then begin
    if Select([CaseImpl.OnSuccess, CaseImpl.OnError], Index, 0) = wrTimeout then
      raise EWriteError.Create('This case already reserved for pending IO operation');
  end;
  if not CaseImpl.WriteValueExists then
    raise EWriteError.Create('You must set value for pending write');
  Future := a.Impl.WritePending(b.FValueHolder);
  b.FValueToRead := Future;
  CaseImpl.Operation := ioWrite;
  CaseImpl.OnSuccess := Future.OnFullFilled;
  CaseImpl.OnError := Future.OnRejected;
  CaseImpl.ErrorHolder := Future;
  Result := True;
end;
{var
  Future: IFuture<T, TPendingError>;
begin

  Future := b.Impl.ReadPending;
  a.Impl := TCaseImpl.Create(Future, ioRead, Future.OnFullFilled, Future.OnRejected);
  a.FValueToRead := Future;
  Result := True;
end;   }

procedure TChannel<T>.TWriteOnly.SetDeadlockEsxception(
  const Value: TExceptionClass);
begin
  Impl.SetDeadlockExceptionClass(Value);
end;

function TChannel<T>.TWriteOnly.Write(const A: T): Boolean;
begin
  Result := Impl.Write(A);
end;

function TChannel<T>.TWriteOnly.WritePending(
  const A: T): IFuture<T, TPendingError>;
begin
  Result := Impl.WritePending(A)
end;

{ TSymmetric<T1, T2> }

constructor TSymmetric<T1, T2>.Create(
  const Routine: TSymmetricRoutine<T1, T2>; const A1: T1; const A2: T2);
begin
  Impl := TSymmetricImpl<T1,T2>.Create(Routine, A1, A2)
end;

constructor TSymmetric<T1, T2>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1; const A2: T2);
begin
  Impl := TSymmetricImpl<T1,T2>.Create(Routine, A1, A2)
end;

class operator TSymmetric<T1, T2>.Implicit(
  const A: TSymmetric<T1, T2>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

class operator TSymmetric<T1, T2>.Implicit(
  const A: TSymmetric<T1, T2>): IRawGreenlet;
begin
  Result := A.Impl
end;

procedure TSymmetric<T1, T2>.Join(const RaiseErrors: Boolean);
begin
  Impl.Join(RaiseErrors);
end;

procedure TSymmetric<T1, T2>.Kill;
begin
  Impl.Kill
end;

procedure TSymmetric<T1, T2>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TSymmetric<T1, T2>.Spawn(
  const Routine: TSymmetricRoutine<T1, T2>; const A1: T1;
  const A2: T2): TSymmetric<T1, T2>;
begin
  Result := TSymmetric<T1, T2>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

class function TSymmetric<T1, T2>.Spawn(
  const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1;
  const A2: T2): TSymmetric<T1, T2>;
begin
  Result := TSymmetric<T1, T2>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

{ TSymmetric<T1, T2, T3> }

constructor TSymmetric<T1, T2, T3>.Create(
  const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2;
  const A3: T3);
begin
  Impl := TSymmetricImpl<T1,T2,T3>.Create(Routine, A1, A2, A3);
end;

constructor TSymmetric<T1, T2, T3>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1;
  const A2: T2; const A3: T3);
begin
  Impl := TSymmetricImpl<T1,T2,T3>.Create(Routine, A1, A2, A3);
end;

class operator TSymmetric<T1, T2, T3>.Implicit(
  const A: TSymmetric<T1, T2, T3>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

class operator TSymmetric<T1, T2, T3>.Implicit(
  const A: TSymmetric<T1, T2, T3>): IRawGreenlet;
begin
  Result := A.Impl
end;

procedure TSymmetric<T1, T2, T3>.Join(const RaiseErrors: Boolean);
begin
  Impl.Join(RaiseErrors);
end;

procedure TSymmetric<T1, T2, T3>.Kill;
begin
  Impl.Kill
end;

procedure TSymmetric<T1, T2, T3>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TSymmetric<T1, T2, T3>.Spawn(
  const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2;
  const A3: T3): TSymmetric<T1, T2, T3>;
begin
  Result := TSymmetric<T1, T2, T3>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

class function TSymmetric<T1, T2, T3>.Spawn(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1;
  const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>;
begin
  Result := TSymmetric<T1, T2, T3>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

{ TAsymmetric<Y> }

constructor TAsymmetric<Y>.Create(
  const Routine: TAsymmetricRoutine<Y>);
begin
  Impl := TAsymmetricImpl<Y>.Create(Routine);
end;

constructor TAsymmetric<Y>.Create(
  const Routine: TAsymmetricRoutineStatic<Y>);
begin
  Impl := TAsymmetricImpl<Y>.Create(Routine);
end;

function TAsymmetric<Y>.GetResult(const Block: Boolean): Y;
begin
  Result := Impl.GetResult(Block)
end;

class operator TAsymmetric<Y>.Implicit(const A: TAsymmetric<Y>): IAsymmetric<Y>;
begin
  Result := A.Impl;
end;

procedure TAsymmetric<Y>.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TAsymmetric<Y>.Kill;
begin
  Impl.Kill
end;

procedure TAsymmetric<Y>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class operator TAsymmetric<Y>.Implicit(const A: TAsymmetric<Y>): IRawGreenlet;
begin
  Result := A.Impl;
end;

class function TAsymmetric<Y>.Spawn(
  const Routine: TAsymmetricRoutine<Y>): TAsymmetric<Y>;
begin
  Result := TAsymmetric<Y>.Create(Routine);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<Y>): TAsymmetric<Y>;
begin
  Result := TAsymmetric<Y>.Create(Routine);
  Result.Impl.Switch;
end;

{$IFDEF DCC}
class function TAsymmetric<Y>.Spawn<T>(const Routine: TAsymmetricRoutine<T, Y>; const A: T): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T,Y>.Create(Routine, A);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T>(const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T,Y>.Create(Routine, A);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1, T2>(const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,Y>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1, T2>(const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1; const A2: T2): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,Y>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1, T2, T3>(const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,T3,Y>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1, T2, T3>(const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1; const A2: T2; const A3: T3): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,T3,Y>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1,T2,T3,T4>(const Routine: TAsymmetricRoutine<T1,T2,T3,T4,Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,T3,T4,Y>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

class function TAsymmetric<Y>.Spawn<T1,T2,T3,T4>(const Routine: TAsymmetricRoutineStatic<T1,T2,T3,T4,Y>; const A1: T1; const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1,T2,T3,T4,Y>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

{$ENDIF}

class operator TAsymmetric<Y>.Implicit(const A: TAsymmetric<Y>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

{ TAsymmetric<T, Y> }

constructor TAsymmetric<T, Y>.Create(const Routine: TAsymmetricRoutine<T, Y>;
  const A: T);
begin
  Impl := TAsymmetricImpl<T, Y>.Create(Routine, A)
end;

constructor TAsymmetric<T, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T);
begin
  Impl := TAsymmetricImpl<T, Y>.Create(Routine, A)
end;

function TAsymmetric<T, Y>.GetResult(const Block: Boolean): Y;
begin
  Result := Impl.GetResult(Block)
end;

class operator TAsymmetric<T, Y>.Implicit(
  const A: TAsymmetric<T, Y>): IAsymmetric<Y>;
begin
  Result := A.Impl
end;

procedure TAsymmetric<T, Y>.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TAsymmetric<T, Y>.Kill;
begin
  Impl.Kill
end;

procedure TAsymmetric<T, Y>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class operator TAsymmetric<T, Y>.Implicit(
  const A: TAsymmetric<T, Y>): IRawGreenlet;
begin
  Result := A.Impl;
end;

class function TAsymmetric<T, Y>.Spawn(const Routine: TAsymmetricRoutine<T, Y>;
  const A: T): TAsymmetric<T, Y>;
begin
  Result := TAsymmetric<T, Y>.Create(Routine, A);
  Result.Impl.Switch;
end;

class function TAsymmetric<T, Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<T, Y>;
begin
  Result := TAsymmetric<T, Y>.Create(Routine, A);
  Result.Impl.Switch;
end;

class operator TAsymmetric<T, Y>.Implicit(const A: TAsymmetric<T, Y>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

{ TAsymmetric<T1, T2, Y> }

constructor TAsymmetric<T1, T2, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1;
  const A2: T2);
begin
  Impl := TAsymmetricImpl<T1, T2, Y>.Create(Routine, A1, A2)
end;

constructor TAsymmetric<T1, T2, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1;
  const A2: T2);
begin
  Impl := TAsymmetricImpl<T1, T2, Y>.Create(Routine, A1, A2)
end;

function TAsymmetric<T1, T2, Y>.GetResult(const Block: Boolean): Y;
begin
  Result := Impl.GetResult(Block)
end;

class operator TAsymmetric<T1, T2, Y>.Implicit(
  const A: TAsymmetric<T1, T2, Y>): IRawGreenlet;
begin
  Result := A.Impl
end;

class operator TAsymmetric<T1, T2, Y>.Implicit(
  const A: TAsymmetric<T1, T2, Y>): IAsymmetric<Y>;
begin
  Result := A.Impl
end;

procedure TAsymmetric<T1, T2, Y>.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TAsymmetric<T1, T2, Y>.Kill;
begin
  Impl.Kill
end;

procedure TAsymmetric<T1, T2, Y>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TAsymmetric<T1, T2, Y>.Spawn(
  const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1;
  const A2: T2): TAsymmetric<T1, T2, Y>;
begin
  Result := TAsymmetric<T1, T2, Y>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

class function TAsymmetric<T1, T2, Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1;
  const A2: T2): TAsymmetric<T1, T2, Y>;
begin
  Result := TAsymmetric<T1, T2, Y>.Create(Routine, A1, A2);
  Result.Impl.Switch;
end;

class operator TAsymmetric<T1, T2, Y>.Implicit(
  const A: TAsymmetric<T1, T2, Y>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

{ TSymmetric }

constructor TSymmetric.Create(const Routine: TSymmetricRoutine);
begin
  Impl := TSymmetricImpl.Create(Routine);
end;

constructor TSymmetric.Create(
  const Routine: TSymmetricRoutineStatic);
begin
  Impl := TSymmetricImpl.Create(Routine);
end;

class operator TSymmetric.Implicit(const A: TSymmetric): IRawGreenlet;
begin
  Result := A.Impl
end;

class operator TSymmetric.Implicit(const A: TSymmetric): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

procedure TSymmetric.Join(const RaiseErrors: Boolean);
begin
  Impl.Join(RaiseErrors)
end;

procedure TSymmetric.Kill;
begin
  Impl.Kill
end;

procedure TSymmetric.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TSymmetric.Spawn(const Routine: TSymmetricRoutine): TSymmetric;
begin
  Result := TSymmetric.Create(Routine);
  Result.Impl.Switch;
end;

class function TSymmetric.Spawn(
  const Routine: TSymmetricRoutineStatic): TSymmetric;
begin
  Result := TSymmetric.Create(Routine);
  Result.Impl.Switch;
end;

{ TAsymmetric<T1, T2, T3, Y> }

constructor TAsymmetric<T1, T2, T3, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2;
  const A3: T3);
begin
  Impl := TAsymmetricImpl<T1, T2, T3, Y>.Create(Routine, A1, A2, A3)
end;

constructor TAsymmetric<T1, T2, T3, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1;
  const A2: T2; const A3: T3);
begin
  Impl := TAsymmetricImpl<T1, T2, T3, Y>.Create(Routine, A1, A2, A3)
end;

function TAsymmetric<T1, T2, T3, Y>.GetResult(const Block: Boolean): Y;
begin
  Result := Impl.GetResult(Block)
end;

class operator TAsymmetric<T1, T2, T3, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, Y>): IRawGreenlet;
begin
  Result := A.Impl
end;

class operator TAsymmetric<T1, T2, T3, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, Y>): IAsymmetric<Y>;
begin
  Result := A.Impl
end;

procedure TAsymmetric<T1, T2, T3, Y>.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TAsymmetric<T1, T2, T3, Y>.Kill;
begin
  Impl.Kill
end;

procedure TAsymmetric<T1, T2, T3, Y>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TAsymmetric<T1, T2, T3, Y>.Spawn(
  const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2;
  const A3: T3): TAsymmetric<T1, T2, T3, Y>;
begin
  Result := TAsymmetric<T1, T2, T3, Y>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

class function TAsymmetric<T1, T2, T3, Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1;
  const A2: T2; const A3: T3): TAsymmetric<T1, T2, T3, Y>;
begin
  Result := TAsymmetric<T1, T2, T3, Y>.Create(Routine, A1, A2, A3);
  Result.Impl.Switch;
end;

class operator TAsymmetric<T1, T2, T3, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, Y>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

{ TAsymmetric<T1, T2, T3, T4, Y> }

constructor TAsymmetric<T1, T2, T3, T4, Y>.Create(
  const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4);
begin
  Impl := TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4)
end;

constructor TAsymmetric<T1, T2, T3, T4, Y>.Create(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4);
begin
  Impl := TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4)
end;

function TAsymmetric<T1, T2, T3, T4, Y>.GetResult(const Block: Boolean): Y;
begin
  Result := Impl.GetResult(Block)
end;

class operator TAsymmetric<T1, T2, T3, T4, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, T4, Y>): IRawGreenlet;
begin
  Result := A.Impl
end;

class operator TAsymmetric<T1, T2, T3, T4, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, T4, Y>): IAsymmetric<Y>;
begin
  Result := A.Impl
end;

procedure TAsymmetric<T1, T2, T3, T4, Y>.Join(const RaiseErrors: Boolean);
begin
  Greenlets.Join([Self], INFINITE, RaiseErrors)
end;

procedure TAsymmetric<T1, T2, T3, T4, Y>.Kill;
begin
  Impl.Kill
end;

procedure TAsymmetric<T1, T2, T3, T4, Y>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TAsymmetric<T1, T2, T3, T4, Y>.Spawn(
  const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TAsymmetric<T1, T2, T3, T4, Y>;
begin
  Result := TAsymmetric<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

class function TAsymmetric<T1, T2, T3, T4, Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TAsymmetric<T1, T2, T3, T4, Y>;
begin
  Result := TAsymmetric<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

class operator TAsymmetric<T1, T2, T3, T4, Y>.Implicit(
  const A: TAsymmetric<T1, T2, T3, T4, Y>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

{ TGenerator<T> }

constructor TGenerator<T>.Create(const Routine: TSymmetricRoutine);
begin
  Impl := TGeneratorImpl<T>.Create(Routine);
end;

constructor TGenerator<T>.Create(const Routine: TSymmetricArgsRoutine;
  const Args: array of const);
begin
  Impl := TGeneratorImpl<T>.Create(Routine, Args);
end;

constructor TGenerator<T>.Create(const Routine: TSymmetricArgsStatic;
  const Args: array of const);
begin
  Impl := TGeneratorImpl<T>.Create(Routine, Args);
end;

function TGenerator<T>.GetEnumerator: GInterfaces.TEnumerator<T>;
begin
  Result := Impl.GetEnumerator
end;

procedure TGenerator<T>.Setup(const Args: array of const);
begin
  Impl.Setup(Args);
end;

class procedure TGenerator<T>.Yield(const Value: T);
begin
  TGeneratorImpl<T>.Yield(Value)
end;

{ TGreenThread }

function TGreenThread.Asymmetrics<Y>: TAsymmetricFactory<Y>;
var
  Key: string;
  Hash: TObjectDictionary<string, TObject>;
begin
  Key := TAsymmetricFactory<Y>.ClassName;
  Hash := TObjectDictionary<string, TObject>(FHash);
  if Hash.ContainsKey(Key) then begin
    Result := TAsymmetricFactory<Y>(Hash[Key]);
  end
  else begin
    Result := TAsymmetricFactory<Y>.Create(DefHub(Self));
    Hash.Add(Key, Result)
  end;
end;

constructor TGreenThread.Create;
begin
  FOnTerminate := TGevent.Create(True);
  inherited Create(False);
  FSymmetrics := TSymmetricFactory.Create(DefHub(Self));
  FHash := TObjectDictionary<string, TObject>.Create([doOwnsValues]);
  AtomicIncrement(NumberOfInstances);
end;

destructor TGreenThread.Destroy;
begin
  Kill(True);
  FOnTerminate.Free;
  if Assigned(FHub) then begin
    FHub.Free;
  end;
  FSymmetrics.Free;
  FHash.Free;
  AtomicDecrement(NumberOfInstances);
  inherited;
end;

procedure TGreenThread.DoAbort;
begin
  Abort
end;

procedure TGreenThread.Execute;
var
  Joiner: TJoiner;
begin
  FHub := DefHub;
  Joiner := GetJoiner(FHub);
  try
    try
      FHub.Loop(Self.ExitCond);
    finally
      // who did not have time to reschedule - we kill
      // since otherwise, ambiguities appear in the logic
      Joiner.KillAll;
      TRawGreenletPimpl.ClearContexts;
    end;
  finally
    FOnTerminate.SetEvent;
  end;
end;

function TGreenThread.ExitCond: Boolean;
begin
  Result := Terminated
end;

procedure TGreenThread.Kill(const GreenBlock: Boolean);
begin
  if FOnTerminate.WaitFor(0) = wrSignaled then
    Exit;
  DefHub(Self).EnqueueTask(Self.DoAbort);
  if GreenBlock then
    FOnTerminate.WaitFor
end;

function TGreenThread.Symmetrics: TSymmetricFactory;
begin
  Result := FSymmetrics
end;

{ TGreenGroup<KEY> }

procedure TGreenGroup<KEY>.Clear;
begin
  GetImpl.Clear
end;

function TGreenGroup<KEY>.Copy: TGreenGroup<KEY>;
begin
  Result.Impl := Self.GetImpl.Copy
end;

function TGreenGroup<KEY>.Count: Integer;
begin
  Result := GetImpl.Count
end;

function TGreenGroup<KEY>.GetImpl: IGreenGroup<KEY>;
begin
  if not Assigned(Impl) then
    Impl := TGreenGroupImpl<KEY>.Create;
  Result := Impl;
end;

function TGreenGroup<KEY>.GetValue(const Key: KEY): IRawGreenlet;
begin
  Result := GetImpl.GetValue(Key)
end;

function TGreenGroup<KEY>.IsEmpty: Boolean;
begin
  Result := GetImpl.IsEmpty
end;

function TGreenGroup<KEY>.Join(Timeout: LongWord; const RaiseError: Boolean): Boolean;
begin
  Result := GetImpl.Join(Timeout, RaiseError);
end;

procedure TGreenGroup<KEY>.KillAll;
begin
  GetImpl.KillAll
end;

procedure TGreenGroup<KEY>.SetValue(const Key: KEY; G: IRawGreenlet);
begin
  GetImpl.SetValue(Key, G)
end;

{ TFanOut<T> }

constructor TFanOut<T>.Make(const Input: TChannel<T>.TReadOnly);
begin
  Self.Impl := TFanOutImpl<T>.Create(Input.Impl);
end;

function TFanOut<T>.Inflate(const BufSize: Integer): TChannel<T>.TReadOnly;
begin
  Result.Impl := Self.Impl.Inflate(BufSize)
end;

{ TSmartPointer<T> }

class operator TSmartPointer<T>.Implicit(A: TSmartPointer<T>): T;
var
  Obj: TObject absolute Result;
begin
  if IsClass then begin
    if Assigned(A.FObjRef) then
      Obj := A.FObjRef.GetValue
    else
      Obj := nil;
  end
  else begin
    Result := A.FRef
  end;
end;

function TSmartPointer<T>.Get: T;
var
  Obj: TObject absolute Result;
begin
  Result := FRef;
  if IsClass then
    if Assigned(FObjRef) then
      Obj := FObjRef.GetValue
    else
      Obj := nil
end;

class operator TSmartPointer<T>.Implicit(A: T): TSmartPointer<T>;
var
  Obj: TObject absolute A;
begin
  if IsClass then begin
    Result.FObjRef := GC(Obj)
  end
  else begin
    Result.FRef := A
  end;
end;

class function TSmartPointer<T>.IsClass: Boolean;
var
  ti: PTypeInfo;
begin
  ti := TypeInfo(T);
  Result := ti.Kind = tkClass;
end;

{ TSymmetricFactory }

constructor TSymmetricFactory.Create(Hub: THub);
begin
  FHub := Hub;
end;

function TSymmetricFactory.Spawn(
  const Routine: TSymmetricRoutineStatic): TSymmetric;
begin
  Result.Impl := TSymmetricImpl.Create(Routine, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn(const Routine: TSymmetricRoutine): TSymmetric;
begin
  Result.Impl := TSymmetricImpl.Create(Routine, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2, T3, T4>(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>;
begin
  Result.Impl := TSymmetricImpl<T1, T2, T3, T4>.Create(Routine, A1, A2, A3, A4, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2, T3>(
  const Routine: TSymmetricRoutine<T1, T2, T3>; const A1: T1; const A2: T2;
  const A3: T3): TSymmetric<T1, T2, T3>;
begin
  Result.Impl := TSymmetricImpl<T1, T2, T3>.Create(Routine, A1, A2, A3, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2, T3, T4>(
  const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2;
  const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>;
begin
  Result.Impl := TSymmetricImpl<T1, T2, T3, T4>.Create(Routine, A1, A2, A3, A4, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2, T3>(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3>; const A1: T1;
  const A2: T2; const A3: T3): TSymmetric<T1, T2, T3>;
begin
  Result.Impl := TSymmetricImpl<T1, T2, T3>.Create(Routine, A1, A2, A3, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2>(
  const Routine: TSymmetricRoutine<T1, T2>; const A1: T1;
  const A2: T2): TSymmetric<T1, T2>;
begin
  Result.Impl := TSymmetricImpl<T1, T2>.Create(Routine, A1, A2, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T1, T2>(
  const Routine: TSymmetricRoutineStatic<T1, T2>; const A1: T1;
  const A2: T2): TSymmetric<T1, T2>;
begin
  Result.Impl := TSymmetricImpl<T1, T2>.Create(Routine, A1, A2, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T>(const Routine: TSymmetricRoutine<T>;
  const A: T): TSymmetric<T>;
begin
  Result.Impl := TSymmetricImpl<T>.Create(Routine, A, FHub);
  Result.Run;
end;

function TSymmetricFactory.Spawn<T>(const Routine: TSymmetricRoutineStatic<T>;
  const A: T): TSymmetric<T>;
begin
  Result.Impl := TSymmetricImpl<T>.Create(Routine, A, FHub);
  Result.Run;
end;

{ TSymmetric<T1, T2, T3, T4> }

constructor TSymmetric<T1, T2, T3, T4>.Create(
  const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2;
  const A3: T3; const A4: T4);
begin
  Impl := TSymmetricImpl<T1,T2,T3,T4>.Create(Routine, A1, A2, A3, A4);
end;

constructor TSymmetric<T1, T2, T3, T4>.Create(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4);
begin
  Impl := TSymmetricImpl<T1,T2,T3,T4>.Create(Routine, A1, A2, A3, A4);
end;

class operator TSymmetric<T1, T2, T3, T4>.Implicit(
  const A: TSymmetric<T1, T2, T3, T4>): TGevent;
begin
  Result := A.Impl.GetOnTerminate
end;

class operator TSymmetric<T1, T2, T3, T4>.Implicit(
  const A: TSymmetric<T1, T2, T3, T4>): IRawGreenlet;
begin
  Result := A.Impl
end;

procedure TSymmetric<T1, T2, T3, T4>.Join(const RaiseErrors: Boolean);
begin
  Impl.Join(RaiseErrors);
end;

procedure TSymmetric<T1, T2, T3, T4>.Kill;
begin
  Impl.Kill
end;

procedure TSymmetric<T1, T2, T3, T4>.Run;
begin
  if Impl.GetState = gsReady then
    Impl.GetProxy.Pulse
end;

class function TSymmetric<T1, T2, T3, T4>.Spawn(
  const Routine: TSymmetricRoutine<T1, T2, T3, T4>; const A1: T1; const A2: T2;
  const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>;
begin
  Result := TSymmetric<T1, T2, T3, T4>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

class function TSymmetric<T1, T2, T3, T4>.Spawn(
  const Routine: TSymmetricRoutineStatic<T1, T2, T3, T4>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TSymmetric<T1, T2, T3, T4>;
begin
  Result := TSymmetric<T1, T2, T3, T4>.Create(Routine, A1, A2, A3, A4);
  Result.Impl.Switch;
end;

{ TAsymmetricFactory<Y> }

constructor TAsymmetricFactory<Y>.Create(Hub: THub);
begin
  FHub := Hub
end;

function TAsymmetricFactory<Y>.Spawn(
  const Routine: TAsymmetricRoutineStatic<Y>): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<Y>.Create(Routine, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn(
  const Routine: TAsymmetricRoutine<Y>): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<Y>.Create(Routine, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2, T3, T4>(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2, T3>(
  const Routine: TAsymmetricRoutine<T1, T2, T3, Y>; const A1: T1; const A2: T2;
  const A3: T3): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, T3, Y>.Create(Routine, A1, A2, A3, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2, T3, T4>(
  const Routine: TAsymmetricRoutine<T1, T2, T3, T4, Y>; const A1: T1;
  const A2: T2; const A3: T3; const A4: T4): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, T3, T4, Y>.Create(Routine, A1, A2, A3, A4, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2, T3>(
  const Routine: TAsymmetricRoutineStatic<T1, T2, T3, Y>; const A1: T1;
  const A2: T2; const A3: T3): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, T3, Y>.Create(Routine, A1, A2, A3, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2>(
  const Routine: TAsymmetricRoutine<T1, T2, Y>; const A1: T1;
  const A2: T2): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, Y>.Create(Routine, A1, A2, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T1, T2>(
  const Routine: TAsymmetricRoutineStatic<T1, T2, Y>; const A1: T1;
  const A2: T2): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T1, T2, Y>.Create(Routine, A1, A2, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T>(const Routine: TAsymmetricRoutine<T, Y>;
  const A: T): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T, Y>.Create(Routine, A, FHub);
  Result.Run;
end;

function TAsymmetricFactory<Y>.Spawn<T>(
  const Routine: TAsymmetricRoutineStatic<T, Y>; const A: T): TAsymmetric<Y>;
begin
  Result.Impl := TAsymmetricImpl<T, Y>.Create(Routine, A, FHub);
  Result.Run;
end;

{ TGCondVariable }

procedure TGCondVariable.Broadcast;
begin
  GetImpl.Broadcast
end;

function TGCondVariable.GetImpl: IGCondVariable;
begin
  if not Assigned(Impl) then
    Impl := TGCondVariableImpl.Create;
  Result := Impl;
end;

class function TGCondVariable.Make(
  aExternalMutex: TCriticalSection): TGCondVariable;
begin
  Result.Impl := TGCondVariableImpl.Create(aExternalMutex);
end;

procedure TGCondVariable.Signal;
begin
  GetImpl.Signal
end;

procedure TGCondVariable.Wait(aUnlocking: TCriticalSection);
begin
  GetImpl.Wait(aUnlocking);
end;

procedure TGCondVariable.Wait(aSpinUnlocking: TPasMPSpinLock);
begin
  GetImpl.Wait(aSpinUnlocking);
end;

{ TGSemaphore }

procedure TGSemaphore.Acquire;
begin
  Impl.Acquire
end;

function TGSemaphore.Limit: LongWord;
begin
  Result := Impl.Limit
end;

class function TGSemaphore.Make(Limit: LongWord): TGSemaphore;
begin
  Result.Impl := TGSemaphoreImpl.Create(Limit)
end;

procedure TGSemaphore.Release;
begin
  Impl.Release
end;

function TGSemaphore.Value: LongWord;
begin
  Result := Impl.Value
end;

{ TGMutex }

procedure TGMutex.Acquire;
begin
  GetImpl.Acquire;
end;

function TGMutex.GetImpl: IGMutex;
begin
  if not Assigned(Impl) then
    Impl := TGMutexImpl.Create;
  Result := Impl
end;

procedure TGMutex.Release;
begin
  GetImpl.Release
end;

{ TGQueue<T> }

procedure TGQueue<T>.Clear;
begin
  Impl.Clear
end;

function TGQueue<T>.Count: Integer;
begin
  Result := Impl.Count
end;

procedure TGQueue<T>.Dequeue(out A: T);
begin
  Impl.Dequeue(A)
end;

procedure TGQueue<T>.Enqueue(A: T);
begin
  Impl.Enqueue(A)
end;

class function TGQueue<T>.Make(MaxCount: LongWord): TGQueue<T>;
begin
  Result.Impl := TGQueueImpl<T>.Create(MaxCount);
end;

{ TFuturePromise<RESULT, STATUS> }

function TFuturePromise<RESULT, STATUS>.GetFuture: IFuture<RESULT, STATUS>;
begin
  if not Assigned(FFuture) then
    Init;
  Result := FFuture;
end;

function TFuturePromise<RESULT, STATUS>.GetPromise: IPromise<RESULT, STATUS>;
begin
  if not Assigned(FPromise) then
    Init;
  Result := FPromise;
end;

procedure TFuturePromise<RESULT, STATUS>.Init;
var
  F: TFutureImpl<RESULT, STATUS>;
begin
  F := TFutureImpl<RESULT, STATUS>.Create;
  FFuture := F;
  FPromise := TPromiseImpl<RESULT, STATUS>.Create(F);
end;

{ TCase<T> }

class operator TCase<T>.Implicit(var A: TCase<T>): ICase;
begin
  if not Assigned(A.Impl) then
    A.Impl := TCaseImpl.Create;
  Result := A.Impl
end;

class operator TCase<T>.Equal(a: TCase<T>; b: T): Boolean;
var
  Comparer: IComparer<T>;
begin
  Comparer := TComparer<T>.Default;
  Result := Comparer.Compare(a, b) = 0
end;

class operator TCase<T>.Equal(a: T; b: TCase<T>): Boolean;
var
  Comparer: IComparer<T>;
  val: T;
begin
  Comparer := TComparer<T>.Default;
  Result := Comparer.Compare(a, b) = 0
end;

function TCase<T>.Get: T;
begin
  Result := Self;
end;

class operator TCase<T>.Implicit(const A: T): TCase<T>;
begin
  Result.Impl := TCaseImpl.Create;
  Result.Impl.WriteValueExists := True;
  Result.FValueHolder := A;
end;

class operator TCase<T>.Implicit(const A: TCase<T>): T;
begin
  if Assigned(A.Impl) then begin
    if A.Impl.GetOperation = ioRead then begin
      Result := A.FValueToRead.GetResult
    end
    else begin
      if A.FValueToWrite.OnFullFilled.WaitFor(0) = wrSignaled then
        Result := A.FValueToWrite.GetResult
      else
        raise EReadError.Create('You try access to value that is not completed in write operation');
    end;
  end
  else
    raise EReadError.Create('Value is empty. Start read/write operation');
end;

{ TCaseSet }

class operator TCaseSet.Add(a: TCaseSet; b: ICase): TCaseSet;
begin
  Result.Collection := a.GetCollection.Copy;
  Result.Collection.Append(b, False);
end;

class operator TCaseSet.Add(a, b: TCaseSet): TCaseSet;
begin
  Result.Collection := a.GetCollection.Copy;
  Result.Collection.Append(b.GetCollection, False);
end;

procedure TCaseSet.Clear;
begin
  GetCollection.Clear;
end;

function TCaseSet.GetCollection: ICollection<ICase>;
begin
  if not Assigned(Collection) then
    Collection := TCollectionImpl<ICase>.Create;
  Result := Collection;
end;

function TCaseSet.Has(a: ICase): Boolean;
var
  I: ICase;
begin
  Result := False;
  for I in GetCollection do
    if I = a then
      Exit(True);
end;

class operator TCaseSet.In(a: ICase; b: TCaseSet) : Boolean;
begin
  Result := b.Has(a)
end;

class operator TCaseSet.Implicit(const A: ICase): TCaseSet;
begin
  Result.GetCollection.Append(A, False)
end;

function TCaseSet.IsEmpty: Boolean;
begin
  Result := GetCollection.Count = 0
end;

class function TCaseSet.Make(const Cases: array of ICase): TCaseSet;
var
  I: ICase;
begin
  for I in Cases do begin
    Result.GetCollection.Append(I, False)
  end;
end;

class operator TCaseSet.Subtract(a, b: TCaseSet): TCaseSet;
var
  I: ICase;
begin
  Result.Collection := a.GetCollection.Copy;
  for I in b.GetCollection do
    Result.Collection.Remove(I);
end;

class operator TCaseSet.Subtract(a: TCaseSet; b: ICase): TCaseSet;
begin
  Result.Collection := a.GetCollection.Copy;
  Result.GetCollection.Remove(b);
end;


initialization

end.

