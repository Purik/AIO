unit AioIndy;

interface
uses IdIOHandler, IdServerIOHandler, IdComponent, IdIOHandlerSocket, IdGlobal,
  Aio, SysUtils, IdCustomTransparentProxy, IdYarn, IdSocketHandle, IdThread;

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
    FTransparentProxy: TIdCustomTransparentProxy;
    FUseNagle: Boolean;
    FConnected: Boolean;
    function ReadDataFromSource(var VBuffer: TIdBytes): Integer; override;
    function WriteDataToTarget(const ABuffer: TIdBytes; const AOffset, ALength: Integer): Integer; override;
    function SourceIsAvailable: Boolean; override;
    function CheckForError(ALastResult: Integer): Integer; override;
    procedure RaiseError(AError: Integer); override;
    function GetTransparentProxy: TIdCustomTransparentProxy; virtual;
    procedure SetTransparentProxy(AProxy: TIdCustomTransparentProxy); virtual;
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
    property TransparentProxy: TIdCustomTransparentProxy read GetTransparentProxy write SetTransparentProxy;
  end;


  TAioIdIOHandlerSocketClass = class of TAioIdIOHandlerSocket;

  TAioIdServerIOHandler = class(TIdServerIOHandler)
  protected
    FSocket: IAioTcpSocket;
    IOHandlerSocketClass: TAioIdIOHandlerSocketClass;
    //
    procedure InitComponent; override;
  public
    function Accept(
      ASocket: TIdSocketHandle;
      AListenerThread: TIdThread;
      AYarn: TIdYarn
      ): TIdIOHandler;override;
    function MakeClientIOHandler(ATheThread: TIdYarn): TIdIOHandler; override;
  end;


implementation
uses IdExceptionCore, IdResourceStringsCore, Classes, IdStack, IdTCPConnection,
  IdSocks;

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
  if Assigned(FTransparentProxy) then begin
    if FTransparentProxy.Owner = nil then begin
      FreeAndNil(FTransparentProxy);
    end;
  end;
  FBinding := nil;
  inherited Destroy;
end;

function TAioIdIOHandlerSocket.GetTransparentProxy: TIdCustomTransparentProxy;
begin
  // Necessary at design time for Borland SOAP support
  if FTransparentProxy = nil then begin
    FTransparentProxy := TIdSocksInfo.Create(nil); //default
  end;
  Result := FTransparentProxy;
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

procedure TAioIdIOHandlerSocket.SetTransparentProxy(
  AProxy: TIdCustomTransparentProxy);
var
  LClass: TIdCustomTransparentProxyClass;
begin
  // All this is to preserve the compatibility with old version
  // In the case when we have SocksInfo as object created in runtime without owner form it is treated as temporary object
  // In the case when the ASocks points to an object with owner it is treated as component on form.

  if Assigned(AProxy) then begin
    if not Assigned(AProxy.Owner) then begin
      if Assigned(FTransparentProxy) then begin
        if Assigned(FTransparentProxy.Owner) then begin
          FTransparentProxy.RemoveFreeNotification(Self);
          FTransparentProxy := nil;
        end;
      end;
      LClass := TIdCustomTransparentProxyClass(AProxy.ClassType);
      if Assigned(FTransparentProxy) and (FTransparentProxy.ClassType <> LClass) then begin
        FreeAndNil(FTransparentProxy);
      end;
      if not Assigned(FTransparentProxy) then begin
        FTransparentProxy := LClass.Create(nil);
      end;
      FTransparentProxy.Assign(AProxy);
    end else begin
      if Assigned(FTransparentProxy) then begin
        if not Assigned(FTransparentProxy.Owner) then begin
          FreeAndNil(FTransparentProxy);
        end else begin
          FTransparentProxy.RemoveFreeNotification(Self);
        end;
      end;
      FTransparentProxy := AProxy;
      FTransparentProxy.FreeNotification(Self);
    end;
  end
  else if Assigned(FTransparentProxy) then begin
    if not Assigned(FTransparentProxy.Owner) then begin
      FreeAndNil(FTransparentProxy);
    end else begin
      FTransparentProxy.RemoveFreeNotification(Self);
      FTransparentProxy := nil; //remove link
    end;
  end;
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

{ TAioIdServerIOHandler }

function TAioIdServerIOHandler.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
var
  Address: string;
  Port: Integer;
  Cli: IAioTcpSocket;
begin
  if FSocket = nil then begin
    Address := ASocket.IP;
    Port := ASocket.Port;
    //ASocket.CloseSocket;
    FSocket := MakeAioTcpSocket;
    FSocket.Bind(Address, Port);
    FSocket.Listen;
  end;
  Cli := FSocket.Accept;
  Result := TAioIdIOHandlerSocket.Create;
  TAioIdIOHandlerSocket(Result).FBinding := Cli;
end;

procedure TAioIdServerIOHandler.InitComponent;
begin
  inherited InitComponent;
  IOHandlerSocketClass := TAioIdIOHandlerSocket;
end;

function TAioIdServerIOHandler.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := IOHandlerSocketClass.Create(nil);
end;

end.
