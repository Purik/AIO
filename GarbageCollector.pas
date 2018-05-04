unit GarbageCollector;

interface
uses {$IFDEF FPC} contnrs, fgl {$ELSE}Generics.Collections, System.Rtti{$ENDIF},
  PasMP;

type

  IGCPointer<T> = interface
    function GetValue: T;
    function GetRefCount: Integer;
  end;
  IGCObject = IGCPointer<TObject>;

  TGarbageCollector = class
  private
  type
    TLocalRefs = class(TInterfacedObject, IGCObject)
    strict private
      FContainer: TGarbageCollector;
      FGlobalRef: IGCObject;
      FValue: TObject;
    protected
      function _AddRef: Integer; stdcall;
      function _Release: Integer; stdcall;
      property Container: TGarbageCollector read FContainer write FContainer;
    public
      constructor Create(Container: TGarbageCollector; GlobalRef: IGCObject);
      function GetValue: TObject;
      function GetRefCount: Integer;
      property GlobalRef: IGCObject read FGlobalRef;
    end;
  var
    {$IFDEF DCC}
    FStorage: TDictionary<TObject, TLocalRefs>;
    {$ELSE}
    FStorage: TFPGMap<TObject, TLocalRefs>;
    {$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    function IsExists(A: TObject): Boolean;
    function SetValue(A: TObject): IGCObject;
    procedure Clear;
    class function ExistsInGlobal(A: TObject): Boolean; static;
  end;

  TFinalizer<T> = record
  public
    class procedure Fin(var A: T); static;
  end;

  TGCPointerImpl<T> = class(TInterfacedObject, IGCPointer<T>)
  strict private
    FValue: T;
    FIsObject: Boolean;
    FObject: TObject;
    FDynArr: Pointer;
    FIsDynArr: Boolean;
  protected
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(Value: T); overload;
    destructor Destroy; override;
    function GetValue: T;
    function GetRefCount: Integer;
  end;

var
  GlobalGC: TPasMPHashTable<Pointer, IGCObject>;
  GlobalGCActive: Boolean;
{$IFDEF DEBUG}
  GCCounter: Integer;
{$ENDIF}

implementation
uses TypInfo;


{ TGarbageCollector }

procedure TGarbageCollector.Clear;
var
  LocalRefs: TLocalRefs;
begin
  for LocalRefs in FStorage.Values do
    LocalRefs.Container := nil;
  FStorage.Clear;
end;

constructor TGarbageCollector.Create;
begin
  {$IFDEF DCC}
  FStorage := TDictionary<TObject, TLocalRefs>.Create
  {$ELSE}
  FStorage := TFPGMap<TObject, TLocalRefs>.Create;
  {$ENDIF}
end;

destructor TGarbageCollector.Destroy;
begin
  Clear;
  FStorage.Free;
  inherited;
end;

class function TGarbageCollector.ExistsInGlobal(A: TObject): Boolean;
var
  Smart: IGCObject;
begin
  Result := GlobalGC.GetKeyValue(A, Smart)
end;

function TGarbageCollector.IsExists(A: TObject): Boolean;
{$IFDEF FPC}
var
  Index: Integer;
{$ENDIF}
begin
  {$IFDEF DCC}
  Result := FStorage.ContainsKey(A)
  {$ELSE}
  Result := FStorage.Find(Key, Index);
  {$ENDIF}
end;

function TGarbageCollector.SetValue(A: TObject): IGCObject;
var
  GlobalRef: IGCObject;
  LocalRefs: TLocalRefs;
begin
  if A = nil then
    Exit(nil);
  if IsExists(A) then
    Result := FStorage[A]
  else if GlobalGC.GetKeyValue(A, GlobalRef) then begin
    LocalRefs := TLocalRefs.Create(Self, GlobalRef);
    Result := LocalRefs;
    FStorage.Add(A, LocalRefs)
  end
  else begin
    GlobalRef := TGCPointerImpl<TObject>.Create(A);
    {$IFDEF DEBUG}
    Assert(GlobalGC.SetKeyValue(A, GlobalRef));
    {$ELSE}
    GlobalGC.SetKeyValue(A, GlobalRef);
    {$ENDIF}
    LocalRefs := TLocalRefs.Create(Self, GlobalRef);
    Result := LocalRefs;
    FStorage.Add(A, LocalRefs)
  end
end;

class procedure TFinalizer<T>.Fin(var A: T);
var
  ti: PTypeInfo;
  ObjValuePtr: PObject;
begin
  ti := TypeInfo(T);
  if (ti.Kind = tkClass) then begin
    ObjValuePtr := @A;
    if Assigned(ObjValuePtr) then
      ObjValuePtr.Free;
  end
end;

{ TGCPointerImpl<T> }

constructor TGCPointerImpl<T>.Create(Value: T);
var
  ti: PTypeInfo;
  ObjValuePtr: PObject;
  DynArrPtr: Pointer;
begin
  FValue := Value;
  ti := TypeInfo(T);
  if (ti.Kind = tkClass) then begin
    ObjValuePtr := @Value;
    FObject := ObjValuePtr^;
    FIsObject := True;
  end
  else if ti.Kind = tkDynArray then begin
    FDynArr := @Value;
    FIsDynArr := True;
  end;
end;

destructor TGCPointerImpl<T>.Destroy;
begin
  TFinalizer<T>.Fin(FValue);
  inherited;
end;

function TGCPointerImpl<T>.GetRefCount: Integer;
begin
  Result := FRefCount
end;

function TGCPointerImpl<T>.GetValue: T;
begin
  Result := FValue
end;

function TGCPointerImpl<T>._AddRef: Integer;
var
  Ref: IGCObject;
begin
  Result := inherited _AddRef;
  if FIsObject and (Result = 1) then begin
    {$IFDEF DEBUG}
    Assert(not GlobalGC.GetKeyValue(FObject, Ref));
    {$ENDIF}
    Ref := TGCPointerImpl<TObject>(Self);
    GlobalGC.SetKeyValue(FObject, Ref)
  end;
  {$IFDEF DEBUG}
  AtomicIncrement(GCCounter);
  {$ENDIF}
end;

function TGCPointerImpl<T>._Release: Integer;
begin
  Result := inherited _Release;
  if FIsObject and (Result = 1) then begin
    if GlobalGCActive then begin
      {$IFDEF DEBUG}
      Assert(GlobalGC.DeleteKey(FObject));
      {$ELSE}
      GlobalGC.DeleteKey(FObject)
      {$ENDIF}
    end;
  end;
  {$IFDEF DEBUG}
  AtomicDecrement(GCCounter);
  {$ENDIF}
end;

{ TGarbageCollector.TLocalRefs }

constructor TGarbageCollector.TLocalRefs.Create(Container: TGarbageCollector;
  GlobalRef: IGCObject);
begin
  FContainer := Container;
  FGlobalRef := GlobalRef;
  FValue := GlobalRef.GetValue;
end;

function TGarbageCollector.TLocalRefs.GetRefCount: Integer;
begin
  Result := FRefCount
end;

function TGarbageCollector.TLocalRefs.GetValue: TObject;
begin
  Result := FGlobalRef.GetValue
end;

function TGarbageCollector.TLocalRefs._AddRef: Integer;
begin
  Result := inherited _AddRef;
end;

function TGarbageCollector.TLocalRefs._Release: Integer;
begin
  Result := inherited _Release;
  if Result = 0 then begin
    if Assigned(FContainer) then
      if FContainer.FStorage.ContainsKey(FValue) then
        FContainer.FStorage.Remove(FValue);
  end;
end;

initialization
  GlobalGC := TPasMPHashTable<Pointer, IGCObject>.Create;
  GlobalGCActive := True;

finalization
  GlobalGCActive := False;
  GlobalGC.Free

end.
