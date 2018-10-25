// **************************************************************************************************
// Delphi Aio Library.
// Unit Gevent
// https://github.com/Purik/AIO

// The contents of this file are subject to the Apache License 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
//
// The Original Code is Gevent.pas.
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
unit Gevent;

interface
uses SysUtils, Classes, SyncObjs,
  {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections,  System.Rtti{$ENDIF};

type

  {*
     TGevent - allows you to build a state machine around events imperative
      event-driven programming
  *}
  IGevent = interface
    ['{9F8D9F83-E1DE-478C-86A2-AF641EEF50B7}']
    procedure SetEvent(const Sync: Boolean = False);
    procedure ResetEvent;
    function  WaitFor(aTimeOut: LongWord = INFINITE): TWaitResult;
  end;

  TGevent = class(TInterfacedObject, IGevent)
  type
    EOperationError = class(Exception);
  private
  type
    TWaitList = TList;
    TIndexes = array of Integer;
    IAssociateRef = interface
      procedure ClearIndexes;
      function  GetIndexes: TIndexes;
      procedure Lock;
      procedure Unlock;
      function Emit(const aResult: TWaitResult; const IsDestroyed: Boolean;
        Index: Integer): Boolean;
      procedure SetOwner(Value: TGevent);
      function GetOwner: TGevent;
    end;
  var
    FAssociateRef: IAssociateRef;
    FHandle: THandle;
    FWaiters: tWaitList;
    FLock: SyncObjs.TCriticalSection;
    FSignal: Boolean;
    FManualReset: Boolean;
    function GreenWaitEvent(aTimeOut: LongWord = INFINITE): TWaitResult;
    function ThreadWaitEvent(aTimeOut: LongWord = INFINITE): TWaitResult;
    class procedure SwitchTimeout(Id: THandle; Data: Pointer); static;
  private
    procedure Emit(const aResult: TWaitResult; const IsDestroyed: Boolean;
      const Sync: Boolean = False);
  protected
    function WaitersCount: Integer;
    procedure Lock; inline;
    procedure Unlock; inline;
    function TryLock: Boolean; inline;
    class procedure TimeoutCb(Id: THandle; Data: Pointer); static;
    property AssociateRef: IAssociateRef read FAssociateRef;
    class procedure SignalTimeout(Id: THandle; Data: Pointer;
      const Aborted: Boolean); static;
    procedure ClearEmptyDescr;
  public
    constructor Create(const ManualReset: Boolean=False;
      const InitialState: Boolean = False); overload;
    constructor Create(Handle: THandle); overload;
    destructor Destroy; override;
    procedure SetEvent(const Sync: Boolean = False);
    procedure ResetEvent;
    procedure Associate(Emitter: TGevent; Index: Integer);
    function  WaitFor(aTimeOut: LongWord = INFINITE): TWaitResult;
    class function WaitMultiple(const Events: array of TGevent;
      out Index: Integer; const Timeout: LongWord=INFINITE): TWaitResult;
  end;

implementation
uses GInterfaces, GreenletsImpl, Greenlets, PasMP, Hub;

type
  TAssociateRef = class(TInterfacedObject, TGevent.IAssociateRef)
  strict private
    FOwner: TGevent;
    FLock: SyncObjs.TCriticalSection;
    FIndexes: TGevent.TIndexes;
    function FindIndex(Value: Integer): Boolean;
  public
    procedure ClearIndexes;
    function GetIndexes: TGevent.TIndexes;
    procedure Lock;
    procedure Unlock;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    procedure SetOwner(Value: TGevent);
    function GetOwner: TGevent;
    function Emit(const aResult: TWaitResult; const IsDestroyed: Boolean;
        Index: Integer): Boolean;
  end;

  TMultiContextVar = class(TInterfacedObject)
  strict private
    FActive: Boolean;
    FLock: TPasMPSpinLock;
    function GetActive: Boolean;
    procedure SetActive(const Active: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    property Active: Boolean read GetActive write SetActive;
  end;

  PWaitResult = ^TWaitResult;
  TWaitDescr = class(TInterfacedObject)
  strict private
    FProxy: IGreenletProxy;
    FHub: TCustomHub;
    FTimeStop: TTime;
    FResult: TWaitResult;
    FEvDestroyed: TMultiContextVar;
    FAssociate: TGevent.IAssociateRef;
    FTag: Integer;
    FContext: Pointer;
    FGevent: TGevent;
  public
    constructor Create(Hub: TCustomHub; const Result: TWaitResult; EvDestroyedRef: TMultiContextVar); overload;
    constructor Create(Associate: TGevent.IAssociateRef; Tag: Integer); overload;
    destructor Destroy; override;
    // props
    property Context: Pointer read FContext write FContext;
    property Proxy: IGreenletProxy read FProxy write FProxy;
    property Hub: TCustomHub read FHub;
    property TimeStop: TTime read FTimeStop write FTimeStop;
    property Associate: TGevent.IAssociateRef read FAssociate;
    property Tag: Integer read FTag;
    property Result: TWaitResult read FResult write FResult;
    property EvDestroyed: TMultiContextVar read FEvDestroyed;
    property Gevent: TGevent read FGevent write FGevent;
  end;

  TGreenletPimpl = class(TRawGreenletImpl);


{ TGevent.TAssociateRef }

procedure TAssociateRef.AfterConstruction;
begin
  inherited;
  FLock := SyncObjs.TCriticalSection.Create;
end;

procedure TAssociateRef.BeforeDestruction;
begin
  inherited;
  FreeAndNil(FLock);
end;

procedure TAssociateRef.ClearIndexes;
begin
  Lock;
  SetLength(FIndexes, 0);
  Unlock;
end;

function TAssociateRef.Emit(const aResult: TWaitResult;
  const IsDestroyed: Boolean; Index: Integer): Boolean;
begin
  Lock;
  try
    Result := FOwner <> nil;
    if Result then begin
      if not FindIndex(Index) then begin
        SetLength(FIndexes, Length(FIndexes)+1);
        FIndexes[High(FIndexes)] := Index;
      end;
      FOwner.Emit(aResult, IsDestroyed);
      Result := FOwner <> nil;
    end;
  finally
    Unlock;
  end;
end;

function TAssociateRef.FindIndex(Value: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FIndexes) do
    if FIndexes[I] = Value then
      Exit(True)
end;

function TAssociateRef.GetIndexes: TGevent.TIndexes;
begin
  Lock;
  try
    Result := FIndexes
  finally
    UnLock
  end;
end;

function TAssociateRef.GetOwner: TGevent;
begin
  Lock;
  try
    Result := FOwner;
  finally
    Unlock;
  end;
end;

procedure TAssociateRef.Lock;
begin
  {$IFDEF DCC}
  TMonitor.Enter(FLock);
  {$ELSE}
  FLock.Acquire;
  {$ENDIF}
end;

procedure TAssociateRef.SetOwner(Value: TGevent);
begin
  Lock;
  try
    FOwner := Value;
  finally
    Unlock;
  end;
end;

procedure TAssociateRef.Unlock;
begin
  {$IFDEF DCC}
  TMonitor.Exit(FLock);
  {$ELSE}
  FLock.Release;
  {$ENDIF}
end;

{ TGevent }

procedure TGevent.Associate(Emitter: TGevent; Index: Integer);
var
  Descr: TWaitDescr;
begin
  Lock;
  try
    Emitter.Lock;
    try
      Emitter.ClearEmptyDescr;
      Descr := TWaitDescr.Create(FAssociateRef, Index);
      Descr._AddRef;
      Emitter.FWaiters.Add(Descr);
    finally
      Emitter.Unlock;
    end;
  finally
    Unlock;
  end;
end;

constructor TGevent.Create(const ManualReset, InitialState: Boolean);
begin
  FLock := SyncObjs.TCriticalSection.Create;
  {$IFDEF DCC}
  TMonitor.SetSpinCount(FLock, 4000);
  {$ENDIF}
  FWaiters := tWaitList.Create;
  FSignal := InitialState;
  FManualReset := ManualReset;
  FAssociateRef := TAssociateRef.Create;
  FAssociateRef.SetOwner(Self);
  {$IFDEF DEBUG}
  AtomicIncrement(GeventCounter)
  {$ENDIF}
end;

procedure TGevent.ClearEmptyDescr;
var
  Ind: Integer;
  Descr: TWaitDescr;
begin
  Lock;
  try
    Ind := 0;
    while Ind < FWaiters.Count do begin
      Descr := TWaitDescr(FWaiters[Ind]);
      if Assigned(Descr.Associate) and (Descr.Associate.GetOwner = nil) then begin
        Descr._Release;
        FWaiters.Delete(Ind)
      end
      else
        Inc(Ind)
    end;
  finally
    Unlock;
  end;
end;

constructor TGevent.Create(Handle: THandle);
begin
  Create(False, False);
  if FHandle <> 0 then
    raise EOperationError.CreateFmt('Gevent already associated with %d handle',
      [FHandle]);
  FHandle := Handle;
end;

destructor TGevent.Destroy;
begin
  FAssociateRef.SetOwner(nil);
  Emit(wrAbandoned, True);
  FAssociateRef := nil;
  FWaiters.Free;
  FLock.Free;
  {$IFDEF DEBUG}
  AtomicDecrement(GeventCounter);
  {$ENDIF}
  inherited;
end;

procedure TGevent.Emit(const aResult: TWaitResult; const IsDestroyed: Boolean;
  const Sync: Boolean);
var
  L: array of TWaitDescr;
  Syncs: array of TWaitDescr;
  I, SyncsNum: Integer;
begin
  Lock;
  try
    FSignal := aResult = wrSignaled;
    SetLength(L, FWaiters.Count);
    for I := 0 to FWaiters.Count-1 do begin
      L[I] := FWaiters[I];
    end;
    FWaiters.Clear;
    SyncsNum := 0;
  finally
    Unlock;
  end;
  if Sync then begin
    SetLength(Syncs, Length(L));
    SyncsNum := 0;
  end;
  for I := 0 to High(L) do begin
    if Assigned(L[I].Proxy) and (not (L[I].Proxy.GetState in [gsExecute, gsSuspended])) then begin
      L[I]._Release;
      Continue;
    end;
    if Assigned(L[I].Associate) then begin
      if L[I].Associate.Emit(aResult, IsDestroyed, L[I].Tag) then begin
        if IsDestroyed then
          L[I]._Release
        else begin
          Lock;
          FWaiters.Add(L[I]);
          if (aResult = wrSignaled) and FSignal and (not FManualReset) then
            FSignal := False;
          Unlock;
        end;
      end
      else begin
        L[I]._Release
      end;
    end
    else begin
      L[I].Result := aResult;
      L[I].EvDestroyed.Active := IsDestroyed;
      if Assigned(L[I].Proxy) then begin
        if Sync and (L[I].Hub = GetCurrentHub) then begin
          Syncs[SyncsNum] := L[I];
          Inc(SyncsNum);
        end
        else begin
          L[I].Proxy.Resume;
          L[I]._Release;
        end;
      end
      else begin
        L[I].Hub.Pulse;
        L[I]._Release;
      end;
    end
  end;
  if Sync then
    for I := 0 to SyncsNum-1 do begin
      TRawGreenletImpl(Syncs[I].Context).Resume;
      Syncs[I]._Release;
    end;
end;

function TGevent.GreenWaitEvent(aTimeOut: LongWord): TWaitResult;
var
  Descr: TWaitDescr;
  Ellapsed: TTime;
  EvDestroyed: TMultiContextVar;
  Timeout: THandle;

  procedure ForceFinalize;
  var
    I: Integer;
  begin
    if EvDestroyed.Active then
      Exit;
    Lock;
    try
      for I := 0 to FWaiters.Count-1 do
        if TWaitDescr(FWaiters[I]).Proxy = Descr.Proxy then begin
          TWaitDescr(FWaiters[I])._Release;
          FWaiters.Delete(I);
          Break;
        end;
    finally
      Unlock;
    end;
  end;

begin
  if TRawGreenletImpl(GetCurrent).GetProxy.GetState = gsKilling then
    Exit(wrAbandoned);
  Result := wrError;
  Lock;
  try
    if FSignal then begin
      Exit(wrSignaled)
    end
    else if aTimeOut = 0 then begin
      Exit(wrTimeout);
    end;
    EvDestroyed := TMultiContextVar.Create;
    EvDestroyed._AddRef;
    Descr := TWaitDescr.Create(GetCurrentHub, wrError, EvDestroyed);
    Descr._AddRef;
    if aTimeOut = INFINITE then
      Descr.TimeStop := 0
    else begin
      Descr.TimeStop := Now + TimeOut2Time(aTimeOut);
    end;
    Descr.Proxy := TRawGreenletImpl(GetCurrent).GetProxy;
    Descr.Context := GetCurrent;
    Descr.Gevent := Self;
    Descr._AddRef;
    FWaiters.Add(Descr);
  finally
    Unlock;
  end;

  Timeout := 0;
  try
    if FHandle <> 0 then begin
      Descr.Hub.AddEvent(FHandle, SignalTimeout, Self);
    end;
    if Descr.TimeStop = 0 then begin
      while not ((Descr.Result in [wrAbandoned, wrSignaled]) or FSignal) do begin
        TRawGreenletImpl(GetCurrent).Suspend;
        Greenlets.Yield;
      end;
      if FSignal and (Descr.Result = wrError) then
        Result := wrSignaled
      else
        Result := Descr.Result;
    end
    else begin
      Descr._AddRef;
      Timeout := Descr.Hub.CreateTimeout(SwitchTimeout, Descr, aTimeOut+1);
      Ellapsed := Now;
      Ellapsed := Now - Ellapsed;
      Descr.TimeStop := Descr.TimeStop - Ellapsed;
      Descr.Result := wrTimeout;
      TRawGreenletImpl(GetCurrent).Suspend;
      while Descr.TimeStop >= Now do begin
        if (Descr.Result <> wrTimeout) or FSignal then
          Break
        else begin
          TRawGreenletImpl(GetCurrent).Suspend;
          Greenlets.Yield;
        end
      end;
      if FSignal and (Descr.Result = wrError) then
        Result := wrSignaled
      else
        Result := Descr.Result;
    end;
  finally
    if Result in [wrAbandoned, wrError] then
      FSignal := False;
    if FHandle <> 0 then
      Descr.Hub.RemEvent(FHandle);
    if Timeout <> 0 then begin
      Descr.Hub.DestroyTimeout(Timeout);
      Descr._Release;
    end;
    ForceFinalize;
    EvDestroyed._Release;
    Descr._Release;
  end;
end;

procedure TGevent.Lock;
begin
  {$IFDEF DCC}
  TMonitor.Enter(FLock);
  {$ELSE}
  FLock.Acquire;
  {$ENDIF}
end;

procedure TGevent.ResetEvent;
begin
  if not FManualReset then
    Exit;
  Lock;
  try
    FSignal := False;
    FAssociateRef.ClearIndexes;
  finally
    Unlock;
  end;
end;

procedure TGevent.SetEvent(const Sync: Boolean);
begin
  Emit(wrSignaled, False, Sync);
end;

class procedure TGevent.SignalTimeout(Id: THandle; Data: Pointer;
  const Aborted: Boolean);
begin
  if Aborted then
    TGevent(Data).Emit(wrAbandoned, False, True)
  else
    TGevent(Data).Emit(wrSignaled, False, True);
end;

class procedure TGevent.SwitchTimeout(Id: THandle; Data: Pointer);
var
  Descr: TWaitDescr;
begin
  Descr := TWaitDescr(Data);
  if not Descr.EvDestroyed.Active then
    TRawGreenletImpl(Descr.Context).Resume;
end;

class procedure TGevent.TimeoutCb(Id: THandle; Data: Pointer);
var
  Descr: TWaitDescr;
begin
  Descr := TWaitDescr(Data);
  if not Descr.EvDestroyed.Active then
    Descr.Gevent.Emit(wrTimeout, False, True);
end;

function TGevent.TryLock: Boolean;
begin
  {$IFDEF DCC}
  Result := TMonitor.TryEnter(FLock);
  {$ELSE}
  Result := FLock.TryEnter
  {$ENDIF}
end;

function TGevent.ThreadWaitEvent(aTimeOut: LongWord): TWaitResult;
var
  Descr: TWaitDescr;
  EvDestroyed: TMultiContextVar;
  Timeout: THandle;

  procedure ForceFinalize;
  var
    I: Integer;
  begin
    if EvDestroyed.Active then
      Exit;
    Lock;
    try
      for I := 0 to FWaiters.Count-1 do
        if (TWaitDescr(FWaiters[I]).Hub = Descr.Hub) and (Descr.Proxy = nil) then begin
          TWaitDescr(FWaiters[I])._Release;
          FWaiters.Delete(I);
          Break;
        end;
    finally
      Unlock;
    end;
  end;

begin
  Result := wrError;
  Lock;
  try
    if FSignal then begin
      Exit(wrSignaled)
    end
    else if aTimeOut = 0 then begin
      Exit(wrTimeout);
    end;
    EvDestroyed := TMultiContextVar.Create;
    EvDestroyed._AddRef;
    Descr := TWaitDescr.Create(GetCurrentHub, wrError, EvDestroyed);
    Descr._AddRef;
    if aTimeOut = INFINITE then
      Descr.TimeStop := 0
    else begin
      Descr.TimeStop := Now + TimeOut2Time(aTimeOut);
    end;
    Descr.Gevent := Self;
    Descr._AddRef;
    FWaiters.Add(Descr);
  finally
    Unlock;
  end;

  Timeout := 0;
  try
    if FHandle <> 0 then begin
      Descr.Hub.AddEvent(FHandle, SignalTimeout, Self);
    end;
    Descr.Hub.IsSuspended := True;
    if Descr.TimeStop = 0 then begin
      while not ((Descr.Result in [wrAbandoned, wrSignaled]) or FSignal) do
        Descr.Hub.Serve(INFINITE);
      if FSignal and (Descr.Result = wrError) then
        Result := wrSignaled
      else
        Result := Descr.Result;
    end
    else begin
      Descr.Result := wrTimeout;
      Descr._AddRef;
      Timeout := Descr.Hub.CreateTimeout(TimeoutCb, Descr, aTimeOut+1);
      while Descr.TimeStop >= Now do begin
        if (Descr.Result <> wrTimeout) or FSignal then
          Break
        else
          Descr.Hub.Serve(Time2TimeOut(Descr.TimeStop - Now))
      end;
      if FSignal and (Descr.Result = wrError) then
        Result := wrSignaled
      else
        Result := Descr.Result;
    end;
  finally
    Descr.Hub.IsSuspended := False;
    if Result in [wrAbandoned, wrError] then
      FSignal := False;
    if Timeout <> 0 then  begin
      Descr.Hub.DestroyTimeout(Timeout);
      Descr._Release;
    end;
    if FHandle <> 0 then
      Descr.Hub.RemEvent(FHandle);
    ForceFinalize;
    EvDestroyed._Release;
    Descr._Release;
  end;
end;

procedure TGevent.Unlock;
begin
  {$IFDEF DCC}
  TMonitor.Exit(FLock);
  {$ELSE}
  FLock.Release;
  {$ENDIF}
end;

function TGevent.WaitersCount: Integer;
begin
  Result := FWaiters.Count
end;

function TGevent.WaitFor(aTimeOut: LongWord): TWaitResult;
begin
  if TGreenletPimpl.GetCurrent = nil then
    Result := ThreadWaitEvent(aTimeOut)
  else
    Result := GreenWaitEvent(aTimeOut);
  if not FManualReset then begin
    Lock;
    try
      // ABA-problem
      if FSignal then
        Result := wrSignaled;
      if Result = wrSignaled then begin
        if (not FManualReset) and FSignal then
          FSignal := False
      end;
    finally
      Unlock
    end;
  end;
end;

class function TGevent.WaitMultiple(const Events: array of TGevent;
  out Index: Integer; const Timeout: LongWord): TWaitResult;
var
  Ev, Assoc: TGevent;
  I: Integer;
begin
  if Length(Events) = 0 then begin
    Index := -1;
    Exit(wrError);
  end;
  Ev := TGEvent.Create;
  try
    for I := 0 to High(Events) do begin
      Assoc := Events[I];
      if Assigned(Assoc) then begin
        Assoc.Lock;
        try
          if Assoc.FSignal then begin
            Index := I;
            if not Assoc.FManualReset then
              Assoc.FSignal := False;
            Exit(wrSignaled);
          end;
          Ev.Associate(Assoc, I);
        finally
          Assoc.UnLock;
        end;
      end;
    end;
    Result := Ev.WaitFor(Timeout);
    Ev.AssociateRef.Lock;;
    try
      if Length(Ev.AssociateRef.GetIndexes) > 0 then
        Index := Ev.AssociateRef.GetIndexes[0]
      else
        Index := -1;
    finally
      Ev.AssociateRef.Unlock;
    end;
  finally
    Ev.Free;
  end;
end;

{ TWaitDescr }

constructor TWaitDescr.Create(Associate: TGevent.IAssociateRef; Tag: Integer);
begin
  FAssociate := Associate;
  FTag := Tag;
end;

constructor TWaitDescr.Create(Hub: TCustomHub; const Result: TWaitResult;
  EvDestroyedRef: TMultiContextVar);
begin
  FHub := Hub;
  FResult := Result;
  FEvDestroyed := EvDestroyedRef;
  FEvDestroyed._AddRef;
end;

destructor TWaitDescr.Destroy;
begin
  FAssociate := nil;
  Proxy := nil;
  if Assigned(FEvDestroyed) then
    FEvDestroyed._Release;
  inherited;
end;

{ TMultiContextVar }

constructor TMultiContextVar.Create;
begin
  FLock := TPasMPSpinLock.Create
end;

destructor TMultiContextVar.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TMultiContextVar.GetActive: Boolean;
begin
  FLock.Acquire;
  Result := FActive;
  FLock.Release;
end;

procedure TMultiContextVar.SetActive(const Active: Boolean);
begin
  FLock.Acquire;
  FActive := Active;
  FLock.Release;
end;

end.
