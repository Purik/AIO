unit AioIndy;

interface
uses IdIOHandler, IdServerIOHandler, IdComponent, IdIOHandlerSocket, IdGlobal,
  Aio, SysUtils;

type

  { TIdIOHandlerSocket reintroducing }
  TAioIdIOHandlerSocket = class(TIdIOHandler)
  const
    CONN_TIMEOUT = 3000;
  protected
    FBinding: IAioProvider;
    FBoundIP: string;
    FBoundPort: TIdPort;
    FDefaultPort: TIdPort;
    //FTransparentProxy: TIdCustomTransparentProxy;
    FUseNagle: Boolean;
    FConnected: Boolean;
    function ReadDataFromSource(var VBuffer: TIdBytes): Integer; override;
    function WriteDataToTarget(const ABuffer: TIdBytes; const AOffset, ALength: Integer): Integer; override;
    function SourceIsAvailable: Boolean; override;
    function CheckForError(ALastResult: Integer): Integer; override;
    procedure RaiseError(AError: Integer); override;
  public
    destructor Destroy; override;
    function BindingAllocated: Boolean;
    procedure Close; override;
    function Connected: Boolean; override;
    procedure Open; override;
    function WriteFile(const AFile: String; AEnableTransferFile: Boolean = False): Int64; override;
    //
    property Binding: IAioProvider read FBinding;
    //
    procedure CheckForDisconnect(ARaiseExceptionIfDisconnected: Boolean = True;
      AIgnoreBuffer: Boolean = False); override;
    function Readable(AMSec: Integer = IdTimeoutDefault): Boolean; override;
  published
    property BoundIP: string read FBoundIP write FBoundIP;
    property BoundPort: TIdPort read FBoundPort write FBoundPort default IdBoundPortDefault;
    property DefaultPort: TIdPort read FDefaultPort write FDefaultPort;
    //property TransparentProxy: TIdCustomTransparentProxy read GetTransparentProxy write SetTransparentProxy;
  end;

procedure MakeNonBlocking(const IdComponents: array of TIdComponent);

implementation
uses IdExceptionCore, IdResourceStringsCore, Classes, IdStack, IdTCPConnection;

{ TAioIdIOHandlerSocket }

function TAioIdIOHandlerSocket.BindingAllocated: Boolean;
begin
  Result := FBinding <> nil
end;

procedure TAioIdIOHandlerSocket.CheckForDisconnect(
  ARaiseExceptionIfDisconnected, AIgnoreBuffer: Boolean);
begin
  if ARaiseExceptionIfDisconnected and not FConnected then
    RaiseConnClosedGracefully
end;

function TAioIdIOHandlerSocket.CheckForError(ALastResult: Integer): Integer;
begin
  // nothing to do
end;

procedure TAioIdIOHandlerSocket.Close;
begin
  if FBinding <> nil then begin
    if Supports(FBinding, IAioTcpSocket) then
    begin
      (FBinding as IAioTcpSocket).Disconnect
    end
  end;
  inherited Close;
end;

function TAioIdIOHandlerSocket.Connected: Boolean;
begin
  Result := (BindingAllocated and FConnected and inherited Connected) or (not InputBufferIsEmpty);
end;

destructor TAioIdIOHandlerSocket.Destroy;
begin
  {if Assigned(FTransparentProxy) then begin
    if FTransparentProxy.Owner = nil then begin
      FreeAndNil(FTransparentProxy);
    end;
  end;}
  FBinding := nil;
  inherited Destroy;
end;

procedure TAioIdIOHandlerSocket.Open;
begin
  inherited Open;

  if not Assigned(FBinding) then begin
    FBinding := MakeAioTcpSocket
  end else begin
    FBinding := nil;
  end;
  FConnected := False;

  //if the IOHandler is used to accept connections then port+host will be empty
  if (Host <> '') and (Port > 0) then begin
    if Supports(FBinding, IAioTcpSocket) then
    begin
      FConnected := (FBinding as IAioTcpSocket).Connect(Host, Port, CONN_TIMEOUT)
    end
    else if Supports(FBinding, IAioUdpSocket) then
    begin
      (FBinding as IAioUdpSocket).Bind(Host, Port);
      FConnected := True;
    end;
  end;
end;

procedure TAioIdIOHandlerSocket.RaiseError(AError: Integer);
begin
  GStack.RaiseSocketError(AError);
end;

function TAioIdIOHandlerSocket.Readable(AMSec: Integer): Boolean;
begin
  Result := Connected
end;

function TAioIdIOHandlerSocket.ReadDataFromSource(
  var VBuffer: TIdBytes): Integer;
begin
  Result := 0;
  if BindingAllocated and FBinding.ReadBytes(VBuffer) then
    Result := Length(VBuffer);
end;

function TAioIdIOHandlerSocket.SourceIsAvailable: Boolean;
begin
  Result := BindingAllocated and FConnected
end;

function TAioIdIOHandlerSocket.WriteDataToTarget(const ABuffer: TIdBytes;
  const AOffset, ALength: Integer): Integer;
begin
  Result := 0;
  if BindingAllocated then
  begin
    Result := FBinding.Write(@ABuffer[AOffset], ALength)
  end;
end;

function TAioIdIOHandlerSocket.WriteFile(const AFile: String;
  AEnableTransferFile: Boolean): Int64;
var
  F: IAioFile;
  FSize, RdSize: UInt64;
  Buffer: Pointer;
begin
  Result := 0;
  if FileExists(AFile) and BindingAllocated then begin
    F := MakeAioFile(AFile, fmOpenRead or fmShareDenyWrite);
    FSize := f.Seek(0, soEnd);
    Buffer := AllocMem(FSize);
    try
      RdSize := F.Read(Buffer, FSize);
      // !!!
      Assert(RdSize = FSize);
      //
      FBinding.Write(Buffer, FSize);
    finally
      FreeMem(Buffer);
    end;
  end
  else
    raise EIdFileNotFound.CreateFmt(RSFileNotFound, [AFile]);
end;

procedure MakeNonBlocking(const IdComponents: array of TIdComponent);
var
  Comp: TIdComponent;
begin
  for Comp in IdComponents do begin
    if Comp.InheritsFrom(TIdTCPConnection) then
      TIdTCPConnection(Comp).IOHandler := TAioIdIOHandlerSocket.Create(Comp);
  end
end;

end.
