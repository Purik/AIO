// **************************************************************************************************
// Delphi Aio Library.
// Unit Hub
// https://github.com/Purik/AIO

// The contents of this file are subject to the Apache License 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
//
// The Original Code is Hub.pas.
//
// Contributor(s):
// Pavel Minenkov
// Purik
// https://github.com/Purik
//
// The Initial Developer of the Original Code is Pavel Minenkov [Purik].
// All Rights Reserved.
//
// **************************************************************************************************
unit Hub;

interface
uses Classes, SysUtils,  SyncObjs, {$IFDEF LOCK_FREE} PasMP, {$ENDIF}
  {$IFDEF FPC} fgl {$ELSE}Generics.Collections,  System.Rtti{$ENDIF},
  GarbageCollector, GInterfaces;

type

  THub = class(TCustomHub)
  strict private
  type
    TTaskKind = (tkMethod, tkIntfMethod, tkProc);

    { TTask }

    TTask = record
      Kind: TTaskKind;
      Method: TThreadMethod;
      Intf: IInterface;
      Proc: TTaskProc;
      Arg: Pointer;
      procedure Init(const Method: TThreadMethod); overload;
      procedure Init(Intf: IInterface; const Method: TThreadMethod); overload;
      procedure Init(const Proc: TTaskProc; Arg: Pointer); overload;
      {$IFDEF FPC}
      class operator = (const a,b : TTask): Boolean;
      {$ENDIF}
    end;
    TQueue = {$IFDEF DCC}TList<TTask>{$ELSE}TFPGList<TTask>{$ENDIF};
    procedure GetAddresses(const Task: TThreadMethod; out Obj: TObject;
      out MethodAddr: Pointer); inline;
  var
    FQueue: TQueue;
    FAccumQueue: TQueue;
    FLoopExit: Boolean;
    FName: string;
    FLock: SyncObjs.TCriticalSection;
    FLS: Pointer;
    FGC: Pointer;
    FIsSuspended: Boolean;
    {$IFDEF LOCK_FREE}
    FLockFreeQueue: TPasMPUnboundedQueue;
    {$ENDIF}
    procedure Clean;
    procedure Swap(var A1, A2: TQueue);
  protected
    procedure Lock; inline;
    procedure Unlock; inline;
    function TryLock: Boolean; inline;
    function ServeTaskQueue: Boolean; dynamic;
    procedure AfterSwap; dynamic;
  public
    constructor Create;
    destructor Destroy; override;
    property Name: string read FName write FName;
    property IsSuspended: Boolean read FIsSuspended write FIsSuspended;
    function  HLS(const Key: string): TObject; override;
    procedure HLS(const Key: string; Value: TObject); override;
    function  GC(A: TObject): IGCObject; override;
    procedure EnqueueTask(const Task: TThreadMethod); override;
    procedure EnqueueTask(const Task: TTaskProc; Arg: Pointer); override;
    procedure Pulse; override;
    procedure LoopExit; override;
    procedure Loop(const Cond: TExitCondition; Timeout: LongWord = INFINITE); override;
    procedure Loop(const Cond: TExitConditionStatic; Timeout: LongWord = INFINITE); override;
    procedure Switch; override;
  end;

  TSingleThreadHub = class(THub)
  type
    TMultiplexorEvent = (meError, meEvent, meSync, meIO, meWinMsg,
      meTimer, meWaitTimeout);
    TMultiplexorEvents = set of TMultiplexorEvent;
  const
    ALL_EVENTS: TMultiplexorEvents = [Low(TMultiplexorEvent)..High(TMultiplexorEvent)];
  private
  type
    TTimeoutRoutine = function(Timeout: LongWord): Boolean of object;
  var
    FEvents: Pointer;
    FReadFiles: Pointer;
    FWriteFiles: Pointer;
    FTimeouts: Pointer;
    FWakeMainThread: TNotifyEvent;
    FThreadId: LongWord;
    FTimerFlag: Boolean;
    FIOFlag: Boolean;
    FIsDef: Boolean;
    FProcessWinMsg: Boolean;
    FSyncEvent: TEvent;
    FServeRoutine: TTimeoutRoutine;
    procedure SetTriggerFlag(const TimerFlag, IOFlag: Boolean);
    procedure WakeUpThread(Sender: TObject);
    procedure SetupEnviron;
    procedure BeforeServe;inline;
    procedure AfterServe; inline;
    function ServeAsDefHub(Timeout: LongWord): Boolean;
    function ServeHard(Timeout: LongWord): Boolean;
  protected
    function ServeMultiplexor(TimeOut: LongWord): TMultiplexorEvent; dynamic;
  public
    constructor Create;
    destructor Destroy; override;
    // IO files, sockets, com-ports, pipes, etc.
    procedure Cancel(Fd: THandle); override;
    function Write(Fd: THandle; Buf: Pointer; Len: LongWord; const Cb: TIOCallback; Data: Pointer; Offset: Int64 = -1): Boolean; override;
    function WriteTo(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean; override;
    function Read(Fd: THandle; Buf: Pointer; Len: LongWord; const Cb: TIOCallback; Data: Pointer; Offset: Int64 = -1): Boolean; override;
    function ReadFrom(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean; override;
    // IO timeouts and timers
    function CreateTimer(const Cb: TInervalCallback; Data: Pointer; Interval: LongWord): THandle; override;
    procedure DestroyTimer(Id: THandle); override;
    function CreateTimeout(const Cb: TInervalCallback; Data: Pointer; Interval: LongWord): THandle; override;
    procedure DestroyTimeout(Id: THandle); override;
    // Event objects
    function  AddEvent(Ev: THandle; const Cb: TEventCallback; Data: Pointer): Boolean; override;
    procedure RemEvent(Ev: THandle); override;
    // services
    function Serve(TimeOut: LongWord): Boolean; override;
    function Wait(TimeOut: LongWord; const Events: TMultiplexorEvents=[];
      const ProcessWinMsg: Boolean = True): TMultiplexorEvent;
    procedure Pulse; override;
  end;

function GetCurrentHub: TCustomHub;
function DefHub(ThreadID: LongWord = 0): TSingleThreadHub; overload;
function DefHub(Thread: TThread): TSingleThreadHub; overload;

var
  HubInfrasctuctureEnable: Boolean;
{$IFDEF DEBUG}
  IOEventTupleCounter: Integer;
  IOFdTupleCounter: Integer;
  IOTimeTupleCounter: Integer;
{$ENDIF}

implementation
uses Math, GreenletsImpl, Greenlets, sock,
  {$IFDEF MSWINDOWS}
    {$IFDEF DCC}Winapi.Windows{$ELSE}windows{$ENDIF}
  {$ELSE}
  // TODO
  {$ENDIF};

const
  NANOSEC_PER_MSEC = 1000000;

type

  TObjMethodStruct = packed record
    Code: Pointer;
    Data: TObject;
  end;

  THubMap = {$IFDEF DCC}TDictionary{$ELSE}TFPGMap{$ENDIF}<LongWord, TSingleThreadHub>;

  TEventTuple = record
    Event: THandle;
    Cb: TEventCallback;
    Data: Pointer;
    Hub: THub;
    procedure Trigger(const Aborted: Boolean);
  end;

  PEvents = ^TEvents;
  TEvents = record
  const
    MAX_EV_COUNT = 1024;
  var
    SyncEvent: TEvent;
    FBuf: array[0..MAX_EV_COUNT-1] of THandle;
    FCb: array[0..MAX_EV_COUNT-1] of TEventCallback;
    FData: array[0..MAX_EV_COUNT-1] of Pointer;
    FHub: array[0..MAX_EV_COUNT-1] of THub;
    FBufSize: Integer;
    procedure Enqueue(Hnd: THandle; const Cb: TEventCallback;
      Data: Pointer; Hub: THub);
    procedure DequeueByIndex(Index: Integer); overload;
    procedure Dequeue(Hnd: THandle); overload;
    function Buf: Pointer; inline;
    function TupleByIndex(Index: Integer): TEventTuple; inline;
    function Find(Hnd: THandle; out Index: Integer): Boolean; inline;
    function BufSize: LongWord; inline;
    function IsInitialized: Boolean; inline;
    procedure Initialize; inline;
    procedure DeInitialize; inline;
  end;

  PFileTuple = ^TFileTuple;
  TFileTuple = record
    Fd: THandle;
    ReadData: Pointer;
    WriteData: Pointer;
    ReadCb: TIOCallback;
    WriteCb: TIOCallback;
    Hub: THub;
    Active: Boolean;
    CleanTime: TTime;
    {$IFDEF MSWINDOWS}
    Overlap: TOverlapped;
    {$ENDIF}
    procedure RecalcCleanTime;
    procedure Trigger(ErrorCode: Integer; Len: Integer; const Op: TIOOperation);
  end;

  PFiles = ^TFiles;
  TFiles = record
  const
    TRASH_CLEAR_TIMEOUT_MINS = 30;
  type
    TMap = {$IFDEF DCC}TDictionary{$ELSE}TFPGMap{$ENDIF}<THandle, PFileTuple>;
    FList = {$IFDEF DCC}TList{$ELSE}TFPGList{$ENDIF}<PFileTuple>;
  var
    FMap: TMap;
    // in input-output operations callbacks can come to private
    // descriptors. This is found for sockets
    FTrash: FList;
    FTrashLAstClean: TTime;
    procedure TrashClean(const OnlyByTimeout: Boolean = True);
    function IsInitialized: Boolean;
    procedure Initialize;
    procedure Deinitialize;
    function Enqueue(Fd: THandle; const Op: TIOOperation;
      const Cb: TIOCallback; Data: Pointer; Hub: THub): PFileTuple; overload;
    procedure Dequeue(const Fd: THandle);
    function Find(Fd: THandle): Boolean; overload;
    function Find(Id: THandle; out Tup: PFileTuple): Boolean; overload;
  end;

  PTimeoutTuple = ^TTimeoutTuple;
  TTimeoutTuple = record
    Id: THandle;
    Cb: TInervalCallback;
    Data: Pointer;
    Hub: THub;
    procedure Trigger;
  end;

  TRawGreenletPImpl = class(TRawGreenletImpl);

  PTimeouts = ^TTimeouts;
  TTimeouts = record
  type
    TMap = {$IFDEF DCC}TDictionary{$ELSE}TFPGMap{$ENDIF}<THandle, PTimeoutTuple>;
  var
    FMap: TMap;
    function IsInitialized: Boolean;
    procedure Initialize;
    procedure Deinitialize;
  public
    function Enqueue(Id: THandle; const Cb: TInervalCallback;
      Data: Pointer; Hub: THub): PTimeoutTuple;
    procedure Dequeue(Id: THandle);
    function Find(Id: THandle): Boolean; overload;
  end;

threadvar
  CurrentHub: THub;

var
  DefHubsLock: SyncObjs.TCriticalSection;
  DefHubs: THubMap;

{$IFDEF MSWINDOWS}
  {$I iocpwin.inc}
var
  WsaDataOnce: TWSADATA;
function GetCurrentProcessorNumber: DWORD; external kernel32 name 'GetCurrentProcessorNumber';
{$ENDIF}

function GetCurrentHub: TCustomHub;
begin
  if Assigned(CurrentHub) then
    Result := CurrentHub
  else
    Result := DefHub;
end;

function DefHub(ThreadID: LongWord): TSingleThreadHub;
var
  ID: LongWord;
  CintainsKey: Boolean;
  {$IFNDEF DCC}
  Index: Integer;
  {$ENDIF}
begin
  if not Assigned(DefHubs) then
    Exit(nil);
  if ThreadID = 0 then
    ID := TThread.CurrentThread.ThreadID
  else
    ID := ThreadID;
  DefHubsLock.Acquire;
  try
    {$IFDEF DCC}
    CintainsKey := DefHubs.ContainsKey(ID);
    {$ELSE}
    CintainsKey := DefHubs.Find(ID, Index);
    {$ENDIF}
    if CintainsKey then
      Result := DefHubs[ID]
    else begin
      Result := TSingleThreadHub.Create;
      Result.FIsDef := True;
      Result.FThreadId := ID;
      DefHubs.Add(ID, Result);
    end;
  finally
    DefHubsLock.Release
  end;
end;

function DefHub(Thread: TThread): TSingleThreadHub;
begin
  Result := DefHub(Thread.ThreadID)
end;

{$IFDEF MSWINDOWS}
procedure STFileIOCompletionReadRoutine(dwErrorCode: DWORD;
  dwNumberOfBytesTransfered:DWORD; lpOverlapped: POverlapped); stdcall;
var
  Tuple: PFileTuple;
begin
  Tuple := PFileTuple(lpOverlapped.hEvent);
  if not Tuple.Active then begin
    Tuple.RecalcCleanTime;
    Exit;
  end;
  TSingleThreadHub(Tuple.Hub).SetTriggerFlag(False, True);
  Tuple.Trigger(dwErrorCode, dwNumberOfBytesTransfered, ioRead);
end;

procedure STFlaggedFileIOCompletionReadRoutine(dwErrorCode: DWORD;
  dwNumberOfBytesTransfered:DWORD; lpOverlapped: POverlapped; Flags: DWORD); stdcall;
var
  Tuple: PFileTuple;
begin
  Tuple := PFileTuple(lpOverlapped.hEvent);
  if not Tuple.Active then begin
    Tuple.RecalcCleanTime;
    Exit;
  end;
  TSingleThreadHub(Tuple.Hub).SetTriggerFlag(False, True);
  Tuple.Trigger(dwErrorCode, dwNumberOfBytesTransfered, ioRead);
end;

procedure STFileIOCompletionWriteRoutine(dwErrorCode: DWORD;
  dwNumberOfBytesTransfered:DWORD; lpOverlapped: POverlapped); stdcall;
var
  Tuple: PFileTuple;
begin
  Tuple := PFileTuple(lpOverlapped.hEvent);
  if not Tuple.Active then begin
    Tuple.RecalcCleanTime;
    Exit;
  end;
  TSingleThreadHub(Tuple.Hub).SetTriggerFlag(False, True);
  Tuple.Trigger(dwErrorCode, dwNumberOfBytesTransfered, ioWrite);
end;

procedure STFlaggedFileIOCompletionWriteRoutine(dwErrorCode: DWORD;
  dwNumberOfBytesTransfered:DWORD; lpOverlapped: POverlapped; Flags: DWORD); stdcall;
var
  Tuple: PFileTuple;
begin
  Tuple := PFileTuple(lpOverlapped.hEvent);
  if not Tuple.Active then begin
    Tuple.RecalcCleanTime;
    Exit;
  end;
  TSingleThreadHub(Tuple.Hub).SetTriggerFlag(False, True);
  Tuple.Trigger(dwErrorCode, dwNumberOfBytesTransfered, ioWrite);
end;

procedure STTimerAPCProc(lpArgToCompletionRoutine: Pointer;
  dwTimerLowValue: DWORD; dwTimerHighValue: DWORD); stdcall;
var
  Tuple: PTimeoutTuple;
begin
  Tuple := lpArgToCompletionRoutine;
  TSingleThreadHub(Tuple.Hub).SetTriggerFlag(True, False);
  Tuple.Trigger;
end;

{$ENDIF}

function GetEvents(Hub: TSingleThreadHub): PEvents; inline;
begin
  Result := PEvents(Hub.FEvents)
end;

function GetReadFiles(Hub: TSingleThreadHub): PFiles; inline;
begin
  Result := PFiles(Hub.FReadFiles)
end;

function GetWriteFiles(Hub: TSingleThreadHub): PFiles; inline;
begin
  Result := PFiles(Hub.FWriteFiles)
end;

function GetTimeouts(Hub: TSingleThreadHub): PTimeouts; inline;
begin
  Result := PTimeouts(Hub.FTimeouts)
end;

{ THub }

procedure THub.AfterSwap;
begin

end;

function THub.ServeTaskQueue: Boolean;
var
  I: Integer;
  Arg: Pointer;
  Proc: TTaskProc;
  OldHub: THub;
  Tsk: TTask;

  procedure Process(var Tsk: TTask);
  begin
    case Tsk.Kind of
      tkMethod: begin
        Tsk.Method();
      end;
      tkIntfMethod: begin
        if Assigned(Tsk.Intf) then begin
          Tsk.Method();
          Tsk.Intf := nil;
        end;
      end;
      tkProc: begin
        Proc := Tsk.Proc;
        Arg := Tsk.Arg;
        Proc(Arg)
      end;
    end;
  end;

begin
  Result := False;
  OldHub := CurrentHub;
  try
    CurrentHub := Self;

    {$IFDEF MSWINDOWS}
    if TThread.CurrentThread.ThreadID = MainThreadID then begin
      Result := CheckSynchronize(0)
    end;
    {$ENDIF}

    {$IFDEF LOCK_FREE}
    try
      while FLockFreeQueue.Dequeue(Tsk) do begin
        Result := True;
        Process(Tsk)
      end;
    finally
      while FLockFreeQueue.Dequeue(Tsk) do ;
    end;
    {$ELSE}
    // transaction commit to write and transfer data
    // in transaction for reading - to reduce problems with race condition
    Swap(FQueue, FAccumQueue);
    Result := Result or (FQueue.Count > 0);
    if FQueue.Count > 0 then
      try
        for I := 0 to FQueue.Count-1 do begin
          Tsk := FQueue[I];
          Process(Tsk);
        end;
      finally
        // obligatory it is necessary to clean, differently at Abort or Exception
        // on the iteration trace. queues will come up with "outdated" calls
        FQueue.Clear;
      end;
    {$ENDIF}
  finally
    CurrentHub := OldHub;
  end;
end;

procedure THub.Clean;

  procedure CleanQueue(A: TQueue);
  var
    I: Integer;
  begin
    for I := 0 to A.Count-1 do
      with A[I] do begin
        case Kind of
          tkIntfMethod: begin
            //Intf._Release;
          end;
          tkMethod:;
          tkProc: ;
        end;
      end;
    A.Clear;
  end;

begin
  Lock;
  try
    CleanQueue(FAccumQueue);
    CleanQueue(FQueue);
  finally
    Unlock
  end;
end;

procedure THub.Swap(var A1, A2: TQueue);
var
  Tmp: TQueue;
begin
  Lock;
  try
    Tmp := A1;
    A1 := A2;
    A2 := Tmp;
  finally
    AfterSwap;
    Unlock;
  end;
end;

procedure THub.Lock;
begin
  {$IFDEF DCC}
  TMonitor.Enter(FLock);
  {$ELSE}
  FLock.Acquire;
  {$ENDIF}
end;

procedure THub.Unlock;
begin
  {$IFDEF DCC}
  TMonitor.Exit(FLock);
  {$ELSE}
  FLock.Release;
  {$ENDIF}
end;

function THub.TryLock: Boolean;
begin
  {$IFDEF DCC}
  Result := TMonitor.TryEnter(FLock);
  {$ELSE}
  Result := FLock.TryEnter
  {$ENDIF}
end;

constructor THub.Create;
begin
  inherited Create;
  FQueue := TQueue.Create;
  FAccumQueue := TQueue.Create;
  FLock := SyncObjs.TCriticalSection.Create;
  FLS := TLocalStorage.Create;
  FGC := TGarbageCollector.Create;
  GetJoiner(Self);
  {$IFDEF LOCK_FREE}
  FLockFreeQueue := TPasMPUnboundedQueue.Create(SizeOf(TTask));
  {$ENDIF}
end;

destructor THub.Destroy;
begin
  Clean;
  FQueue.Free;
  FAccumQueue.Free;
  TLocalStorage(FLS).Free;
  TGarbageCollector(FGC).Free;
  FLock.Free;
  {$IFDEF LOCK_FREE}
  FLockFreeQueue.Free;
  {$ENDIF}
  inherited;
end;

function THub.HLS(const Key: string): TObject;
begin
  Result := TLocalStorage(FLS).GetValue(Key);
end;

procedure THub.HLS(const Key: string; Value: TObject);
var
  Obj: TObject;
begin
  if TLocalStorage(FLS).IsExists(Key) then begin
    Obj := TLocalStorage(FLS).GetValue(Key);
    Obj.Free;
    TLocalStorage(FLS).UnsetValue(Key);
  end;
  if Assigned(Value) then
    TLocalStorage(FLS).SetValue(Key, Value)
end;

function THub.GC(A: TObject): IGCObject;
var
  G: TGarbageCollector;
begin
  G := TGarbageCollector(FGC);
  Result := G.SetValue(A);
end;

procedure THub.EnqueueTask(const Task: TTaskProc; Arg: Pointer);
var
  Tsk: TTask;
  {$IFDEF LOCK_FREE}
  Q: TPasMPUnboundedQueue;
  {$ENDIF}
begin
  Tsk.Init(Task, Arg);
  {$IFDEF LOCK_FREE}
  FLockFreeQueue.Enqueue(Tsk);
  {$ELSE}
  Lock;
  try
    FAccumQueue.Add(Tsk);
  finally
    Unlock
  end;
  {$ENDIF}
  Pulse;
end;

procedure THub.EnqueueTask(const Task: TThreadMethod);
var
  Obj: TObject;
  MethodAddr: Pointer;
  Intf: IInterface;
  Tsk: TTask;
  {$IFDEF LOCK_FREE}
  Q: TPasMPUnboundedQueue;
  {$ENDIF}
begin
  GetAddresses(Task, Obj, MethodAddr);
  {$IFDEF DEBUG}
  Assert(not Obj.InheritsFrom(TRawGreenletImpl), 'Enqueue Greenlet methods only by Proxy');
  {$ENDIF}
  if Obj.GetInterface(IInterface, Intf) then
    Tsk.Init(Intf, Task)
  else
    Tsk.Init(Task);
  {$IFDEF LOCK_FREE}
  if Assigned(Intf) then
    Intf._AddRef;
  FLockFreeQueue.Enqueue(Tsk);
  {$ELSE}
  Lock;
  try
    // write transaction
    FAccumQueue.Add(Tsk);
  finally
    Unlock;
  end;
  {$ENDIF}
  Pulse;
end;

procedure THub.GetAddresses(const Task: TThreadMethod; out Obj: TObject;
  out MethodAddr: Pointer);
var
  Struct: TObjMethodStruct absolute Task;
begin
  Obj := Struct.Data;
  MethodAddr := Struct.Code;
end;

procedure THub.Loop(const Cond: TExitCondition; Timeout: LongWord);
var
  Stop: TTime;
begin
  FLoopExit := False;
  Stop := Now + TimeOut2Time(Timeout);
  while not Cond() and (Now < Stop) and (not FLoopExit) do
    Serve(Time2TimeOut(Stop - Now))
end;

procedure THub.Loop(const Cond: TExitConditionStatic; Timeout: LongWord);
var
  Stop: TTime;
begin
  FLoopExit := False;
  Stop := Now + TimeOut2Time(Timeout);
  while not Cond() and (Now < Stop) and (not FLoopExit) do
    Serve(Time2TimeOut(Stop - Now))
end;

procedure THub.Switch;
begin
  if Greenlets.GetCurrent <> nil then begin
    TRawGreenletPImpl.Switch2RootContext
  end;
end;

procedure THub.LoopExit;
begin
  FLoopExit := True;
  Pulse;
end;

procedure THub.Pulse;
begin

end;

{ TSingleThreadHub }

function TSingleThreadHub.AddEvent(Ev: THandle; const Cb: TEventCallback;
  Data: Pointer): Boolean;
var
  Index: Integer;
  Tup: TEventTuple;
begin
  {$IFDEF MSWINDOWS}
  Result := GetEvents(Self).BufSize < (MAXIMUM_WAIT_OBJECTS-1);
  {$ELSE}
  Result := True;
  {$ENDIF}
  if GetEvents(Self).Find(Ev, Index) then begin
    Tup := GetEvents(Self).TupleByIndex(Index);
    if (@Tup.Cb <> @Cb) or (Tup.Data <> Data) then
      raise EHubError.CreateFmt('Handle %d already exists in demultiplexor queue', [Ev]);
  end;
  if Result then begin
    GetEvents(Self).Enqueue(Ev, Cb, Data, Self);
    Pulse;
  end;
end;

procedure TSingleThreadHub.AfterServe;
begin
  if Assigned(FWakeMainThread) then
    Classes.WakeMainThread := FWakeMainThread;
  if not FIsDef then
    FThreadId := 0;
end;

procedure TSingleThreadHub.BeforeServe;
begin
  if FIsDef then begin
    if FThreadId <> TThread.CurrentThread.ThreadID then
      raise EHubError.Create('Def Hub must be serving inside owner thread');
  end
  else begin
    if FThreadId <> 0 then
      raise EHubError.Create('Hub already serving by other thread');
    FThreadId := TThread.CurrentThread.ThreadID;
  end;
  SetupEnviron;
  if TThread.CurrentThread.ThreadID = MainThreadID then begin
    FWakeMainThread := Classes.WakeMainThread;
    Classes.WakeMainThread := Self.WakeUpThread;
  end;
end;

procedure TSingleThreadHub.Cancel(Fd: THandle);
var
  R, W: Boolean;
begin
  R := GetReadFiles(Self).Find(Fd);
  W := GetWriteFiles(Self).Find(Fd);
  if W or R then begin
    {$IFDEF MSWINDOWS}
    CancelIo(Fd);
    {$ELSE}

    {$ENDIF}
  end;
  if R then
    GetReadFiles(Self).Dequeue(Fd);
  if W then
    GetWriteFiles(Self).Dequeue(Fd);
end;

constructor TSingleThreadHub.Create;
begin
  inherited Create;
  SetupEnviron;
  FServeRoutine := ServeHard;
end;

function TSingleThreadHub.CreateTimeout(const Cb: TInervalCallback;
  Data: Pointer; Interval: LongWord): THandle;
var
  DueTime: Int64;
  TuplePtr: PTimeoutTuple;
begin
  {$IFDEF MSWINDOWS}
  Result := CreateWaitableTimer(nil, False, '');
  DueTime := Interval*(NANOSEC_PER_MSEC div 100);
  DueTime := DueTime * -1;
  TuplePtr := GetTimeouts(Self).Enqueue(Result, Cb, Data, Self);
  if not SetWaitableTimer(Result, DueTime, 0, @STTimerAPCProc, TuplePtr, False) then begin
     GetTimeouts(Self).Dequeue(Result);
  end;
  {$ELSE}

  {$ENDIF}
end;

function TSingleThreadHub.CreateTimer(const Cb: TInervalCallback; Data: Pointer;
  Interval: LongWord): THandle;
var
  DueTime: Int64;
  TuplePtr: PTimeoutTuple;
begin
  {$IFDEF MSWINDOWS}
  Result := CreateWaitableTimer(nil, False, '');
  DueTime := Interval*(NANOSEC_PER_MSEC div 100);
  DueTime := DueTime * -1;
  TuplePtr := GetTimeouts(Self).Enqueue(Result, Cb, Data, Self);
  if not SetWaitableTimer(Result, DueTime, Interval, @STTimerAPCProc, TuplePtr, False) then begin
     GetTimeouts(Self).Dequeue(Result);
  end;
  {$ELSE}

  {$ENDIF}
end;

destructor TSingleThreadHub.Destroy;
var
  ContainsKey: Boolean;
  {$IFNDEF DCC}
  Index: Integer;
  {$ENDIF}
begin
  if Assigned(FEvents) then begin
    GetEvents(Self).DeInitialize;
    FreeMem(FEvents, SizeOf(TEvents));
  end;
  if Assigned(FReadFiles) then begin
    GetReadFiles(Self).Deinitialize;
    FreeMem(FReadFiles, SizeOf(TFiles));
  end;
  if Assigned(FWriteFiles) then begin
    GetWriteFiles(Self).Deinitialize;
    FreeMem(FWriteFiles, SizeOf(TFiles));
  end;
  if Assigned(FTimeouts) then begin
    GetTimeouts(Self).Deinitialize;
    FreeMem(FTimeouts, SizeOf(TTimeouts));
  end;
  if FIsDef then begin
    DefHubsLock.Acquire;
    try
      {$IFDEF DCC}
      ContainsKey := DefHubs.ContainsKey(FThreadId);
      {$ELSE}
      ContainsKey := DefHubs.Find(FThreadId, Index);
      {$ENDIF}
      if ContainsKey then
        DefHubs.Remove(FThreadId);
    finally
      DefHubsLock.Release
    end;
  end;
  TRawGreenletPImpl.ClearContexts;
  CurrentHub := nil;
  inherited;
end;

procedure TSingleThreadHub.DestroyTimeout(Id: THandle);
begin
  {$IFDEF MSWINDOWS}
  if GetTimeouts(Self).Find(Id) then begin
     CancelWaitableTimer(Id);
     GetTimeouts(Self).Dequeue(Id);
  end
  {$ELSE}

  {$ENDIF}
end;

procedure TSingleThreadHub.DestroyTimer(Id: THandle);
begin
  {$IFDEF MSWINDOWS}
  if GetTimeouts(Self).Find(Id) then begin
    CancelWaitableTimer(Id);
    GetTimeouts(Self).Dequeue(Id);
  end;
  {$ELSE}

  {$ENDIF}
end;

procedure TSingleThreadHub.Pulse;
begin
  FSyncEvent.SetEvent;
end;

function TSingleThreadHub.ReadFrom(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean;
var
  TuplePtr: PFileTuple;
  Flags: DWORD;
  Buf_: WSABUF;
  RetValue: LongWord;
begin
  TuplePtr := GetReadFiles(Self).Enqueue(Fd, ioRead, Cb, Data, Self);
  Flags := MSG_PARTIAL;
  Buf_.len := Len;
  Buf_.buf := Buf;

  WSARecvFrom(Fd, @Buf_, 1, nil, Flags, Addr.AddrPtr,
    @Addr.AddrLen, @TuplePtr.Overlap, @STFlaggedFileIOCompletionReadRoutine);

  RetValue := WSAGetLastError;
  Result := RetValue = WSA_IO_PENDING;
  if not Result then begin
    GetReadFiles(Self).Dequeue(Fd);
  end;
end;

function TSingleThreadHub.Read(Fd: THandle; Buf: Pointer; Len: LongWord;
  const Cb: TIOCallback; Data: Pointer; Offset: Int64): Boolean;
var
  TuplePtr: PFileTuple;
begin
  TuplePtr := GetReadFiles(Self).Enqueue(Fd, ioRead, Cb, Data, Self);
  {$IFDEF MSWINDOWS}
  if Offset <> -1 then begin
    TuplePtr^.Overlap.Offset := Offset and $FFFFFFFF;
    TuplePtr^.Overlap.OffsetHigh := Offset shr 32;
  end;
  Result := ReadFileEx(Fd, Buf, Len, @TuplePtr^.Overlap, @STFileIOCompletionReadRoutine);
  if not Result then
    GetReadFiles(Self).Dequeue(Fd);
    {$IFDEF DEBUG}
    //raise EHubError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
    {$ENDIF}
  {$ELSE}

  {$ENDIF}
end;

procedure TSingleThreadHub.RemEvent(Ev: THandle);
begin
  GetEvents(Self).Dequeue(Ev);
end;

function TSingleThreadHub.ServeAsDefHub(Timeout: LongWord): Boolean;
var
  Stop: TTime;
  MxEvent: TMultiplexorEvent;
begin
  Stop := Now + TimeOut2Time(TimeOut);
  repeat
    if ServeTaskQueue then
      Exit(True)
    else begin
      FProcessWinMsg := True;
      MxEvent := ServeMultiplexor(Time2TimeOut(Stop - Now));
      Result := MxEvent <> meWaitTimeout;
      Result := Result or ServeTaskQueue;
    end;
  until (Now >= Stop) or Result;
end;

function TSingleThreadHub.ServeHard(Timeout: LongWord): Boolean;
begin
  BeforeServe;
  try
    Result := ServeAsDefHub(Timeout);
  finally
    AfterServe
  end;
  if FIsDef then
    FServeRoutine := ServeAsDefHub
end;

function TSingleThreadHub.Serve(TimeOut: LongWord): Boolean;
begin
  Result := FServeRoutine(TimeOut);
end;

function TSingleThreadHub.ServeMultiplexor(TimeOut: LongWord): TMultiplexorEvent;
const
  WM_QUIT = $0012;
  WM_CLOSE = $0010;
  WM_DESTROY = $0002;
  MWMO_ALERTABLE = $0002;
  MWMO_INPUTAVAILABLE = $0004;
var
  MultiplexorCode: LongWord;
  Event: TEventTuple;

  {$IFDEF MSWINDOWS}
  Msg: TMsg;

  function ProcessMultiplexorAnswer(Code: LongWord): TMultiplexorEvent;
  var
    Cnt: Integer;
  begin
    Result := meError;
    if Code = WAIT_FAILED then begin
      Cnt := GetEvents(Self).BufSize;
      if Cnt = 0 then
        raise EHubError.CreateFmt('Events.Count = 0', [])
      else
        raise EHubError.CreateFmt('IO.Serve with error: %s', [SysErrorMessage(GetLastError)]);
    end;
    if Code = 0 then begin
      Result := meSync;
    end
    else if InRange(Code, WAIT_OBJECT_0+1, WAIT_OBJECT_0+GetEvents(Self).BufSize-1) then begin
      Event := GetEvents(Self).TupleByIndex(Code);
      GetEvents(Self).DequeueByIndex(Code);
      Event.Trigger(False);
      Result := meEvent;
    end
    else if InRange(Code, WAIT_ABANDONED_0+1, WAIT_ABANDONED_0+GetEvents(Self).BufSize-1) then begin
      Event := GetEvents(Self).TupleByIndex(Code);
      GetEvents(Self).DequeueByIndex(Code);
      Event.Trigger(True);
      Result := meEvent;
    end;
  end;
  {$ENDIF}

begin
  Result := meError;
  {$IFDEF MSWINDOWS}
  if IsConsole or (TThread.CurrentThread.ThreadID <> MainThreadID) then begin
    MultiplexorCode := WaitForMultipleObjectsEx(GetEvents(Self).BufSize,
      {$IFDEF DCC}PWOHandleArray{$ELSE}LPHANDLE{$ENDIF}(GetEvents(Self).Buf),
      False, Timeout, True);
  end
  else begin
    MultiplexorCode := MsgWaitForMultipleObjectsEx(GetEvents(Self).BufSize, GetEvents(Self).Buf^,
      Timeout, QS_ALLEVENTS or QS_ALLINPUT, MWMO_ALERTABLE or MWMO_INPUTAVAILABLE);
  end;
  case MultiplexorCode of
    WAIT_TIMEOUT:
      Result := meWaitTimeout;
    WAIT_IO_COMPLETION: begin
      if FTimerFlag then
        Result := meTimer
      else if FIOFlag then
        Result := meIO
    end;
    else begin
      if MultiplexorCode = GetEvents(Self).BufSize then
        Result := meWinMsg
      else
        Result := ProcessMultiplexorAnswer(MultiplexorCode);
    end;
  end;
  if Result = meWinMsg then begin
    if FProcessWinMsg then begin
      while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do begin
        TranslateMessage(Msg);
        DispatchMessage(Msg);
        if Msg.message in [WM_QUIT, WM_CLOSE, WM_DESTROY] then begin
          CloseWindow(GetWindow(GetCurrentProcess, GW_HWNDFIRST));
          //Abort
        end
      end;
    end
  end;

  {$ELSE}

  {$ENDIF}
end;

procedure TSingleThreadHub.SetTriggerFlag(const TimerFlag, IOFlag: Boolean);
begin
  FTimerFlag := TimerFlag;
  FIOFlag := IOFlag;
end;

procedure TSingleThreadHub.SetupEnviron;
begin
  if not Assigned(FEvents) then begin
    FEvents := AllocMem(SizeOf(TEvents));
    FillChar(FEvents^, SizeOF(TEvents), 0);
  end;
  if not GetEvents(Self).IsInitialized then begin
    GetEvents(Self).Initialize;
    FSyncEvent := GetEvents(Self).SyncEvent;
  end;
  if not Assigned(FReadFiles) then begin
    FReadFiles := AllocMem(SizeOf(TFiles));
    FillChar(FReadFiles^, SizeOF(TFiles), 0);
  end;
  if not GetReadFiles(Self).IsInitialized then begin
    GetReadFiles(Self).Initialize;
  end;
  if not Assigned(FWriteFiles) then begin
    FWriteFiles := AllocMem(SizeOf(TFiles));
    FillChar(FWriteFiles^, SizeOF(TFiles), 0);
  end;
  if not GetWriteFiles(Self).IsInitialized then begin
    GetWriteFiles(Self).Initialize;
  end;
  if not Assigned(FTimeouts) then begin
    FTimeouts := AllocMem(SizeOf(TTimeouts));
    FillChar(FTimeouts^, SizeOF(TTimeouts), 0);
  end;
  if not GetTimeouts(Self).IsInitialized then begin
    GetTimeouts(Self).Initialize;
  end;
end;

function TSingleThreadHub.Wait(TimeOut: LongWord;
  const Events: TMultiplexorEvents; const ProcessWinMsg: Boolean): TMultiplexorEvent;
var
  Stop: TTime;
  LocalEvents: TMultiplexorEvents;
  IsTimeout: Boolean;
begin
  FProcessWinMsg := ProcessWinMsg;
  IsTimeout := False;
  if Events = [] then
    LocalEvents := ALL_EVENTS
  else
    LocalEvents := Events;
  BeforeServe;
  try
    Stop := Now + TimeOut2Time(TimeOut);
    repeat
      Result := ServeMultiplexor(Time2TimeOut(Stop - Now));
      IsTimeout := (TimeOut <> INFINITE) and (Now >= Stop);
    until IsTimeout or (Result in LocalEvents);
  finally
    if IsTimeout then
      Result := meWaitTimeout;
    AfterServe
  end;
end;

procedure TSingleThreadHub.WakeUpThread(Sender: TObject);
begin
  GetEvents(Self).SyncEvent.SetEvent;
end;

function TSingleThreadHub.WriteTo(Fd: THandle; Buf: Pointer; Len: LongWord; const Addr: TAnyAddress; const Cb: TIOCallback; Data: Pointer): Boolean;
var
  TuplePtr: PFileTuple;
  Flags: DWORD;
  BufWsa: WSABUF;
  RetValue: LongWord;
  SentSz: LongWord;
begin
  TuplePtr := GetWriteFiles(Self).Enqueue(Fd, ioWrite, Cb, Data, Self);
  Flags := 0;
  BufWsa.buf := Buf;
  BufWsa.len := Len;
  SentSz := 0;
  WSASendTo(Fd, @BufWsa, 1, SentSz, Flags, Addr.AddrPtr,
    Addr.AddrLen, @TuplePtr.Overlap, @STFlaggedFileIOCompletionWriteRoutine);
  RetValue := WSAGetLastError;
  Result := RetValue = WSA_IO_PENDING;
  if not Result then begin
    GetWriteFiles(Self).Dequeue(Fd);
  end;
end;

function TSingleThreadHub.Write(Fd: THandle; Buf: Pointer; Len: LongWord;
  const Cb: TIOCallback; Data: Pointer; Offset: Int64): Boolean;
var
  TuplePtr: PFileTuple;
begin
  TuplePtr := GetWriteFiles(Self).Enqueue(Fd, ioWrite, Cb, Data, Self);
  {$IFDEF MSWINDOWS}
  if Offset <> -1 then begin
    TuplePtr^.Overlap.Offset := Offset and $FFFFFFFF;
    TuplePtr^.Overlap.OffsetHigh := Offset shr 32;
  end;
  Result := WriteFileEx(Fd, Buf, Len, TuplePtr^.Overlap, @STFileIOCompletionWriteRoutine);
  if not Result then begin
    GetWriteFiles(Self).Dequeue(Fd);
    {$IFDEF DEBUG}
    //raise EHubError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
    {$ENDIF}
  end;
  {$ELSE}

  {$ENDIF}
end;

{ TEvents }

function TEvents.Buf: Pointer;
begin
  Result := @FBuf;
end;

function TEvents.BufSize: LongWord;
begin
  Result := FBufSize
end;

procedure TEvents.DeInitialize;
begin
  if not IsInitialized then
    Exit;
  Dequeue(THandle(SyncEvent.Handle));
  FreeAndNil(SyncEvent);
end;

procedure TEvents.Dequeue(Hnd: THandle);
var
  Index, I: Integer;
begin
  Index := -1;
  for I := 0 to FBufSize-1 do
    if FBuf[I] = Hnd then begin
      Index := I;
      Break;
    end;
  if Index <> -1 then begin
    DequeueByIndex(Index);
  end;
end;

procedure TEvents.DequeueByIndex(Index: Integer);
begin
  if Index >= FBufSize then
    Exit;
  if Index = FBufSize-1 then
    Dec(FBufSize)
  else begin
    Move(FBuf[Index+1], FBuf[Index], (FBufSize-Index-1)*SizeOf(THandle));
    Move(FCb[Index+1], FCb[Index], (FBufSize-Index-1)*SizeOf(TEventCallback));
    Move(FData[Index+1], FData[Index], (FBufSize-Index-1)*SizeOf(Pointer));
    Dec(FBufSize);
  end;
  {$IFDEF DEBUG}
  AtomicDecrement(IOEventTupleCounter);
  {$ENDIF}
end;

procedure TEvents.Enqueue(Hnd: THandle; const Cb: TEventCallback;
  Data: Pointer; Hub: THub);
begin
  if not Assigned(Cb) then
    Exit;
  FBuf[FBufSize] := Hnd;
  FCb[FBufSize] := Cb;
  FData[FBufSize] := Data;
  FHub[FBufSize] := Data;
  Inc(FBufSize);
  {$IFDEF DEBUG}
  AtomicIncrement(IOEventTupleCounter);
  {$ENDIF}
end;

function TEvents.Find(Hnd: THandle; out Index: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  Index := -1;
  for I := 0 to BufSize-1 do
    if FBuf[I] = Hnd then begin
      Index := I;
      Exit(True)
    end;
end;

procedure TEvents.Initialize;
begin
  if IsInitialized then
    Exit;
  SyncEvent := TEvent.Create(nil, False, False, '');
  FBufSize := 1;
  FBuf[0] := THandle(SyncEvent.Handle);
  {$IFDEF DEBUG}
  AtomicIncrement(IOEventTupleCounter);
  {$ENDIF}
end;

function TEvents.IsInitialized: Boolean;
begin
  Result := Assigned(SyncEvent)
end;

function TEvents.TupleByIndex(Index: Integer): TEventTuple;
begin
  Result.Event := FBuf[Index];
  Result.Cb := FCb[Index];
  Result.Data := FData[Index];
  Result.Hub := FHub[Index]
end;

{ TEvents.TTuple }

procedure TEventTuple.Trigger(const Aborted: Boolean);
var
  OldHub: THub;
begin
  OldHub := CurrentHub;
  try
    CurrentHub := Self.Hub;
    Self.Cb(Event, Data, Aborted)
  finally
    CurrentHub := OldHub;
  end;
end;

{ TFilesTuple }

procedure TFileTuple.Trigger(ErrorCode, Len: Integer; const Op: TIOOperation);
var
  OldHub: THub;
begin
  OldHub := CurrentHub;
  try
    CurrentHub := Hub;
    case Op of
      ioRead:
        ReadCb(Fd, Op, ReadData, ErrorCode, Len);
      ioWrite:
        WriteCb(Fd, Op, WriteData, ErrorCode, Len);
    end;
  finally
    CurrentHub := OldHub;
  end;
end;

procedure TFileTuple.RecalcCleanTime;
begin
  CleanTime := Now + EncodeTime(0, TFiles.TRASH_CLEAR_TIMEOUT_MINS, 0, 0)
end;

{ TFiles }

procedure TFiles.Deinitialize;
var
  Fd: THandle;
  {$IFNDEF DCC}I: Integer;{$ENDIF}
begin
  if not IsInitialized then
    Exit;
  {$IFDEF MSWINDOWS}
  {$IFDEF DCC}
  for Fd in FMap.Keys do begin
    CancelIo(Fd);
    Dequeue(Fd);
  end;
  {$ELSE}
  for I := 0 to FMap.Count-1 do begin
    Fd := FMap.Keys[I];
    CancelIo(Fd);
    Dequeue(Fd);
  end;
  {$ENDIF}
  {$ELSE}

  {$ENDIF}
  FMap.Free;
  TrashClean(False);
  FTrash.Free;
end;

procedure TFiles.Dequeue(const Fd: THandle);
var
  TuplePtr: PFileTuple;
begin
  if Find(Fd) then begin
    TuplePtr := FMap[Fd];
    TuplePtr.Active := False;
    TuplePtr.RecalcCleanTime;
    FMap.Remove(Fd);
    FTrash.Add(TuplePtr);
    {$IFDEF DEBUG}
    AtomicDecrement(IOFdTupleCounter);
    {$ENDIF}
  end;
  if Now > FTrashLAstClean then
    TrashClean;
end;

function TFiles.Enqueue(Fd: THandle; const Op: TIOOperation;
  const Cb: TIOCallback; Data: Pointer; Hub: THub): PFileTuple;
begin
  if Find(Fd) then begin
    Result := FMap[Fd]
  end
  else begin
    New(Result);
    FMap.Add(Fd, Result);
    FillChar(Result^, SizeOf(TFileTuple), 0);
    {$IFDEF DEBUG}
    AtomicIncrement(IOFdTupleCounter);
    {$ENDIF}
  end;
  Result.Fd := Fd;
  case Op of
    ioRead: begin
      Result.ReadCb := Cb;
      Result.ReadData := Data;
    end;
    ioWrite: begin
      Result.WriteCb := Cb;
      Result.WriteData := Data;
    end;
  end;
  Result.Hub := Hub;
  Result.Active := True;
  {$IFDEF MSWINDOWS}
  Result.Overlap.hEvent := NativeUInt(Result);
  {$ENDIF}
  if Now > FTrashLAstClean then
    TrashClean;
end;

function TFiles.Find(Id: THandle; out Tup: PFileTuple): Boolean;
begin
  Result := Find(Id);
  if Result then
    Tup := FMap[Id]
end;

function TFiles.Find(Fd: THandle): Boolean;
begin
  {$IFDEF DCC}
  Result := FMap.ContainsKey(Fd);
  {$ELSE}
  Result := FMap.IndexOf(Fd) >= 0;
  {$ENDIF}
end;

procedure TFiles.Initialize;
begin
  if IsInitialized then
    Exit;
  FMap := TMap.Create;
  FTrash := FList.Create;
end;

procedure TFiles.TrashClean(const OnlyByTimeout: Boolean);
var
  I: Integer;
begin
  if OnlyByTimeout then begin
    I := 0;
    while I < FTrash.Count do begin
      if FTrash[I].CleanTime < Now then begin
        Dispose(FTrash[I]);
        FTrash.Delete(I);
      end
      else
        Inc(I)
    end;
  end
  else begin
    for I := 0 to FTrash.Count-1 do begin
      Dispose(FTrash[I]);
    end;
    FTrash.Clear;
  end;
  FTrashLAstClean := Now;
end;

function TFiles.IsInitialized: Boolean;
begin
  Result := Assigned(FMap);
end;

{ TTimeouts }

procedure TTimeouts.Deinitialize;
var
  Id: NativeUInt;
  {$IFNDEF DCC}
  I: Integer;
  Fd: THandle;
  {$ENDIF}
begin
  if not IsInitialized then
    Exit;
  {$IFDEF MSWINDOWS}
  {$IFDEF DCC}
  for Id in FMap.Keys do begin
    CancelWaitableTimer(Id);
    Dequeue(Id);
  end;
  {$ELSE}
  for I := 0 to FMap.Count-1 do begin
    Fd := FMap.Keys[I];
    CancelIo(Fd);
    Dequeue(Fd);
  end;
  {$ENDIF}
  {$ELSE}

  {$ENDIF}
  FMap.Free;
end;

procedure TTimeouts.Dequeue(Id: THandle);
var
  TuplePtr: PTimeoutTuple;
begin
  if Find(Id) then begin
    TuplePtr := FMap[Id];
    FMap.Remove(Id);
    Dispose(TuplePtr);
    {$IFDEF DEBUG}
    AtomicDecrement(IOTimeTupleCounter);
    {$ENDIF}
  end;
end;

function TTimeouts.Enqueue(Id: THandle; const Cb: TInervalCallback;
  Data: Pointer; Hub: THub): PTimeoutTuple;
begin
  if Find(Id) then
    Result := FMap[Id]
  else begin
    New(Result);
    FMap.Add(Id, Result);
    {$IFDEF DEBUG}
    AtomicIncrement(IOTimeTupleCounter);
    {$ENDIF}
  end;
  Result.Cb := Cb;
  Result.Data := Data;
  Result.Id := Id;
  Result.Hub := Hub;
end;

function TTimeouts.Find(Id: THandle): Boolean;
begin
  {$IFDEF DCC}
  Result := FMap.ContainsKey(Id);
  {$ELSE}
  Result := FMap.IndexOf(Id) >= 0;
  {$ENDIF}
end;

procedure TTimeouts.Initialize;
begin
  if IsInitialized then
    Exit;
  FMap := TMap.Create;
end;

function TTimeouts.IsInitialized: Boolean;
begin
  Result := Assigned(FMap);
end;

{ TTimeoutTuple }

procedure TTimeoutTuple.Trigger;
var
  OldHub: THub;
begin
  OldHub := CurrentHub;
  try
    CurrentHub := Hub;
    Cb(Id, Data)
  finally
    CurrentHub := OldHub
  end;
end;

{ THub.TTask }

procedure THub.TTask.Init(const Method: TThreadMethod);
begin
  FillChar(Self, SizeOf(Self), 0);
  Self.Method := Method;
  Self.Kind := tkMEthod;
end;

procedure THub.TTask.Init(Intf: IInterface; const Method: TThreadMethod);
begin
  FillChar(Self, SizeOf(Self), 0);
  Self.Method := Method;
  Self.Intf := Intf;
  Self.Kind := tkIntfMethod;
end;

procedure THub.TTask.Init(const Proc: TTaskProc; Arg: Pointer);
begin
  FillChar(Self, SizeOf(Self), 0);
  Self.Proc := Proc;
  Self.Arg := Arg;
  Self.Kind := tkProc;
end;

{$IFDEF FPC}
class operator THub.TTask.=(const a, b: TTask): Boolean;
begin
  if a.Kind <> b.Kind then
    Exit(False);
  case a.Kind of
    tkMethod, tkIntfMethod: begin
      Result := @a.Method = @b.Method;
    end;
    tkProc: begin
      Result := @a.Proc = @b.Proc
    end;
  end;
end;
{$ENDIF}

{$IFDEF MSWINDOWS}

function GetMessagePatched(var lpMsg: TMsg; hWnd: HWND;
  wMsgFilterMin, wMsgFilterMax: UINT): BOOL; stdcall;
begin
  case DefHub.Wait(INFINITE) of
    meError:;
    meEvent:
      ;
    meSync:
      DefHub.ServeTaskQueue;
    meIO:;
    meWinMsg:;
    meTimer:;
    meWaitTimeout:;
  end;
  Result := False;
end;

procedure FinalizeDefHubList;
var
  {$IFDEF DCC}
  TID: LongWord;
  {$ELSE}
  I: Integer;
  H: TSingleThreadHub;
  {$ENDIF}
begin
  DefHubsLock.Acquire;
  try
    {$IFDEF DCC}
    for TID in DefHubs.Keys do begin
      DefHubs[TID].FIsDef := False;
      DefHubs[TID].Free;
    end;
    {$ELSE}
    for I := 0 to DefHubs.Count-1 do begin
      H := DefHubs.Data[I];
      H.FIsDef := False;
      H.Free;
    end;
    {$ENDIF}
  finally
    DefHubsLock.Release;
  end;
  FreeAndNil(DefHubsLock);
  FreeAndNil(DefHubs);
end;

{$ENDIF}

initialization
  DefHubsLock := SyncObjs.TCriticalSection.Create;
  DefHubs := THubMap.Create;

  InitSocketInterface('');
  sock.WSAStartup(WinsockLevel, WsaDataOnce);
  InitializeStubsEx;

  HubInfrasctuctureEnable := True;

finalization

  HubInfrasctuctureEnable := False;

  sock.WSACleanup;
  DestroySocketInterface;

  FinalizeDefHubList;

end.
