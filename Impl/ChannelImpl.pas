unit ChannelImpl;

interface
uses {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections, System.Rtti{$ENDIF},
  GInterfaces, Hub, Gevent, PasMP, Classes, Greenlets, SyncObjs,
  GarbageCollector, SysUtils;

type

  ILightGevent = interface
    procedure SetEvent(const Async: Boolean = False);
    procedure WaitEvent;
    procedure Associate(Other: ILightGevent; Index: Integer);
    function GetIndex: Integer;
    procedure SetIndex(Value: Integer);
    function GetContext: Pointer;
    function GetInstance: Pointer;
  end;

  TLightGevent = class(TInterfacedObject, ILightGevent)
  strict private
    FSignal: Boolean;
    FLock: TPasMPSpinLock;
    FContext: Pointer;
    FHub: TCustomHub;
    FWaitEventRoutine: TThreadMethod;
    FIndex: Integer;
    FAssociate: ILightGevent;
    FAssociateIndex: Integer;
    FWaiting: Boolean;
    procedure Lock; inline;
    procedure Unlock; inline;
    procedure ThreadedWaitEvent;
    procedure GreenletWaitEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetEvent(const Async: Boolean = False);
    procedure WaitEvent;
    procedure Associate(Other: ILightGevent; Index: Integer);
    function GetIndex: Integer;
    procedure SetIndex(Value: Integer);
    function GetContext: Pointer;
    function GetInstance: Pointer;
  end;

  IAbstractContract = interface
    ['{E27E9F47-02E7-4F82-BB5E-36FE142BF55B}']
    procedure FixCurContext;
    function IsMyCtx: Boolean;
    procedure Lock;
    procedure Unlock;
  end;

  IContract<T> = interface(IAbstractContract)
    ['{4A32E6FB-1E6C-462F-BF8B-0503270D162A}']
    function Push(const A: T; Ref: IGCObject): Boolean;
    function Pop(out A: T; out Ref:  IGCObject): Boolean;
    function IsEmpty: Boolean;
  end;

  TLightCondVar = class
  type
    TSyncMethod = (smDefault, smForceAsync, smForceSync);
  strict private
  type
    TWaitRoutine = procedure(Unlocking: TPasMPSpinLock) of object;
    TSyncRoutine = procedure(const Method: TSyncMethod=smDefault) of object;
  var
    FItems: TList;
    FLock: TPasMPSpinLock;
    FAsync: Boolean;
    FWaitRoutine: TWaitRoutine;
    FSignalRoutine: TSyncRoutine;
    FBroadcastRoutine: TSyncRoutine;
    procedure Clean;
    procedure LockedWait(Unlocking: TPasMPSpinLock);
    procedure LockedSignal(const Method: TSyncMethod);
    procedure LockedBroadcast(const Method: TSyncMethod);
    procedure UnLockedWait(Unlocking: TPasMPSpinLock);
    procedure UnLockedSignal(const Method: TSyncMethod);
    procedure UnLockedBroadcast(const Method: TSyncMethod);
  protected
    procedure Lock; inline;
    procedure Unlock; inline;
    procedure Enqueue(E: TLightGevent);
    function Dequeue(out E: TLightGevent): Boolean;
  public
    constructor Create(const Async: Boolean; const Locked: Boolean);
    destructor Destroy; override;
    procedure Wait(Unlocking: TPasMPSpinLock = nil);
    procedure Signal(const Method: TSyncMethod=smDefault);
    procedure Broadcast(const Method: TSyncMethod=smDefault);
    procedure Assign(Source: TLightCondVar);
  end;

  TAbstractContractImpl = class(TInterfacedObject, IAbstractContract)
  strict private
    FLock: TPasMPSpinLock;
    FContext: Pointer;
    FHub: TCustomHub;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Lock;
    procedure Unlock;
    procedure FixCurContext;
    function IsMyCtx: Boolean;
  end;

  TContractImpl<T> = class(TAbstractContractImpl, IContract<T>)
  strict private
    FValue: T;
    FDefValue: T;
    FIsEmpty: Boolean;
    FSmartObj: IGCObject;
  public
    constructor Create;
    destructor Destroy; override;
    function Push(const A: T; Ref: IGCObject): Boolean;
    function Pop(out A: T; out Ref: IGCObject): Boolean;
    function IsEmpty: Boolean;
  end;

  THubRefDictionary = TPasMPHashTable<THub, Integer>;

  TLocalContextService = class
  strict private
    FRef: IGCObject;
    FDeadLockExceptionClass: TExceptionClass;
    function GetDeadLockExceptionClass: TExceptionClass;
  public
    function Refresh(A: TObject): IGCObject;
    property DeadLockExceptionClass: TExceptionClass read GetDeadLockExceptionClass
      write FDeadLockExceptionClass;
  end;

  TLeaveLockLogger = class
  strict private
  const
    MAX_COUNT_FACTOR = 5;
  var
    FCounter: Integer;
  public
    procedure Check(const Msg: string);
  end;

  TOnDieEvent = procedure(ID: Integer) of object;

  ILiveToken = interface
    ['{7A8A9717-8D55-439B-B142-80F62BC6A613}']
    procedure Die;
    procedure Deactivate;
    function IsLive: Boolean;
  end;

  IContextRef = interface
    procedure SetActive(const Value: Boolean);
    function GetActive: Boolean;
    function GetRefCount: Integer;
    function AddRef(Accum: Integer = 1): Integer;
    function Release(Accum: Integer = 1): Integer;
  end;

  TContextRef = class(TInterfacedObject, IContextRef)
  strict private
    FActive: Boolean;
    FRefCount: Integer;
    FIsOwner: Boolean;
  public
    constructor Create(const Active: Boolean = True; const IsOwnerContext: Boolean = False);
    procedure SetActive(const Value: Boolean);
    function GetActive: Boolean;
    function GetRefCount: Integer;
    function AddRef(Accum: Integer = 1): Integer;
    function Release(Accum: Integer = 1): Integer;
  end;

  TContextHashTable = {$IFDEF DCC}
               TDictionary<NativeUInt, IContextRef>
               {$ELSE}
               TFPGMap<NativeUInt, IContextRef>
               {$ENDIF};

  TOnGetLocalService = function: TLocalContextService of object;
  TOnCheckDeadLock = function(const AsReader: Boolean; const AsWriter: Boolean;
       const RaiseError: Boolean = True; const Lock: Boolean = True): Boolean of object;

  TCustomChannel<T> = class(TInterfacedObject)
  type
    TPendingOperations<Y> = class
    strict private
      FPendingReader: IRawGreenlet;
      FPendingWriter: IRawGreenlet;
      FReaderFuture: IFuture<Y, TPendingError>;
      FWriterFuture: IFuture<Y, TPendingError>;
    public
      destructor Destroy; override;
      property PendingReader: IRawGreenlet read FPendingReader write FPendingReader;
      property PendingWriter: IRawGreenlet read FPendingWriter write FPendingWriter;
      property ReaderFuture: IFuture<Y, TPendingError> read FReaderFuture write FReaderFuture;
      property WriterFuture: IFuture<Y, TPendingError> read FWriterFuture write FWriterFuture;
    end;
  strict private
    FGuid: string;
    FIsClosed: Integer;
    FIsObjectTyp: Boolean;
    function GetLocalContextKey: string;
    function GetLocalPendingKey: string;
  private
  var
    FReaders: TContextHashTable;
    FWriters: TContextHashTable;
    FDefValue: T;
  protected
  var
    FLock: TPasMPSpinLock;
    FReadersNum: Integer;
    FWritersNum: Integer;
    FOwnerContext: NativeUInt;
    class function GetContextUID: NativeUInt;
    property Guid: string read FGuid;
    function GetLocalService: TLocalContextService;
    function GetLocalPendings: TPendingOperations<T>;
    property IsObjectTyp: Boolean read FIsObjectTyp;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    procedure BroadcastAll(const Method: TLightCondVar.TSyncMethod); virtual; abstract;
    function CheckDeadLock(const AsReader: Boolean; const AsWriter: Boolean;
       const RaiseError: Boolean = True; const Lock: Boolean = True): Boolean;
    procedure CheckLeaveLock;
    function InternalAddRef(const AsReader: Boolean; const AsWriter: Boolean): Integer;
    function InternalRelease(const AsReader: Boolean; const AsWriter: Boolean): Integer;
    function InternalRead(out A: T; ReleaseFactor: Integer): Boolean; dynamic; abstract;
    function InternalWrite(const A: T; ReleaseFactor: Integer): Boolean; dynamic; abstract;
    procedure AsyncRead(const Promise: IPromise<T, TPendingError>; const ReleaseFactor: Integer);
    procedure AsyncWrite(const Promise: IPromise<T, TPendingError>; const ReleaseFactor: Integer;
      const Value: TSmartPointer<T>);
  public
    constructor Create;
    destructor Destroy; override;
    // channel interface
    function  Read(out A: T): Boolean;
    function  Write(const A: T): Boolean;
    function  ReadPending: IFuture<T, TPendingError>;
    function  WritePending(const A: T): IFuture<T, TPendingError>;
    procedure Close; dynamic;
    function  IsClosed: Boolean;
    // generator-like
    function Get: T;
    function GetEnumerator: TEnumerator<T>;
    function GetBufSize: LongWord; dynamic; abstract;
    procedure AccumRefs(ReadRefCount, WriteRefCount: Integer);
    procedure ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
    procedure SetDeadlockExceptionClass(Cls: TExceptionClass);
    function  GetDeadlockExceptionClass: TExceptionClass;
  end;

  TReadOnlyChannel<T> = class(TInterfacedObject, IReadOnly<T>)
  strict private
    FParent: TCustomChannel<T>;
  protected
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(Parent: TCustomChannel<T>);
    function Read(out A: T): Boolean;
    function ReadPending: IFuture<T, TPendingError>;
    procedure Close;
    function IsClosed: Boolean;
    function GetEnumerator: TEnumerator<T>;
    function Get: T;
    function GetBufSize: LongWord;
    procedure AccumRefs(ReadRefCount, WriteRefCount: Integer);
    procedure ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
    procedure SetDeadlockExceptionClass(Cls: TExceptionClass);
    function  GetDeadlockExceptionClass: TExceptionClass;
  end;

  TWriteOnlyChannel<T> = class(TInterfacedObject, IWriteOnly<T>)
  strict private
    FParent: TCustomChannel<T>;
  protected
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(Parent: TCustomChannel<T>);
    function Write(const A: T): Boolean;
    function WritePending(const A: T): IFuture<T, TPendingError>;
    procedure Close;
    function IsClosed: Boolean;
    function GetBufSize: LongWord;
    procedure AccumRefs(ReadRefCount, WriteRefCount: Integer);
    procedure ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
    procedure SetDeadlockExceptionClass(Cls: TExceptionClass);
    function  GetDeadlockExceptionClass: TExceptionClass;
  end;

  TSingleThreadSyncChannel<T> = class;
  TMultiThreadSyncChannel<T> = class;

  TSyncChannel<T> = class(TCustomChannel<T>, IChannel<T>)
  private
  type
    TOnRead = function(out A: T; ReleaseFactor: Integer): Boolean of object;
    TOnWrite = function(const A: T; ReleaseFactor: Integer): Boolean of object;
    TOnBroadcast = procedure(const Method: TLightCondVar.TSyncMethod) of object;
  var
    FReadOnly: TReadOnlyChannel<T>;
    FWriteOnly: TWriteOnlyChannel<T>;
    FSTChannel: TSingleThreadSyncChannel<T>;
    FMTChannel: TMultiThreadSyncChannel<T>;
    FOnRead: TOnRead;
    FOnWrite: TOnWrite;
    FOnClose: TThreadMethod;
    FOnBroadCast: TOnBroadcast;
  protected
    FLiveToken: ILiveToken;
    procedure BroadcastAll(const Method: TLightCondVar.TSyncMethod); override;
    function InternalRead(out A: T; ReleaseFactor: Integer): Boolean; override;
    function InternalWrite(const A: T; ReleaseFactor: Integer): Boolean; override;
  public
    constructor Create(const ThreadSafe: Boolean);
    destructor Destroy; override;
    procedure Close; override;
    function ReadOnly: IReadOnly<T>;
    function WriteOnly: IWriteOnly<T>;
    function GetBufSize: LongWord; override;
  end;

  TAsyncChannel<T> = class(TCustomChannel<T>, IChannel<T>)
  strict private
    FSize: Integer;
    FCapacity: Integer;
    FReadOnly: TReadOnlyChannel<T>;
    FWriteOnly: TWriteOnlyChannel<T>;
    FItems: array of IContract<T>;
    FReadOffset: Integer;
    FWriteOffset: Integer;
    FReadCond: TLightCondVar;
    FWriteCond: TLightCondVar;
  protected
    FLiveToken: ILiveToken;
    procedure BroadcastAll(const Method: TLightCondVar.TSyncMethod); override;
    function InternalRead(out A: T; ReleaseFactor: Integer): Boolean; override;
    function InternalWrite(const A: T; ReleaseFactor: Integer): Boolean; override;
  public
    constructor Create(BufSize: LongWord);
    destructor Destroy; override;
    procedure Close; override;
    function  ReadOnly: IReadOnly<T>;
    function  WriteOnly: IWriteOnly<T>;
    function GetBufSize: LongWord; override;
  end;

  TChannelEnumerator<T> = class(TEnumerator<T>)
  strict private
    FChannel: TCustomChannel<T>;
    FCurrent: T;
    FReleaseFactor: Integer;
  protected
    function GetCurrent: T; override;
  public
    constructor Create(Channel: TCustomChannel<T>; ReleaseFator: Integer);
    function MoveNext: Boolean; override;
    property Current: T read GetCurrent;
    procedure Reset; override;
  end;

  TSingleThreadSyncChannel<T> = class
  const
    YIELD_WAIT_CNT = 2;
  type
    TContract = record
    strict private
      SmartObj: IGCObject;
    public
      Value: T;
      Contragent: Pointer;
      IsEmpty: Boolean;
      procedure PushSmartObj(Value: IGCObject);
      function PullSmartObj: IGCObject;
    end;
  strict private
  var
    FContractExists: Boolean;
    FReadCond: TLightCondVar;
    FWriteCond: TLightCondVar;
    FContract: TContract;
    FHub: TCustomHub;
    FIsClosed: Boolean;
    FIsObjectTyp: Boolean;
    FOnGetLocalService: TOnGetLocalService;
    FOnCheckDeadLock: TOnCheckDeadLock;
    FWritersNumPtr: PInteger;
    FReadersNumPtr: PInteger;
  public
    constructor Create(const IsObjectTyp: Boolean;
      const OnGetLocalGC: TOnGetLocalService;
      const OnCheckDeadLock: TOnCheckDeadLock; WNumPtr, RNumPtr: PInteger);
    destructor Destroy; override;
    function Write(const A: T; ReleaseFactor: Integer): Boolean;
    function Read(out A: T; ReleaseFactor: Integer): Boolean;
    procedure Close;
    property Hub: TCustomHub read FHub write FHub;
    procedure Assign(Source: TMultiThreadSyncChannel<T>);
    procedure BroadcastAll(const Method: TLightCondVar.TSyncMethod);
  end;

  TMultiThreadSyncChannel<T> = class
  strict private
    FLock: TPasMPSpinLock;
    FReadCond: TLightCondVar;
    FWriteCond: TLightCondVar;
    FIsClosed: Boolean;
    FContract: IContract<T>;
    FContractExists: Boolean;
    FNotify: ILightGevent;
    FIsObjectTyp: Boolean;
    FOnGetLocalService: TOnGetLocalService;
    FOnCheckDeadLock: TOnCheckDeadLock;
    FWritersNumPtr: PInteger;
    FReadersNumPtr: PInteger;
  protected
    property Lock: TPasMPSpinLock read FLock;
    property Contract: IContract<T> read FContract;
    property ContractExists: Boolean read FContractExists write FContractExists;
    property Notify: ILightGevent read FNotify write FNotify;
    property ReadCond: TLightCondVar read FReadCond;
    property WriteCond: TLightCondVar read FWriteCond;
  public
    constructor Create(const IsObjectTyp: Boolean;
      const OnGetLocalGC: TOnGetLocalService;
      const OnCheckDeadLock: TOnCheckDeadLock; WNumPtr, RNumPtr: PInteger);
    destructor Destroy; override;
    function Write(const A: T; ReleaseFactor: Integer): Boolean;
    function Read(out A: T; ReleaseFactor: Integer): Boolean;
    procedure Close;
    procedure BroadcastAll(const Method: TLightCondVar.TSyncMethod);
  end;

  TSoftDeadLock = class(EAbort);

  TFanOutImpl<T> = class(TInterfacedObject, IFanOut<T>)
  strict private
  type
    IReadChannel = IReadOnly<T>;
    TChannelDescr = record
      ID: Integer;
      Token: ILiveToken;
      SyncImpl: TSyncChannel<T>;
      AsyncImpl: TAsyncChannel<T>;
      Channel: TCustomChannel<T>;
    end;
  var
    FLastID: Integer;
    FBufSize: LongWord;
    FLock: TCriticalSection;
    FInflateList: TList<TChannelDescr>;
    FWorker: IRawGreenlet;
    FWorkerContext: NativeUInt;
    FWorkerCtxReady: TGevent;
    FOnUpdated: TGevent;
    procedure Routine(const Input: IReadOnly<T>);
    procedure DieCb(ID: Integer);
    function GenerateID: Integer;
  public
    constructor Create(Input: IReadOnly<T>);
    destructor Destroy; override;
    function Inflate(const BufSize: Integer=-1): IReadOnly<T>;
  end;

  TLiveTokenImpl = class(TInterfacedObject, ILiveToken)
  strict private
    FIsLive: Boolean;
    FCb: TOnDieEvent;
    FID: Integer;
    FLock: TCriticalSection;
  public
    constructor Create(ID: Integer; const Cb: TOnDieEvent);
    destructor Destroy; override;
    function IsLive: Boolean;
    procedure Die;
    procedure Deactivate;
  end;

var
  StdDeadLockException: TExceptionClass;
  StdLeaveLockException: TExceptionClass;

implementation
uses TypInfo, GreenletsImpl, Math;

type
  TRawGreenletPImpl = class(TRawGreenletImpl);

function _GetCurentHub: TCustomHub;
begin
  if GetCurrent <> nil then
    Result := TRawGreenletPImpl(GetCurrent).Hub
  else
    Result := GetCurrentHub
end;

{ TSyncChannel<T> }

procedure TSyncChannel<T>.BroadcastAll(const Method: TLightCondVar.TSyncMethod);
begin
  FOnBroadCast(Method);
end;

procedure TSyncChannel<T>.Close;
begin
  inherited;
  FOnClose;
  CheckLeaveLock;
end;

constructor TSyncChannel<T>.Create(const ThreadSafe: Boolean);
begin
  inherited Create;
  FReadOnly := TReadOnlyChannel<T>.Create(Self);
  FWriteOnly := TWriteOnlyChannel<T>.Create(Self);
  if ThreadSafe then begin
    FMTChannel := TMultiThreadSyncChannel<T>.Create(IsObjectTyp,
      GetLocalService, CheckDeadLock, @FWritersNum, @FReadersNum);
    FOnRead := FMTChannel.Read;
    FOnWrite := FMTChannel.Write;
    FOnClose := FMTChannel.Close;
    FOnBroadCast := FMTChannel.BroadcastAll;
  end
  else begin
    FSTChannel := TSingleThreadSyncChannel<T>.Create(IsObjectTyp,
      GetLocalService, CheckDeadLock, @FWritersNum, @FReadersNum);
    FOnRead := FSTChannel.Read;
    FOnWrite := FSTChannel.Write;
    FOnClose := FSTChannel.Close;
    FOnBroadCast := FSTChannel.BroadcastAll;
  end;
end;

destructor TSyncChannel<T>.Destroy;
begin
  if Assigned(FLiveToken) then
    FLiveToken.Die;
  FReadOnly.Free;
  FWriteOnly.Free;
  FSTChannel.Free;
  FMTChannel.Free;
  inherited;
end;

function TSyncChannel<T>.GetBufSize: LongWord;
begin
  Result := 0
end;

function TSyncChannel<T>.InternalRead(out A: T;
  ReleaseFactor: Integer): Boolean;
begin
  Result := FOnRead(A, ReleaseFactor);
  if not Result then begin
    CheckLeaveLock;
  end;
end;

function TSyncChannel<T>.InternalWrite(const A: T;
  ReleaseFactor: Integer): Boolean;
begin
  Result := FOnWrite(A, ReleaseFactor);
  if not Result then
    CheckLeaveLock;
end;

function TSyncChannel<T>.ReadOnly: IReadOnly<T>;
begin
  Result := FReadOnly
end;

function TSyncChannel<T>.WriteOnly: IWriteOnly<T>;
begin
  Result := FWriteOnly
end;

{ TAsyncChannel<T> }

procedure TAsyncChannel<T>.BroadcastAll(const Method: TLightCondVar.TSyncMethod);
begin
  FReadCond.Broadcast(Method);
  FWriteCond.Broadcast(Method);
end;

procedure TAsyncChannel<T>.Close;
begin
  inherited;
  FReadCond.Broadcast(smForceAsync);
  FWriteCond.Broadcast(smForceAsync);
  CheckLeaveLock;
end;

constructor TAsyncChannel<T>.Create(BufSize: LongWord);
var
  I: Integer;
begin
  inherited Create;
  Assert(BufSize > 0, 'BufSize > 0');
  FCapacity := BufSize;
  FReadOnly := TReadOnlyChannel<T>.Create(Self);
  FWriteOnly := TWriteOnlyChannel<T>.Create(Self);
  SetLength(FItems, BufSize);
  for I := 0 to High(FItems) do
    FItems[I] := TContractImpl<T>.Create;
  FReadCond := TLightCondVar.Create(False, True);
  FWriteCond := TLightCondVar.Create(True, True);
end;

destructor TAsyncChannel<T>.Destroy;
begin
  if Assigned(FLiveToken) then
    FLiveToken.Die;
  FReadOnly.Free;
  FWriteOnly.Free;
  FReadCond.Free;
  FWriteCond.Free;
  inherited;
end;

function TAsyncChannel<T>.GetBufSize: LongWord;
begin
  Result := FCapacity
end;

function TAsyncChannel<T>.InternalRead(out A: T;
  ReleaseFactor: Integer): Boolean;
var
  Contract: IContract<T>;
  ObjPtr: PObject;
  Ref: IGCObject;
begin
  Result := False;
  AtomicDecrement(FWritersNum, ReleaseFactor);
  try
    while True do begin
      FLock.Acquire;
      if FSize > 0 then begin
        Contract := FItems[FReadOffset];
        if not Contract.IsMyCtx then begin
          FReadOffset := (FReadOffset + 1) mod FCapacity;
          Dec(FSize);
          Contract.Pop(A, Ref);
          FLock.Release;
          FWriteCond.Signal;
          Exit(True);
        end
        else begin
          FWriteCond.Broadcast;
          if CheckDeadLock(True, False, False, False) then begin
            FLock.Release;
            raise GetLocalService.DeadLockExceptionClass.Create('DeadLock::TAsyncChannel<T>.Read');
          end;
          FReadCond.Wait(FLock);
        end;
      end
      else begin
        if IsClosed then begin
          FLock.Release;
          Exit(False)
        end
        else begin
          if CheckDeadLock(True, False, False, False) then begin
            FLock.Release;
            raise GetLocalService.DeadLockExceptionClass.Create('DeadLock::TAsyncChannel<T>.Read');
          end;
          FReadCond.Wait(FLock);
        end;
      end;
    end;
  finally
    AtomicIncrement(FWritersNum, ReleaseFactor);
    if Result and IsObjectTyp then begin
      ObjPtr := @A;
      GetLocalService.Refresh(ObjPtr^);
    end;
    if not Result then begin
      CheckLeaveLock;
    end;
  end;
end;

function TAsyncChannel<T>.InternalWrite(const A: T;
  ReleaseFactor: Integer): Boolean;
var
  Contract: IContract<T>;
  ObjPtr: PObject;
  Ref: IGCObject;
begin
  if IsObjectTyp then begin
    ObjPtr := @A;
    Ref := GetLocalService.Refresh(ObjPtr^);
  end;
  Result := False;
  AtomicDecrement(FReadersNum, ReleaseFactor);
  try
    while not IsClosed do begin
      FLock.Acquire;
      if CheckDeadLock(False, True, False, False) then begin
        FLock.Release;
        raise GetLocalService.DeadLockExceptionClass.Create('DeadLock::TAsyncChannel<T>.Write');
      end;
      if FSize < FCapacity then begin
        Contract := FItems[FWriteOffset];
        FWriteOffset := (FWriteOffset + 1) mod FCapacity;
        Inc(FSize);
        Contract.Push(A, Ref);
        Contract.FixCurContext;
        FLock.Release;
        FReadCond.Signal;
        Exit(True);
      end
      else begin
        FReadCond.Broadcast;
        FWriteCond.Wait(FLock);
      end;
    end;
  finally
    AtomicIncrement(FReadersNum, ReleaseFactor);
  end;
  if not Result then
    CheckLeaveLock;
end;

function TAsyncChannel<T>.ReadOnly: IReadOnly<T>;
begin
  Result := FReadOnly;
end;

function TAsyncChannel<T>.WriteOnly: IWriteOnly<T>;
begin
  Result := FWriteOnly;
end;

{ TCustomChannel<T> }

procedure TCustomChannel<T>.AccumRefs(ReadRefCount, WriteRefCount: Integer);
var
  Context: NativeUInt;
  OldRefCount: Integer;
begin
  Context := GetContextUID;
  FLock.Acquire;
  if FReaders.ContainsKey(Context) then begin
    OldRefCount := FReaders[Context].GetRefCount;
    FReaders[Context].AddRef(ReadRefCount);
    if (FReaders[Context].GetRefCount > 0) and (OldRefCount <= 0) then
      AtomicIncrement(FReadersNum);
  end;
  if FWriters.ContainsKey(Context) then begin
    OldRefCount := FWriters[Context].GetRefCount;
    FWriters[Context].AddRef(WriteRefCount);
    if (FWriters[Context].GetRefCount > 0) and (OldRefCount <= 0) then
      AtomicIncrement(FReadersNum);
  end;
  FLock.Release;
end;

procedure TCustomChannel<T>.AsyncRead(const Promise: IPromise<T, TPendingError>; const ReleaseFactor: Integer);
var
  Value: T;
begin
  InternalAddRef(True, False);
  try
    SetDeadlockExceptionClass(TSoftDeadLock);
    try
      if InternalRead(Value, 0) then
        Promise.SetResult(Value)
      else
        Promise.SetErrorCode(psClosed)
    except
      on E: TSoftDeadLock do
        Promise.SetErrorCode(psDeadlock);
      on E: Exception do
        Promise.SetErrorCode(psException, Format('%s::%s', [E.ClassName, E.Message]));
    end;
  finally
    InternalRelease(True, False);
  end;
end;

procedure TCustomChannel<T>.AsyncWrite(const Promise: IPromise<T, TPendingError>;
  const ReleaseFactor: Integer; const Value: TSmartPointer<T>);
begin
  InternalAddRef(False, True);
  try
    SetDeadlockExceptionClass(TSoftDeadLock);
    try
      if InternalWrite(Value, 0) then
        Promise.SetResult(Value)
      else
        Promise.SetErrorCode(psClosed)
    except
      on E: TSoftDeadLock do
        Promise.SetErrorCode(psDeadlock);
      on E: Exception do
        Promise.SetErrorCode(psException, Format('%s::%s', [E.ClassName, E.Message]));
    end;
  finally
    InternalRelease(False, True);
  end;
end;

function TCustomChannel<T>.CheckDeadLock(const AsReader: Boolean; const AsWriter: Boolean;
  const RaiseError: Boolean; const Lock: Boolean): Boolean;
begin
  {$IFDEF DEBUG}
  Assert(AsReader <> AsWriter);
  Assert(AsReader or AsWriter);
  {$ENDIF}
  if IsClosed then
    Exit(False);
  if Lock then
    FLock.Acquire;
  if AsReader then begin
    Result := FWritersNum < 1
  end
  else begin
    Result := FReadersNum < 1;
  end;
  if Lock then
    FLock.Release;
  if Result and RaiseError then
    raise GetLocalService.DeadLockExceptionClass.Create('DeadLock::TCustomChannel<T>');
end;

procedure TCustomChannel<T>.CheckLeaveLock;
var
  Key: string;
  Inst: TLeaveLockLogger;
begin
  if IsClosed then begin
    Key := Format('LeaveLocker_%s', [Guid]);
    Inst := TLeaveLockLogger(Context(Key));
    if not Assigned(Inst) then begin
      Inst := TLeaveLockLogger.Create;
      Context(Key, Inst);
    end;
    Inst.Check('LeaveLock::TCustomChannel<T>');
  end;
end;

procedure TCustomChannel<T>.Close;
var
  Contract: IContract<T>;
begin
  FIsClosed := 1;
end;

constructor TCustomChannel<T>.Create;
var
  UID: TGUID;
  ti: PTypeInfo;
begin
  if CreateGuid(UID) = 0 then
    FGuid := GUIDToString(UID)
  else
    FGuid := Format('Channel.%p', [Pointer(Self)]);
  ti := TypeInfo(T);
  FIsObjectTyp := ti.Kind = tkClass;
  if FIsObjectTyp then
    GetLocalService;
  FReaders := TContextHashTable.Create(2);
  FWriters := TContextHashTable.Create(2);
  FLock := TPasMPSpinLock.Create;
  FOwnerContext := GetContextUID;
end;

destructor TCustomChannel<T>.Destroy;
begin
  Context(GetLocalContextKey, nil);
  FReaders.Free;
  FWriters.Free;
  FLock.Free;
  inherited;
end;

function TCustomChannel<T>.Get: T;
begin
  if not Read(Result) then
    raise EChannelClosed.Create('Channel is closed');
end;

class function TCustomChannel<T>.GetContextUID: NativeUInt;
begin
  if GetCurrent = nil then
    Result := NativeUInt(GetCurrentHub)
  else
    Result := NativeUInt(GetCurrent)
end;

function TCustomChannel<T>.GetDeadlockExceptionClass: TExceptionClass;
begin
  Result := GetLocalService.DeadLockExceptionClass;
  if not Assigned(Result) then
    Result := StdDeadLockException;
end;

function TCustomChannel<T>.GetEnumerator: TEnumerator<T>;
begin
  Result := TChannelEnumerator<T>.Create(Self, 1)
end;

function TCustomChannel<T>.GetLocalService: TLocalContextService;
var
  Key: string;
begin
  Key := GetLocalContextKey;
  Result := TLocalContextService(Context(Key));
  if not Assigned(Result) then begin
    Result := TLocalContextService.Create;
    Context(Key, Result);
  end;
end;

function TCustomChannel<T>.GetLocalContextKey: string;
begin
  Result := Format('LocalGC_%s', [Guid]);
end;

function TCustomChannel<T>.GetLocalPendingKey: string;
begin
  Result := Format('Pendings_%s', [Guid]);
end;

function TCustomChannel<T>.GetLocalPendings: TPendingOperations<T>;
var
  Key: string;
begin
  Key := GetLocalPendingKey;
  Result := TPendingOperations<T>(Context(Key));
  if not Assigned(Result) then begin
    Result := TPendingOperations<T>.Create;
    Context(Key, Result);
  end;
end;

function TCustomChannel<T>.InternalAddRef(const AsReader, AsWriter: Boolean): Integer;
var
  Context: NativeUInt;
begin
  Context := GetContextUID;
  FLock.Acquire;
  Inc(FRefCount);
  Result := FRefCount;
  if AsReader then begin
    if FReaders.ContainsKey(Context) then
      FReaders[Context].AddRef
    else begin
      FReaders.Add(Context, TContextRef.Create(True, Context = FOwnerContext));
      AtomicIncrement(FReadersNum);
    end;
  end;
  if AsWriter then begin
    if FWriters.ContainsKey(Context) then
      FWriters[Context].AddRef
    else begin
      FWriters.Add(Context, TContextRef.Create(True, Context = FOwnerContext));
      AtomicIncrement(FWritersNum);
    end;
  end;
  FLock.Release;
end;

function TCustomChannel<T>.InternalRelease(const AsReader, AsWriter: Boolean): Integer;
var
  Context: NativeUInt;
  DeadLock: Boolean;
begin
  DeadLock := False;
  Context := GetContextUID;
  FLock.Acquire;
  Dec(FRefCount);
  Result := FRefCount;
  if AsReader and FReaders.ContainsKey(Context) then begin
    if FReaders[Context].Release = 0 then begin
      AtomicDecrement(FReadersNum);
      FReaders.Remove(Context);
    end;
  end;
  if AsWriter and FWriters.ContainsKey(Context) then begin
    if FWriters[Context].Release = 0 then begin
      AtomicDecrement(FWritersNum);
      FWriters.Remove(Context);
    end;
  end;
  DeadLock := CheckDeadLock(False, True, False, False) or CheckDeadLock(True, False, False, False);
  FLock.Release;
  if DeadLock then
    BroadcastAll(smForceAsync);
  if Result = 0 then
    Destroy;
end;

function TCustomChannel<T>.IsClosed: Boolean;
begin
  Result := FIsClosed = 1;
end;

function TCustomChannel<T>.Read(out A: T): Boolean;
begin
  Result := InternalRead(A, 1);
  if not Result then
    A := FDefValue
end;

function TCustomChannel<T>.ReadPending: IFuture<T, TPendingError>;
var
  AsyncReader: TSymmetric<IPromise<T, TPendingError>, Integer>;
  FP: TFuturePromise<T, TPendingError>;
  Pending: TPendingOperations<T>;
  Index: Integer;
begin
  Pending := GetLocalPendings;
  Result := Pending.ReaderFuture;

  if Assigned(Result) and (Select([Result.OnFullFilled, Result.OnRejected], Index, 0) = wrTimeout) then
    Exit;
  
  AsyncReader := TSymmetric<IPromise<T, TPendingError>, Integer>.Spawn(AsyncRead, FP.Promise, 1);
  Result := FP.Future;
  Pending.PendingReader := AsyncReader;
  Pending.ReaderFuture := Result;
end;

procedure TCustomChannel<T>.ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
var
  Context: NativeUInt;
  OldRefCount: Integer;
  DeadLock: Boolean;
begin
  Context := GetContextUID;
  FLock.Acquire;
  if FReaders.ContainsKey(Context) then begin
    OldRefCount := FReaders[Context].GetRefCount;
    FReaders[Context].Release(ReadRefCount);
    if (FReaders[Context].GetRefCount <= 0) and (OldRefCount > 0) then
      AtomicDecrement(FReadersNum)
  end;
  if FWriters.ContainsKey(Context) then begin
    OldRefCount := FWriters[Context].GetRefCount;
    FWriters[Context].Release(WriteRefCount);
    if (FWriters[Context].GetRefCount <= 0) and (OldRefCount > 0) then
      AtomicDecrement(FWritersNum)
  end;
  DeadLock := CheckDeadLock(False, True, False, False) or CheckDeadLock(True, False, False, False);
  FLock.Release;
  if DeadLock then
    BroadcastAll(smForceAsync);
end;

procedure TCustomChannel<T>.SetDeadlockExceptionClass(Cls: TExceptionClass);
begin
  GetLocalService.DeadLockExceptionClass := Cls
end;

function TCustomChannel<T>.Write(const A: T): Boolean;
begin
  Result := InternalWrite(A, 1);
end;

function TCustomChannel<T>.WritePending(const A: T): IFuture<T, TPendingError>;
var
  AsyncWriter: TSymmetric<IPromise<T, TPendingError>, Integer, TSmartPointer<T>>;
  FP: TFuturePromise<T, TPendingError>;
  SmartValue: TSmartPointer<T>;
  Pending: TPendingOperations<T>;
  Index: Integer;
begin
  Pending := GetLocalPendings;
  Result := Pending.WriterFuture;

  if Assigned(Result) and (Select([Result.OnFullFilled, Result.OnRejected], Index, 0) = wrTimeout) then
    Exit;

  SmartValue := A;
  AsyncWriter := TSymmetric<IPromise<T, TPendingError>, Integer, TSmartPointer<T>>
    .Spawn(AsyncWrite, FP.Promise, 1, SmartValue);
  Result := FP.Future;
  Pending.PendingWriter := AsyncWriter;
  Pending.WriterFuture := Result;
end;

function TCustomChannel<T>._AddRef: Integer;
begin
  Result := InternalAddRef(True, True);
end;

function TCustomChannel<T>._Release: Integer;
begin
  Result := InternalRelease(True, True)
end;

{ TReadOnlyChannel<T> }

procedure TReadOnlyChannel<T>.AccumRefs(ReadRefCount, WriteRefCount: Integer);
begin
  FParent.AccumRefs(ReadRefCount, WriteRefCount)
end;

procedure TReadOnlyChannel<T>.Close;
begin
  FParent.Close;
end;

constructor TReadOnlyChannel<T>.Create(Parent: TCustomChannel<T>);
begin
  FParent := Parent;
end;

function TReadOnlyChannel<T>.Get: T;
begin
  Result := FPArent.Get
end;

function TReadOnlyChannel<T>.GetBufSize: LongWord;
begin
  Result := FParent.GetBufSize
end;

function TReadOnlyChannel<T>.GetDeadlockExceptionClass: TExceptionClass;
begin
  Result := FParent.GetDeadlockExceptionClass
end;

function TReadOnlyChannel<T>.GetEnumerator: TEnumerator<T>;
begin
  Result := TChannelEnumerator<T>.Create(FParent, 0)
end;

function TReadOnlyChannel<T>.IsClosed: Boolean;
begin
  Result := FParent.IsClosed
end;

function TReadOnlyChannel<T>.Read(out A: T): Boolean;
begin
  Result := FParent.InternalRead(A, 0);
  if not Result then
    A := FParent.FDefValue;
end;

function TReadOnlyChannel<T>.ReadPending: IFuture<T, TPendingError>;
begin
  Result := FParent.ReadPending;
end;

procedure TReadOnlyChannel<T>.ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
begin
  FPArent.ReleaseRefs(ReadRefCount, WriteRefCount)
end;

procedure TReadOnlyChannel<T>.SetDeadlockExceptionClass(Cls: TExceptionClass);
begin
  FParent.SetDeadlockExceptionClass(Cls)
end;

function TReadOnlyChannel<T>._AddRef: Integer;
begin
  Result := FParent.InternalAddRef(True, False);
end;

function TReadOnlyChannel<T>._Release: Integer;
begin
  Result := FParent.InternalRelease(True, False);
end;

{ TWriteOnlyChannel<T> }

procedure TWriteOnlyChannel<T>.AccumRefs(ReadRefCount, WriteRefCount: Integer);
begin
  FParent.AccumRefs(ReadRefCount, WriteRefCount);
end;

procedure TWriteOnlyChannel<T>.Close;
begin
  FParent.Close
end;

constructor TWriteOnlyChannel<T>.Create(Parent: TCustomChannel<T>);
begin
  FParent := Parent;
end;

function TWriteOnlyChannel<T>.GetBufSize: LongWord;
begin
  Result := FParent.GetBufSize
end;

function TWriteOnlyChannel<T>.GetDeadlockExceptionClass: TExceptionClass;
begin
  Result := FParent.GetDeadlockExceptionClass
end;

function TWriteOnlyChannel<T>.IsClosed: Boolean;
begin
  Result := FParent.IsClosed
end;

procedure TWriteOnlyChannel<T>.ReleaseRefs(ReadRefCount, WriteRefCount: Integer);
begin
  FParent.ReleaseRefs(ReadRefCount, WriteRefCount);
end;

procedure TWriteOnlyChannel<T>.SetDeadlockExceptionClass(Cls: TExceptionClass);
begin
  FParent.SetDeadlockExceptionClass(Cls)
end;

function TWriteOnlyChannel<T>.Write(const A: T): Boolean;
begin
  Result := FParent.InternalWrite(A, 0);
end;

function TWriteOnlyChannel<T>.WritePending(
  const A: T): IFuture<T, TPendingError>;
begin
  Result := FParent.WritePending(A);
end;

function TWriteOnlyChannel<T>._AddRef: Integer;
begin
  Result := FParent.InternalAddRef(False, True)
end;

function TWriteOnlyChannel<T>._Release: Integer;
begin
  Result := FParent.InternalRelease(False, True)
end;

{ TChannelEnumerator<T> }

constructor TChannelEnumerator<T>.Create(Channel: TCustomChannel<T>;
  ReleaseFator: Integer);
begin
  FChannel := Channel;
  FReleaseFactor := ReleaseFator;
end;

function TChannelEnumerator<T>.GetCurrent: T;
begin
  Result := FCurrent;
end;

function TChannelEnumerator<T>.MoveNext: Boolean;
begin
  Result := FChannel.InternalRead(FCurrent, FReleaseFactor)
end;

procedure TChannelEnumerator<T>.Reset;
begin
  // nothing
end;

{ TContractImpl }

constructor TAbstractContractImpl.Create;
begin
  FLock := TPasMPSpinLock.Create;
  Inherited;
end;

destructor TAbstractContractImpl.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TAbstractContractImpl.FixCurContext;
begin
  FContext := GetCurrent;
  FHub := _GetCurentHub;
end;

function TAbstractContractImpl.IsMyCtx: Boolean;
begin
  Result := (GetCurrent = FContext) and (FHub = _GetCurentHub)
end;

procedure TAbstractContractImpl.Lock;
begin
  FLock.Acquire;
end;

procedure TAbstractContractImpl.Unlock;
begin
  FLock.Release;
end;

{ TContractImpl<T> }

constructor TContractImpl<T>.Create;
begin
  FIsEmpty := True;
  Inherited;
end;

destructor TContractImpl<T>.Destroy;
begin

  inherited;
end;

function TContractImpl<T>.IsEmpty: Boolean;
begin
  Result := FIsEmpty;
end;

function TContractImpl<T>.Pop(out A: T; out Ref: IGCObject): Boolean;
begin
  if FIsEmpty then begin
    A := FDefValue;
    Result := False;
  end
  else begin
    A := FValue;
    Ref := FSmartObj;
    FSmartObj := nil;
    FIsEmpty := True;
    Result := True;
  end;
end;

function TContractImpl<T>.Push(const A: T; Ref: IGCObject): Boolean;
begin
  if FIsEmpty then begin
    FValue := A;
    FSmartObj := Ref;
    FIsEmpty := False;
    Result := True;
  end
  else
    Result := False;
end;

{ TLightGevent }

procedure TLightGevent.Associate(Other: ILightGevent; Index: Integer);
begin
  Lock;
  FAssociate := Other;
  FAssociateIndex := Index;
  Unlock;
end;

constructor TLightGevent.Create;
begin
  FIndex := -1;
  FAssociateIndex := -1;
  FLock := TPasMPSpinLock.Create;
  FContext := GetCurrent;
  FHub := GetCurrentHub;
  if Assigned(FContext) then
    FWaitEventRoutine := GreenletWaitEvent
  else
    FWaitEventRoutine := ThreadedWaitEvent;
  inherited;
end;

destructor TLightGevent.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TLightGevent.GetContext: Pointer;
begin
  Result := FContext
end;

function TLightGevent.GetIndex: Integer;
begin
  Lock;
  Result := FIndex;
  Unlock;
end;

function TLightGevent.GetInstance: Pointer;
begin
  Result := Self
end;

procedure TLightGevent.GreenletWaitEvent;
begin
  while not FSignal do begin
    TRawGreenletImpl(FContext).Suspend;
    Greenlets.Yield;
  end;
  TRawGreenletImpl(FContext).Resume;
end;

procedure TLightGevent.Lock;
begin
  FLock.Acquire;
end;

procedure TLightGevent.SetEvent(const Async: Boolean);
var
  CurHub: TCustomHub;
begin
  CurHub := _GetCurentHub;
  Lock;
  try
    FSignal := True;
    if not FWaiting then
      Exit;
    if Assigned(FAssociate) and (FAssociate.GetIndex = -1) then begin
      FAssociate.SetIndex(FAssociateIndex);
      FAssociate.SetEvent(True);
    end;
  finally
    Unlock;
  end;
  if (GetCurrent = FContext) and (FHub = GetCurrentHub) then
    Exit;
  if Assigned(FContext) then begin
    // TODO: вызов GetCurrentHub дорого стоит. Если убрать скорость вырастет в 1.5-2 раза
    if (FHub = CurHub) and (not Async) then begin
      TRawGreenletPImpl(FContext).SetState(gsExecute);
      TRawGreenletPImpl(FContext).Switch
    end
    else
      TRawGreenletPImpl(FContext).GetProxy.Resume
  end
  else begin
    {if (FHub = CurHub) and (not Async) then begin
      FHub.Switch
    end
    else    }
      FHub.Pulse
  end;
end;

procedure TLightGevent.SetIndex(Value: Integer);
begin
  Lock;
  if (FIndex = -1) and (Value <> -1) then
    FIndex := Value;
  Unlock;
end;

procedure TLightGevent.ThreadedWaitEvent;
begin
  FHub.IsSuspended := True;
  try
    while not FSignal do begin
      Greenlets.Yield;
    end;
  finally
    FHub.IsSuspended := False;
  end;
end;

procedure TLightGevent.Unlock;
begin
  FLock.Release
end;

procedure TLightGevent.WaitEvent;
begin
  {$IFDEF DEBUG}
  Assert(GetCurrent = FContext, 'TLightGevent.WaitEvent context error');
  {$ENDIF}
  Lock;
  if FSignal then begin
    FSignal := False;
    Unlock;
  end
  else begin
    FWaiting := True;
    Unlock;
    try
      FWaitEventRoutine;
      Lock;
      FSignal := False;
      Unlock;
    finally
      Lock;
      FWaiting := False;
      Unlock;
    end;
  end;
end;

{ TSingleThreadSyncChannel<T> }

procedure TSingleThreadSyncChannel<T>.Assign(Source: TMultiThreadSyncChannel<T>);
var
  A: T;
  Ref: IGCObject;
begin
  Source.Lock.Acquire;
  try
    if Source.ContractExists then begin
      if Self.FContractExists then begin
        if Assigned(Source.Notify) then begin
          if Source.Contract.IsEmpty then
            Self.FReadCond.Enqueue(TLightGevent(Source.Notify.GetInstance))
          else
            Self.FWriteCond.Enqueue(TLightGevent(Source.Notify.GetInstance));
          Source.Notify := nil;
        end;
      end
      else begin
        Self.FContractExists := True;
        Self.FContract.IsEmpty := not Source.Contract.Pop(A, Ref);
        if not Self.FContract.IsEmpty then begin
          Self.FContract.Value := A;
        end;
        if Assigned(Source.Notify) then
          Self.FContract.Contragent := Source.Notify.GetContext
        else
          Self.FContract.Contragent := nil
      end;
    end;
    Source.ContractExists := False;
    Self.FReadCond.Assign(Source.ReadCond);
    Self.FWriteCond.Assign(Source.WriteCond);
  finally
    Source.Lock.Release
  end;
end;

procedure TSingleThreadSyncChannel<T>.BroadcastAll(const Method: TLightCondVar.TSyncMethod);
begin
  FReadCond.Broadcast(Method);
  FWriteCond.Broadcast(Method);
end;

procedure TSingleThreadSyncChannel<T>.Close;
begin
  FIsClosed := True;
  FReadCond.Broadcast;
  FWriteCond.Broadcast;
  if FContractExists then
    TRawGreenletImpl(FContract.Contragent).Switch;
end;

constructor TSingleThreadSyncChannel<T>.Create(const IsObjectTyp: Boolean;
  const OnGetLocalGC: TOnGetLocalService;
  const OnCheckDeadLock: TOnCheckDeadLock;
  WNumPtr, RNumPtr: PInteger);
begin
  FIsObjectTyp := IsObjectTyp;
  FOnGetLocalService := OnGetLocalGC;
  FOnCheckDeadLock := OnCheckDeadLock;
  FWritersNumPtr := WNumPtr;
  FReadersNumPtr := RNumPtr;
  FContract.IsEmpty := True;
  FReadCond := TLightCondVar.Create(False, False);
  FWriteCond := TLightCondVar.Create(False, False);
  FHub := GetCurrentHub;
end;

destructor TSingleThreadSyncChannel<T>.Destroy;
begin
  FReadCond.Free;
  FWriteCond.Free;
  inherited;
end;

function TSingleThreadSyncChannel<T>.Read(out A: T; ReleaseFactor: Integer): Boolean;
var
  Counter: Integer;
  ObjPtr: PObject;
  Ref: IGCObject;
begin
  Result := False;
  AtomicDecrement(FWritersNumPtr^, ReleaseFactor);
  try
    while True do begin
      if FContractExists then begin
        if not FContract.IsEmpty then begin
          A := FContract.Value;
          Ref := FContract.PullSmartObj;
          FContract.IsEmpty := True;
          if Assigned(FContract.Contragent) then begin
            with TRawGreenletImpl(FContract.Contragent) do begin
              if GetState = gsExecute then
                Switch
              else
                FWriteCond.Signal
            end;
          end
          else begin
            TRawGreenletImpl(GetCurrent).GetProxy.DelayedSwitch;
            FWriteCond.Signal;
            FHub.Switch;
          end;
          Exit(True);
        end
        else begin
          FWriteCond.Signal;
          if FContractExists and FContract.IsEmpty then begin
            if FOnCheckDeadLock(True, False, False, False) then begin
              raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Read');
            end
            else begin
              FReadCond.Wait;
            end;
          end;
        end;
      end
      else begin
        FContractExists := True;
        FContract.IsEmpty := True;
        FContract.Contragent := TRawGreenletImpl(GetCurrent);
        try
          Counter := 1;
          while FContract.IsEmpty do begin
            if FIsClosed then
              Exit(False);
            if Counter > YIELD_WAIT_CNT then begin
              if FOnCheckDeadLock(True, False, False, False) then begin
                raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Read');
              end;
              FReadCond.Wait;
            end
            else begin
              Inc(Counter);
              Greenlets.Yield;
            end;
          end;
          if not FContract.IsEmpty then begin
            A := FContract.Value;
            Ref := FContract.PullSmartObj;
            Exit(True)
          end;
        finally
          FContract.Contragent := nil;
          FContractExists := False;
        end;
      end;
    end;
  finally
    AtomicIncrement(FWritersNumPtr^, ReleaseFactor);
    if Result and FIsObjectTyp then begin
      ObjPtr := @A;
      FOnGetLocalService.Refresh(ObjPtr^);
    end;
  end;
end;

function TSingleThreadSyncChannel<T>.Write(const A: T; ReleaseFactor: Integer): Boolean;
var
  Counter: Integer;
  ObjPtr: PObject;
  Ref: IGCObject;
begin
  if FIsObjectTyp then begin
    ObjPtr := @A;
    Ref := FOnGetLocalService.Refresh(ObjPtr^);
  end;
  Result := False;
  AtomicDecrement(FReadersNumPtr^, ReleaseFactor);
  try
    while not FIsClosed do begin
      if FOnCheckDeadLock(False, True, False, False) then begin
        raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Write');
      end;
      if FContractExists then begin
        if FContract.IsEmpty then begin
          FContract.Value := A;
          FContract.PushSmartObj(Ref);
          FContract.IsEmpty := False;
          if Assigned(FContract.Contragent) then begin
            with TRawGreenletImpl(FContract.Contragent) do begin
              if GetState = gsExecute then
                TRawGreenletImpl(FContract.Contragent).Switch
              else
                FReadCond.Signal
            end;
          end
          else begin
            TRawGreenletImpl(GetCurrent).GetProxy.DelayedSwitch;
            FReadCond.Signal;
            FHub.Switch;
          end;
          Exit(True);
        end
        else begin
          FReadCond.Signal;
          if FContractExists and (not FContract.IsEmpty) then
            FWriteCond.Wait;
        end;
      end
      else begin
        FContractExists := True;
        FContract.IsEmpty := False;
        FContract.Value := A;
        FContract.PushSmartObj(Ref);
        FContract.Contragent := TRawGreenletImpl(GetCurrent);
        try
          Counter := 1;
          while not FContract.IsEmpty do begin
            if FIsClosed then
              Exit(False);
            if Counter > YIELD_WAIT_CNT then begin
              FWriteCond.Wait;
            end
            else begin
              Inc(Counter);
              Greenlets.Yield;
            end;
          end;
          if FContract.IsEmpty then begin
            Exit(True)
          end
        finally
          FContract.Contragent := nil;
          FContractExists := False;
        end;
      end;
    end;
  finally
    AtomicIncrement(FReadersNumPtr^, ReleaseFactor);
  end;
end;


{ TMultiThreadSyncChannel<T> }

procedure TMultiThreadSyncChannel<T>.BroadcastAll(const Method: TLightCondVar.TSyncMethod);
begin
  FLock.Acquire;
  if FContractExists then
    FNotify.SetEvent(True);
  FLock.Release;
  FReadCond.Broadcast(Method);
  FWriteCond.Broadcast(Method);
end;

procedure TMultiThreadSyncChannel<T>.Close;
var
  Notify: ILightGevent;
begin
  FLock.Acquire;
  FIsClosed := True;
  FLock.Release;
  FReadCond.Broadcast(smForceAsync);
  FWriteCond.Broadcast(smForceAsync);
  FLock.Acquire;
  if Assigned(FNotify) then
    FNotify.SetEvent(True);
  FLock.Release;
end;

constructor TMultiThreadSyncChannel<T>.Create(const IsObjectTyp: Boolean;
  const OnGetLocalGC: TOnGetLocalService;
  const OnCheckDeadLock: TOnCheckDeadLock;
  WNumPtr, RNumPtr: PInteger);
begin
  FIsObjectTyp := IsObjectTyp;
  FOnGetLocalService := OnGetLocalGC;
  FOnCheckDeadLock := OnCheckDeadLock;
  FWritersNumPtr := WNumPtr;
  FReadersNumPtr := RNumPtr;
  FLock := TPasMPSpinLock.Create;
  FReadCond := TLightCondVar.Create(False, True);
  FWriteCond := TLightCondVar.Create(False, True);
  FContract := TContractImpl<T>.Create;
end;

destructor TMultiThreadSyncChannel<T>.Destroy;
begin
  FLock.Free;
  FReadCond.Free;
  FWriteCond.Free;
  inherited;
end;

function TMultiThreadSyncChannel<T>.Read(out A: T; ReleaseFactor: Integer): Boolean;
var
  Ref: IGCObject;
  ObjPtr: PObject;
begin
  Result := False;
  AtomicDecrement(FWritersNumPtr^, ReleaseFactor);
  try
    while True do begin
      FLock.Acquire;
      if FContractExists then begin
        if not FContract.IsEmpty and FContract.Pop(A, Ref) then begin
          FLock.Release;
          FNotify.SetEvent;
          Exit(True)
        end
        else begin
          if FIsClosed then begin
            FLock.Release;
            Exit(False)
          end
          else begin
            if FOnCheckDeadLock(True, False, False) then begin
              FLock.Release;
              raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Read');
            end
            else begin
              FWriteCond.Signal;
              FReadCond.Wait(FLock);
            end;
          end;
        end;
      end
      else begin
        if FIsClosed then begin
          FLock.Release;
          Exit(False);
        end;
        if FOnCheckDeadLock(True, False, False) then begin
          FLock.Release;
          raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Read');
        end;
        FContractExists := True;
        if FContract.IsEmpty then begin
          FNotify := TLightGevent.Create;
          FLock.Release;
          FWriteCond.Signal;
          FNotify.WaitEvent;
          FLock.Acquire;
          if FOnCheckDeadLock(True, False, False, False) then begin
            FLock.Release;
            raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Read');
          end;
          FContractExists := False;
          if FContract.Pop(A, Ref) then begin
            FLock.Release;
            Exit(True);
          end
          else begin
            if FIsClosed then begin
              FLock.Release;
              Exit(False);
            end
            else begin
              FWriteCond.Signal;
              FReadCond.Wait(FLock);
            end;
          end;
        end
        else begin
          FContractExists := False;
          FWriteCond.Signal;
          FReadCond.Wait(FLock);
        end;
      end;
    end;
  finally
    AtomicIncrement(FWritersNumPtr^, ReleaseFactor);
    if Result and FIsObjectTyp then begin
      ObjPtr := @A;
      FOnGetLocalService.Refresh(ObjPtr^);
    end;
  end;
end;

function TMultiThreadSyncChannel<T>.Write(const A: T; ReleaseFactor: Integer): Boolean;
var
  Ref: IGCObject;
  ObjPtr: PObject;
  Cls: TExceptionClass;
begin
  if FIsObjectTyp then begin
    ObjPtr := @A;
    Ref := FOnGetLocalService.Refresh(ObjPtr^);
  end;
  Result := False;
  AtomicDecrement(FReadersNumPtr^, ReleaseFactor);
  try
    while not FIsClosed do begin
      FLock.Acquire;
      if FOnCheckDeadLock(False, True, False) then begin
        FLock.Release;
        raise FOnGetLocalService.DeadLockExceptionClass.Create('DeadLock::TSyncChannel<T>.Write');
      end;
      if FContractExists then begin
        if FContract.IsEmpty and FContract.Push(A, Ref) then begin
          FLock.Release;
          FNotify.SetEvent;
          Exit(True)
        end
        else begin
          FReadCond.Signal;
          FWriteCond.Wait(FLock);
        end;
      end
      else begin
        FContractExists := True;
        if FContract.Push(A, Ref) then begin
          FNotify := TLightGevent.Create;
          FLock.Release;
          FReadCond.Signal;
          FNotify.WaitEvent;
          FLock.Acquire;
          FContractExists := False;
          FLock.Release;
          Exit(True);
        end
        else begin
          FContractExists := False;
          FReadCond.Signal;
          FWriteCond.Wait(FLock);
        end;
      end;
    end;
  finally
    AtomicIncrement(FReadersNumPtr^, ReleaseFactor)
  end;
end;

{ TLightCondVar }

procedure TLightCondVar.Assign(Source: TLightCondVar);
var
  I: Integer;
begin
  if Assigned(FLock) then
    FLock.Acquire;
  try
    if Assigned(Source.FLock) then
      Source.FLock.Acquire;
    try
      for I := 0 to Source.FItems.Count-1 do
        Self.FItems.Add(Source.FItems[I]);
      Source.FItems.Clear;
    finally
      if Assigned(Source.FLock) then
        Source.FLock.Release;
    end;
  finally
    if Assigned(FLock) then
      FLock.Release;
  end;
end;

procedure TLightCondVar.Broadcast(const Method: TSyncMethod);
begin
  FBroadcastRoutine(Method)
end;

procedure TLightCondVar.Clean;
var
  I: Integer;
begin
  if Assigned(FLock) then
    FLock.Acquire;
  try
    for I := 0 to FItems.Count-1 do
      TLightGevent(FItems[I])._Release;
    FItems.Clear;
  finally
    if Assigned(FLock) then
    FLock.Release;
  end;
end;

constructor TLightCondVar.Create(const Async: Boolean; const Locked: Boolean);
begin
  FAsync := Async;
  FItems := TList.Create;
  if Locked then begin
    FLock := TPasMPSpinLock.Create;
    FWaitRoutine := LockedWait;
    FSignalRoutine := LockedSignal;
    FBroadcastRoutine := LockedBroadcast;
  end
  else begin
    FWaitRoutine := UnLockedWait;
    FSignalRoutine := UnLockedSignal;
    FBroadcastRoutine := UnLockedBroadcast;
  end;
end;

function TLightCondVar.Dequeue(out E: TLightGevent): Boolean;
begin
  Result := FItems.Count > 0;
  if Result then begin
    E := TLightGevent(FItems[0]);
    FItems.Delete(0);
  end;
end;

destructor TLightCondVar.Destroy;
begin
  Clean;
  FItems.Free;
  if Assigned(FLock) then
    FLock.Free;
  inherited;
end;

procedure TLightCondVar.Enqueue(E: TLightGevent);
begin
  FItems.Add(E);
  E._AddRef;
end;

procedure TLightCondVar.Lock;
begin
  if Assigned(FLock) then
    FLock.Acquire
end;

procedure TLightCondVar.LockedBroadcast(const Method: TSyncMethod);
var
  E: TLightGevent;

  function _Dequeue(out E:  TLightGevent): Boolean;
  begin
    FLock.Acquire;
    Result := Dequeue(E);
    FLock.Release;
  end;

begin
  while _Dequeue(E) do
    try
      case Method of
        smDefault:
          E.SetEvent(FAsync);
        smForceAsync:
          E.SetEvent(True);
        smForceSync:
          E.SetEvent(False);
      end;
    finally
      E._Release;
    end;
end;

procedure TLightCondVar.LockedSignal(const Method: TSyncMethod);
var
  E: TLightGevent;

  function _Dequeue(out E:  TLightGevent): Boolean;
  begin
    FLock.Acquire;
    Result := Dequeue(E);
    FLock.Release;
  end;

begin
  if _Dequeue(E) then
    try
      case Method of
        smDefault:
          E.SetEvent(FAsync);
        smForceAsync:
          E.SetEvent(True);
        smForceSync:
          E.SetEvent(False);
      end;
    finally
      E._Release;
    end;
end;

procedure TLightCondVar.LockedWait(Unlocking: TPasMPSpinLock);
var
  E: TLightGevent;
begin
  E := TLightGevent.Create;
  E._AddRef;
  try
    FLock.Acquire;
    Enqueue(E);
    FLock.Release;
    if Assigned(Unlocking) then
      Unlocking.Release;
    E.WaitEvent;
  finally
    E._Release
  end;
end;

procedure TLightCondVar.Signal(const Method: TSyncMethod);
begin
  FSignalRoutine(Method)
end;

procedure TLightCondVar.Unlock;
begin
  if Assigned(FLock) then
    FLock.Release
end;

procedure TLightCondVar.UnLockedBroadcast(const Method: TSyncMethod);
var
  E: TLightGevent;
begin
  while Dequeue(E) do
    try
      case Method of
        smDefault:
          E.SetEvent(FAsync);
        smForceAsync:
          E.SetEvent(True);
        smForceSync:
          E.SetEvent(False);
      end;
    finally
      E._Release;
    end;
end;

procedure TLightCondVar.UnLockedSignal(const Method: TSyncMethod);
var
  E: TLightGevent;
begin
  if Dequeue(E) then
    try
      case Method of
        smDefault:
          E.SetEvent(FAsync);
        smForceAsync:
          E.SetEvent(True);
        smForceSync:
          E.SetEvent(False);
      end;
    finally
      E._Release;
    end;
end;

procedure TLightCondVar.UnLockedWait(Unlocking: TPasMPSpinLock);
var
  E: TLightGevent;
begin
  E := TLightGevent.Create;
  E._AddRef;
  try
    Enqueue(E);
    if Assigned(Unlocking) then
      Unlocking.Release;
    E.WaitEvent;
  finally
    E._Release
  end;
end;

procedure TLightCondVar.Wait(Unlocking: TPasMPSpinLock);
begin
  FWaitRoutine(Unlocking)
end;

{ TLocalContextService }

function TLocalContextService.GetDeadLockExceptionClass: TExceptionClass;
begin
  Result := FDeadLockExceptionClass;
  if not Assigned(Result) then
    Result := StdDeadLockException;
end;

function TLocalContextService.Refresh(A: TObject): IGCObject;
begin
  FRef := Greenlets.GC(A);
  Result := FRef;
end;

{ TLeaveLockLogger }

procedure TLeaveLockLogger.Check(const Msg: string);
begin
  Inc(FCounter);
  if FCounter >= MAX_COUNT_FACTOR then
    raise StdLeaveLockException.Create(Msg);
end;

{ TSingleThreadSyncChannel<T>.TContract }

function TSingleThreadSyncChannel<T>.TContract.PullSmartObj: IGCObject;
begin
  Result := SmartObj;
  SmartObj := nil;
end;

procedure TSingleThreadSyncChannel<T>.TContract.PushSmartObj(
  Value: IGCObject);
begin
  SmartObj := Value
end;

{ TFanOutImpl<T> }

constructor TFanOutImpl<T>.Create(Input: IReadOnly<T>);
begin
  FLock := TCriticalSection.Create;
  FInflateList := TList<TChannelDescr>.Create;
  FOnUpdated := TGevent.Create;
  FBufSize := Input.GetBufSize;
  FWorkerCtxReady := TGevent.Create(True);
  FWorker := TSymmetric<IReadChannel>.Spawn(Routine, Input);
  FWorkerCtxReady.WaitFor;
end;

destructor TFanOutImpl<T>.Destroy;
var
  Descr: TChannelDescr;
begin
  FLock.Acquire;
  for Descr in FInflateList do
    Descr.Token.Deactivate;
  FLock.Release;
  FWorker.Kill;
  FInflateList.Free;
  FWorkerCtxReady.Free;
  FLock.Free;
  FOnUpdated.Free;
  inherited;
end;

procedure TFanOutImpl<T>.DieCb(ID: Integer);
var
  Descr: TChannelDescr;
  Index: Integer;
begin
  FLock.Acquire;
  try
    Index := 0;
    while Index < FInflateList.Count do begin
      Descr := FInflateList[Index];
      if Descr.ID = ID then begin
        Descr.Channel.Close;
      end;
      _Release;
      Inc(Index);
    end;
  finally
    FLock.Release
  end;
end;

function TFanOutImpl<T>.GenerateID: Integer;
begin
  FLock.Acquire;
  Inc(FLastID);
  Result := FLastID;
  FLock.Release;
end;

function TFanOutImpl<T>.Inflate(const BufSize: Integer): IReadOnly<T>;
var
  Descr: TChannelDescr;
  ChanBufSz: LongWord;
begin
  Descr.SyncImpl := nil;
  Descr.AsyncImpl := nil;
  Descr.ID := GenerateID;
  Descr.Token := TLiveTokenImpl.Create(Descr.ID, DieCb);
  if BufSize < 0 then
    ChanBufSz := FBufSize
  else
    ChanBufSz := BufSize;
  if ChanBufSz = 0 then begin
    Descr.SyncImpl := TSyncChannel<T>.Create(True);
    Descr.SyncImpl.FLiveToken := Descr.Token;
    Descr.Channel := Descr.SyncImpl;
  end
  else begin
    Descr.AsyncImpl := TAsyncChannel<T>.Create(ChanBufSz);
    Descr.AsyncImpl.FLiveToken := Descr.Token;
    Descr.Channel := Descr.AsyncImpl;
  end;
  Inc(Descr.Channel.FWritersNum);
  Descr.Channel.FWriters.Add(FWorkerContext, TContextRef.Create(True, True));

  //(False, True) -> error at form
  Descr.Channel.Freaders.Add(Descr.Channel.FOwnerContext, TContextRef.Create(True, True));
  FLock.Acquire;
  try
    FInflateList.Add(Descr);
    _AddRef;
    if ChanBufSz = 0 then
      Result := Descr.SyncImpl.ReadOnly
    else
      Result := Descr.AsyncImpl.ReadOnly;
  finally
    FLock.Release;
  end;

  FOnUpdated.SetEvent(False);
end;

procedure TFanOutImpl<T>.Routine(const Input: IReadOnly<T>);
var
  Data: T;
  Index, ChanCount: Integer;
begin
  FWorkerContext := TCustomChannel<T>.GetContextUID;
  FWorkerCtxReady.SetEvent;
  try
    FOnUpdated.WaitFor;
    for Data in Input do begin
      FLock.Acquire;
      try
        Index := 0;
        ChanCount := FInflateList.Count;
        while Index < FInflateList.Count do begin
          with FInflateList[Index] do begin
            if not Channel.IsClosed and Token.IsLive then begin
              try
                Channel.SetDeadlockExceptionClass(TSoftDeadLock);
                if Channel.InternalWrite(Data, 0) then
                  Inc(Index)
                else begin
                  FInflateList.Delete(Index);
                  Dec(ChanCount);
                end;
              except
                on E: TSoftDeadLock do begin
                  Channel.Close;
                end;
                on E: EChannelDeadLock do begin
                  Channel.Close;
                end;
                on E: EChannelLeaveLock do begin
                  Channel.Close;
                end;
              end;
            end
            else begin
              FInflateList.Delete(Index);
              Dec(ChanCount);
            end
          end;
        end;
      finally
        FLock.Release;
      end;
      while ChanCount = 0 do begin
        FOnUpdated.WaitFor;
        FLock.Acquire;
        ChanCount := FInflateList.Count;
        FLock.Release;
      end;
    end;
  finally
    FLock.Acquire;
    try
      for Index := 0 to FInflateList.Count-1 do
        FInflateList[Index].Channel.Close;
    finally
      FLock.Release;
    end;
  end;
end;

{ TLiveTokenImpl }

constructor TLiveTokenImpl.Create(ID: Integer; const Cb: TOnDieEvent);
begin
  FID := ID;
  FIsLive := True;
  FCb := Cb;
  FLock := TCriticalSection.Create;
end;

function TLiveTokenImpl.IsLive: Boolean;
begin
  Result := FIsLive
end;

procedure TLiveTokenImpl.Deactivate;
begin
  FLock.Acquire;
  FCb := nil;
  FLock.Release;
end;

destructor TLiveTokenImpl.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TLiveTokenImpl.Die;
begin
  FLock.Acquire;
  try
    if Assigned(FCb) and FIsLive then begin
      FIsLive := False;
      FCb(Self.FID)
    end;
  finally
    FLock.Release;
  end;
end;

{ TContextRef }

function TContextRef.AddRef(Accum: Integer): Integer;
begin
  Inc(FRefCount, Accum);
  Result := FRefCount;
end;

constructor TContextRef.Create(const Active: Boolean; const IsOwnerContext: Boolean);
begin
  FActive := Active;
  if Active then
    FRefCount := 1
  else
    FRefCount := 0;
  FIsOwner := IsOwnerContext;
  if FIsOwner then begin
    //FOwnerToggle := True;
    //FRefCount := 0;
  end;
end;

function TContextRef.GetActive: Boolean;
begin
  Result := FActive
end;

function TContextRef.GetRefCount: Integer;
begin
  Result := FRefCount
end;

function TContextRef.Release(Accum: Integer): Integer;
begin
  Dec(FRefCount, Accum);
  Result := FRefCount;
end;

procedure TContextRef.SetActive(const Value: Boolean);
begin
  FActive := Value
end;

{ TCustomChannel<T>.TPendingOperations<T> }

destructor TCustomChannel<T>.TPendingOperations<Y>.Destroy;
begin
  if Assigned(FPendingReader) then begin
    FPendingReader.Kill;
    FPendingReader := nil;
  end;
  if Assigned(FPendingWriter) then begin
    FPendingWriter.Kill;
    FPendingWriter := nil;
  end;
  FReaderFuture := nil;
  FWriterFuture := nil;
  inherited;
end;

initialization
  StdDeadLockException := EChannelDeadLock;
  StdLeaveLockException := EChannelLeaveLock;

end.
