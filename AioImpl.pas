unit AioImpl;

interface
uses Classes, Greenlets, Gevent, Hub, SysUtils, sock, RegularExpressions, Aio,
  SyncObjs, GInterfaces,
  {$IFDEF MSWINDOWS}
  Winapi.Windows
  {$ELSE}

  {$ENDIF};

type

  TIOHandler = class(TInterfacedObject, IIoHandler)
  private
    FLock: TCriticalSection;
    FAlloc: Pointer;
    FCapacity: LongWord;
    FSize: LongWord;
    FEmitter: IGevent;
    FHandle: THandle;
    FWaitHandle: THandle;
    FErrorCode: NativeUInt;
  public
    constructor Create;
    destructor Destroy; override;
    property Handle: THandle read FHandle write FHandle;
    property WaitHandle: THandle read FWaitHandle write FWaitHandle;
    property ErrorCode: NativeUInt read FErrorCode write FErrorCode;
    procedure Lock;
    procedure Unlock;
    function Emitter: IGevent;
    function ReallocBuf(Size: LongWord): Pointer;
    function GetBuf: Pointer;
    function GetBufSize: LongWord;
  end;

  TAioProvider = class(TInterfacedObject, IAioProvider)
  type
    EIOError = class(Exception);
    AEOF = class(EAbort);
  strict private
  type
    TIO = record
      NumOfBytes: LongWord;
      LastError: Integer;
      OpCode: TIOOperation;
    end;
  const
    DEF_READ_SZ = 1024;
    DEF_EOL = CRLF;
  var
    FOnAfterRead: TGevent;
    FOnAfterWrite: TGevent;
    FReadIO: TIO;
    FWriteIO: TIO;
    FPosition: Int64;
    FEOL: string;
    FEncoding: TEncoding;
    FEOLs: array of string;
    class procedure Cb(Fd: THandle; const Op: TIOOperation; Data: Pointer;
      ErrorCode: Integer; NumOfBytes: LongWord); static;
  protected
    FAsStream: TStream;
    FAsFile: TStream;
    FAcive: Boolean;
    FRegEx: TRegEx;
    FInternalBuf: TBytes;
    FIgnoreInternalBuf: Boolean;
    FEncCopied: Boolean;
    FUseDgramApi: Boolean;
    function GetDgramReadAddress: TAnyAddress; dynamic; abstract;
    function GetDgramWriteAddress: TAnyAddress; dynamic; abstract;
    function GetFd: THandle; dynamic; abstract;
    function GetDriverRcvBufSize: LongWord; dynamic;
    function GetDriverSndBufSize: LongWord; dynamic;
    function ReadPending(Buf: Pointer; Size: LongWord): LongWord; dynamic;
    function WritePending(Buf: Pointer; Size: LongWord): LongWord; dynamic;
    function ReadFull(Buf: Pointer; Size: LongWord): LongWord;
    function WriteFull(Buf: Pointer; Size: LongWord): LongWord;
    procedure OperationComplete(const Op: TIOOperation); dynamic;
    function OnStreamRead(var Buffer; Count: Longint): LongInt;
    function OnStreamWrite(const Buffer; Count: Longint): LongInt;
    procedure SetPosition(const Value: Int64); virtual;
    function GetPosition: Int64; virtual;
    property Position: Int64 read GetPosition write SetPosition;
    property OnAfterRead: TGevent read FOnAfterRead;
    property OnAfterWrite: TGevent read FOnAfterWrite;
    procedure OperationAborted; dynamic;
    procedure ReadLnYielded;
    procedure ReadLnYieldedEOLs;
    procedure ReadRegExYielded(const A: array of const);
    function _ReadString(Enc: TEncoding; out Buf: string; const EOLs: array of string): Boolean;
    procedure DoError(ErrorCode: LongWord; const Operation: TIOOperation); dynamic;
  public
    constructor Create;
    destructor Destroy; override;
    // io operations
    // if Size > 0 -> Will return control when all bytes will be transmitted
    // if Size < 0 -> Will return control when the operation is completed partially
    // if Size = 0 -> Will return data buffer length of driver
    function Read(Buf: Pointer; Size: Integer): LongWord; dynamic;
    function Write(Buf: Pointer; Size: Integer): LongWord; dynamic;
    // stream interfaces
    function AsStream: TStream;
    function AsFile(Size: LongWord): TStream;
    // extended interfaces
    //  strings
    function GetEncoding: TEncoding;
    procedure SetEncoding(Value: TEncoding);
    function GetEOL: string; // end of line ex: LF or CRLF
    procedure SetEOL(const Value: string);
    function ReadLn: string; overload;  // raise AEOF in end of stream
    function ReadLn(out S: string): Boolean; overload;
    function ReadLns: TGenerator<string>; overload;
    function ReadLns(const EOLs: array of string): TGenerator<string>; overload;
    function ReadRegEx(const RegEx: TRegEx; out S: string): Boolean; overload;
    function ReadRegEx(const Pattern: string; out S: string): Boolean; overload;
    function ReadRegEx(const RegEx: TRegEx): TGenerator<string>; overload;
    function ReadRegEx(const Pattern: string): TGenerator<string>; overload;
    function ReadString(Enc: TEncoding; out Buf: string; const EOL: string = CRLF): Boolean;
    procedure WriteLn(const S: string); overload;
    procedure WriteLn(const S: array of string); overload;
    function WriteString(Enc: TEncoding; const Buf: string; const EOL: string = CRLF): Boolean;
    //  others
    function ReadBytes(out Buf: TBytes): Boolean;
    function ReadByte(out Buf: Byte): Boolean;
    function ReadInteger(out Buf: Integer): Boolean;
    function ReadSmallInt(out Buf: SmallInt): Boolean;
    function ReadSingle(out Buf: Single): Boolean;
    function ReadDouble(out Buf: Double): Boolean;
    function WriteBytes(const Bytes: TBytes): Boolean;
    function WriteByte(const Value: Byte): Boolean;
    function WriteInteger(const Value: Integer): Boolean;
    function WriteSmallInt(const Value: SmallInt): Boolean;
    function WriteSingle(const Value: Single): Boolean;
    function WriteDouble(const Value: Double): Boolean;
  end;

  TAioFile = class(TAioProvider, IAioFile)
  strict private
    FFileName: string;
    FFd: THandle;
    FFileSize: Int64;
    FMode: Word;
    FSeekable: Boolean;
  protected
    procedure SetPosition(const Value: Int64); override;
    function GetFd: THandle; override;
    function ReadPending(Buf: Pointer; Size: LongWord): LongWord; override;
    function WritePending(Buf: Pointer; Size: LongWord): LongWord; override;
  public
    constructor Create(const FileName: string; Mode: Word);
    destructor Destroy; override;
    property Position;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
  end;

  TAioSocket = class(TAioProvider)
  type
    ESockError = class(Exception);
    EAddressResolution = class(Exception);
  private
    FSocket: TSocket;
    FEvent: TEvent;
    FOnEvent: TGevent;
    FAcceptEvent: TEvent;
    FOnDisconnect: TGevent;
    FOnAccept: TGevent;
    FBinded: Boolean;
    {$IFDEF MSWINDOWS}
    FOverlap: TOverlapped;
    {$ENDIF}
    procedure RaiseError(ErrorCode: Integer);
  protected
    FLocalSin: TVarSin;
    FRemoteSin: TVarSin;
    function GetErrorDescr(ErrorCode: Integer): string;
    procedure GetLocalSin;
    procedure GetRemoteSin;
    procedure CreateInternal;
    procedure SetSin(var Sin: TVarSin; IP, Port: string);
    function GetDriverRcvBufSize: LongWord; override;
    function GetAddressFamily: Integer; dynamic;
    function GetType: Integer; dynamic;
    function GetProtocolFamily: Integer; dynamic;
    property OnAccept: TGevent read FOnAccept;
    procedure DoAccept(AcceptSock: TAioSocket);
    procedure CheckError(RetCode: Integer);
    function GetRemoteAddress: string;
    function GetRemotePort: string;
    function GetLocalAddress: string;
    function GetLocalPort: string;
    property OnEvent: TGevent read FOnEvent;
    procedure OperationAborted; override;
    function GetSinAddress(Sin: TVarSin): string;
    function GetSinPort(Sin: TVarSin): Integer;
    function  GetFd: THandle; override;
    procedure Bind(const Address: string; const Port: string);
    procedure Listen;
    function  Connect(const Address: string; const Port: string;
      Timeout: LongWord): Boolean;
    procedure Disconnect;
    procedure DoError(ErrorCode: LongWord; const Operation: TIOOperation); override;
  public
    constructor Create;
    destructor Destroy; override;
    function Write(Buf: Pointer; Size: Integer): LongWord; override;
  end;

  TAioTCPSocket = class(TAioSocket, IAioTcpSocket)
  strict private
    function GetOnConnect: TGevent;
  protected
    function GetAddressFamily: Integer; override;
    function GetType: Integer; override;
    function GetProtocolFamily: Integer; override;
  public
    procedure Bind(const Address: string; Port: Integer);
    procedure Listen;
    function  Accept: IAioTcpSocket;
    function  Connect(const Address: string; Port: Integer; Timeout: LongWord): Boolean;
    procedure Disconnect;
    function OnConnect: TGevent;
    function OnDisconnect: TGevent;
    function LocalAddress: TAddress;
    function RemoteAddress: TAddress;
  end;

  TAioUDPSocket = class(TAioSocket, IAioUdpSocket)
  protected
    function GetAddressFamily: Integer; override;
    function GetType: Integer; override;
    function GetProtocolFamily: Integer; override;
    function GetDgramReadAddress: TAnyAddress; override;
    function GetDgramWriteAddress: TAnyAddress; override;
  public
    constructor Create;
    procedure Bind(const Address: string; Port: Integer);
    function GetRemoteAddress: TAddress;
    procedure SetRemoteAddress(const Value: TAddress);
  end;

  TAioComPort = class(TAioProvider, IAioComPort)
  strict private
    FFileName: string;
    FFd: THandle;
    FStateEvent: SyncObjs.TEvent;
    FOnState: TGevent;
    FEventMask: LongWord;
    {$IFDEF MSWINDOWS}
    FOverlap: TOverlapped;
    {$ENDIF}
    function GetEventMask: TEventMask;
  protected
    function GetFd: THandle; override;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function EventMask: TEventMask;
    function OnState: TGevent;
  end;

  TAioNamedPipe = class(TAioProvider, IAioNamedPipe)
  strict private
    FPipeName: string;
    FFd: THandle;
    FEvent: TEvent;
    FOnConnect: TGevent;
    FOvlp: TOverlapped;
    FOpened: Boolean;
  protected
    function GetFd: THandle; override;
    function GetDriverRcvBufSize: LongWord; override;
  public
    constructor Create(const Name: string);
    destructor Destroy; override;
    // server-side
    procedure MakeServer(BufSize: Longword=4096);
    function WaitConnection(Timeout: LongWord = INFINITE): Boolean;
    // client-side
    procedure Open;
    // not remove data from read buffer
    function Peek: TBytes;
  end;

  TAioConsoleApplication = class(TInterfacedObject, IAioConsoleApplication)
  strict private
  const
    DEF_EOL = {$IFDEF MSWINDOWS}CRLF{$ELSE}CR{$ENDIF};
  type
    TInOut = record
      Pipe1: TAioNamedPipe;
      Pipe2: TAioNamedPipe;
      constructor Create(const Name: string);
      procedure Destroy;
      procedure RefreshEncodings(Enc: TEncoding; const EOL: string);
      function ParentSide: TAioNamedPipe;
      function ChildSide: TAioNamedPipe;
      class procedure DelayedOpen(const Pipe: TAioNamedPipe;
        const Timeout: LongWord); static;
    end;
  var
    FHandle: THandle;
    FProcessId: LongWord;
    FInput: TInOut;
    FOutput: TInOut;
    FError: TInOut;
    FWorkDir: string;
    FOnTerminate: TGevent;
    FPath: string;
    FGuid: string;
    FEncoding: TEncoding;
    FEncCopied: Boolean;
    FEOL: string;
    function TryCreate(const AbsPath: string; const Args: array of const): Boolean;
    procedure AllocPipes;
    procedure FinalPipes;
  public
    constructor Create(const Cmd: string; const Args: array of const;
      const WorkDir: string = '');
    destructor Destroy; override;
    // encodings
    function GetEncoding: TEncoding;
    procedure SetEncoding(Value: TEncoding);
    function GetEOL: string;
    procedure SetEOL(const Value: string);
    // in-out
    function StdIn: IAioProvider;
    function StdOut: IAioProvider;
    function StdError: IAioProvider;
    // process-specific
    function ProcessId: LongWord;
    function OnTerminate: TGevent;
    function GetExitCode(const Block: Boolean = True): Integer;
    procedure Terminate(ExitCode: Integer = 0);
  end;

  TAioConsole = class(TInterfacedObject, IAioConsole)
  strict private
  type
    TStdHandle = class(TAioProvider)
    type
      THandleType = (htInput, htOutput, htError);
    strict private
      FHandle: THandle;
      class procedure CbRead(Parameter: Pointer; const TimerOrWaitFired: Boolean); stdcall; static;
      class procedure CbWrite(Parameter: Pointer; const TimerOrWaitFired: Boolean); stdcall; static;
    protected
      function GetFd: THandle; override;
      function ReadPending(Buf: Pointer; Size: LongWord): LongWord; override;
      function WritePending(Buf: Pointer; Size: LongWord): LongWord; override;
    public
      constructor Create(const Typ: THandleType);
      destructor Destroy; override;
    end;
  var
    FStdIn: TStdHandle;
    FStdOut: TStdHandle;
    FStdError: TStdHandle;
  public
    constructor Create;
    destructor Destroy; override;
    function StdIn: IAioProvider;
    function StdOut: IAioProvider;
    function StdError: IAioProvider;
  end;

  TAioSoundCard = class(TAioProvider, IAioSoundCard)
  strict private
  const
    BUF_COUNT = 4;
  type
    TBuffersState = record
      CurBufIndex: Integer;
      ReadyCount: Integer;
      QueuedCount: Integer;
      ReadyBytesLen: Integer;
    end;
  var
    FReadEvent: TEvent;
    FWriteEvent: TEvent;
    FInDev: THandle;
    FOutDev: THandle;
    FFormat: Pointer;
    FRecBufs: array[0..BUF_COUNT-1] of Pointer;
    FRecBufState: TBuffersState;
    FPlayBufs: array[0..BUF_COUNT-1] of Pointer;
    FPlayBufsState: TBuffersState;
    FOnRead: TGevent;
    FOnWrite: TGevent;
    FRecStarted: Boolean;
    procedure UpdateRecBuffersState;
    procedure UpdatePlayBuffersState;
  protected
    function GetFd: THandle; override;
    function ReadPending(Buf: Pointer; Size: LongWord): LongWord; override;
    function WritePending(Buf: Pointer; Size: LongWord): LongWord; override;
  public
    constructor Create(SampPerFreq: LongWord; Channels: LongWord = 1; BitsPerSamp: LongWord = 16);
    destructor Destroy; override;
  end;


implementation
uses Math, System.WideStrUtils, MMSystem;

const
  END_OF_FILE_ERROR_CODE = {$IFDEF MSWINDOWS} ERROR_HANDLE_EOF {$ELSE} 111 {$ENDIF};

type
  TStreamProxy = class(TStream)
  type
    TOnRead = function(var Buffer; Count: Longint): LongInt of object;
    TOnWrite = function(const Buffer; Count: Longint): LongInt of object;
    TOnSeek = function(const Offset: Int64; Origin: TSeekOrigin): Int64 of object;
  strict private
    FProv: TAioProvider;
    FOnRead: TOnRead;
    FOnWrite: TOnWrite;
    FOnSeek: TOnSeek;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(Prov: TAioProvider);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    property OnSeek: TOnSeek read FOnSeek write FOnSeek;
  end;

{$IFDEF MSWINDOWS}
var
  WsaDataOnce: TWSADATA;
  {$I ../iocpwin.inc}
{$ENDIF}


{ TAioProvider }

function TAioProvider.AsFile(Size: LongWord): TStream;
begin
  FAsFile.Size := Size;
  Result := FAsFile;
end;

function TAioProvider.AsStream: TStream;
begin
  Result := FAsStream;
end;

class procedure TAioProvider.Cb(Fd: THandle; const Op: TIOOperation;
  Data: Pointer; ErrorCode: Integer; NumOfBytes: LongWord);
var
  Me: TAioProvider;
begin
  Me := TAioProvider(Data);
  case Op of
    ioRead: begin
      Me.FReadIO.NumOfBytes := NumOfBytes;
      Me.FReadIO.LastError := ErrorCode;
      Me.FReadIO.OpCode := Op;
    end;
    ioWrite: begin
      Me.FWriteIO.NumOfBytes := NumOfBytes;
      Me.FWriteIO.LastError := ErrorCode;
      Me.FWriteIO.OpCode := Op;
    end;
  end;
  Me.OperationComplete(Op);
end;

constructor TAioProvider.Create;
begin
  inherited;
  FPosition := -1;
  FOnAfterRead := TGevent.Create;
  FOnAfterWrite := TGevent.Create;
  FAsStream := TStreamProxy.Create(Self);
  FAsFile := TStreamProxy.Create(Self);
  FEOL := DEF_EOL;
  SetEncoding(TEncoding.Default);
end;

destructor TAioProvider.Destroy;
begin
  FOnAfterRead.Free;
  FOnAfterWrite.Free;
  FAsStream.Free;
  FAsFile.Free;
  if FEncCopied then
    FEncoding.Free;
  inherited;
end;

procedure TAioProvider.DoError(ErrorCode: LongWord;
  const Operation: TIOOperation);
begin
  //
end;

function TAioProvider.GetDriverRcvBufSize: LongWord;
begin
  if not FIgnoreInternalBuf then
    Result := Length(FInternalBuf)
  else
    Result := 0
end;

function TAioProvider.GetDriverSndBufSize: LongWord;
begin
  Result := 0;
end;

function TAioProvider.GetEncoding: TEncoding;
begin
  Result := FEncoding
end;

function TAioProvider.GetEOL: string;
begin
  Result := FEOL
end;

function TAioProvider.GetPosition: Int64;
begin
  Result := FPosition
end;

function TAioProvider.OnStreamRead(var Buffer; Count: Integer): LongInt;
begin
  Result := Read(@Buffer, Count);
end;

function TAioProvider.OnStreamWrite(const Buffer; Count: Integer): LongInt;
begin
  Result := Write(@Buffer, Count);
end;

procedure TAioProvider.OperationComplete(const Op: TIOOperation);
begin
  case Op of
    ioRead:
      FOnAfterRead.SetEvent(False);
    ioWrite:
      FOnAfterWrite.SetEvent(True);
  end;
end;

procedure TAioProvider.OperationAborted;
begin
  //
end;

function TAioProvider.Read(Buf: Pointer; Size: Integer): LongWord;
begin
  if Size > 0 then
    Result := ReadFull(Buf, Size)
  else if Size < 0 then
    Result := ReadPending(Buf, -Size)
  else
    Result := GetDriverRcvBufSize;
end;

function TAioProvider.ReadByte(out Buf: Byte): Boolean;
begin
  Result := Read(@Buf, SizeOf(Byte)) = SizeOf(Byte);
end;

function TAioProvider.ReadBytes(out Buf: TBytes): Boolean;
var
  Readed: LongWord;
  Tmp: TBytes;
  ReadSz: Integer;
begin
  Result := True;
  ReadSz := Read(nil, 0);
  if ReadSz = 0 then
    ReadSz := DEF_READ_SZ;
  SetLength(Tmp, ReadSz);
  Readed := Read(@Tmp[0], -ReadSz);
  if Readed = 0 then
    Exit(False);
  SetLength(Tmp, Readed);
  Buf := Tmp;
end;

function TAioProvider.ReadDouble(out Buf: Double): Boolean;
begin
  Result := Read(@Buf, SizeOf(Double)) = SizeOf(Double);
end;

function TAioProvider.ReadFull(Buf: Pointer; Size: LongWord): LongWord;
var
  AccumSz, ReadedSz: LongWord;
  Offset: PByte;
begin
  AccumSz := 0;
  Offset := Buf;
  while AccumSz < Size do begin
    ReadedSz := ReadPending(Offset, Size - AccumSz);
    if ReadedSz = 0 then
      Break;
    Inc(AccumSz, ReadedSz);
    Inc(Offset, ReadedSz);
  end;
  Result := AccumSz;
end;

function TAioProvider.ReadInteger(out Buf: Integer): Boolean;
begin
  Result := Read(@Buf, SizeOf(Integer)) = SizeOf(Integer)
end;

function TAioProvider.ReadLn: string;
begin
  if not ReadString(FEncoding, Result, FEOL) then
    raise AEOF.Create('EOF');
end;

function TAioProvider.ReadLn(out S: string): Boolean;
begin
  Result := ReadString(FEncoding, S, FEOL)
end;

function TAioProvider.ReadLns(const EOLs: array of string): TGenerator<string>;
var
  I: Integer;
begin
  if Length(EOLs) = 0 then
    raise EArgumentException.Create('EOL collection is empty');
  SetLength(FEOLs, Length(EOLs));
  for I := 0 to High(EOLs) do
    FEOLs[I] := EOLs[I];
  Result := TGenerator<string>.Create(ReadLnYieldedEOLs)
end;

function TAioProvider.ReadLns: TGenerator<string>;
begin
  Result := TGenerator<string>.Create(ReadLnYielded)
end;

procedure TAioProvider.ReadLnYielded;
var
  S: string;
begin
  while ReadString(FEncoding, S, FEOL) do
    TGenerator<string>.Yield(S)
end;

procedure TAioProvider.ReadLnYieldedEOLs;
var
  S: string;
begin
  while _ReadString(FEncoding, S, FEOLs) do
    TGenerator<string>.Yield(S)
end;

function TAioProvider.ReadPending(Buf: Pointer; Size: LongWord): LongWord;
var
  Check: Boolean;
begin
  if not FIgnoreInternalBuf and (Length(FInternalBuf) > 0) then begin
    Result := Length(FInternalBuf);
    Move(FInternalBuf[0], Buf^, Result);
    SetLength(FInternalBuf, 0);
    Exit;
  end;
  if not FUseDgramApi then
    Check := GetCurrentHub.Read(GetFd, Buf, Size, Cb, Self, FPosition)
  else
    Check := GetCurrentHub.ReadFrom(GetFd, Buf, Size, GetDgramReadAddress, Cb, Self);
  if not Check then begin
    OperationAborted;
    Exit(0);
  end;
  case FOnAfterRead.WaitFor of
    wrSignaled: begin
      case FReadIO.LastError of
        0: begin
          if FReadIO.NumOfBytes > 0 then
            Exit(FReadIO.NumOfBytes)
          else begin
            OperationAborted;
            Exit(0);
          end;
        end
        else begin
          SetLastError(FReadIO.LastError);
          DoError(FReadIO.LastError, ioRead);
          OperationAborted;
          Exit(0)
        end
      end
    end
    else begin
      Result := 0;
    end;
  end;
end;

function TAioProvider.ReadRegEx(const Pattern: string): TGenerator<string>;
begin
  Result := TGenerator<string>.Create(ReadRegExYielded, [True, Pattern])
end;

function TAioProvider.ReadRegEx(const RegEx: TRegEx): TGenerator<string>;
begin
  FRegEx := RegEx;
  Result := TGenerator<string>.Create(ReadRegExYielded, [False])
end;

procedure TAioProvider.ReadRegExYielded(const A: array of const);
var
  UsePattern: Boolean;
  S: string;
  RegEx: TRegEx;
begin
  UsePattern := A[0].AsBoolean;
  if UsePattern then
    RegEx := TRegEx.Create(A[1].AsString)
  else
    RegEx := FRegEx;
  while ReadRegEx(RegEx, S) do
    TGenerator<string>.Yield(S);
end;

function TAioProvider.ReadRegEx(const Pattern: string; out S: string): Boolean;
var
  RegEx: TRegEx;
begin
  RegEx := TRegEx.Create(Pattern);
  Result := ReadRegEx(RegEx, S)
end;

function TAioProvider.ReadRegEx(const RegEx: TRegEx; out S: string): Boolean;
var
  Str: string;
  B: TBytes;
  Offs: Integer;
  Match: TMatch;

  function FindMatch: Boolean;
  begin
    Result := False;
    if RegEx.IsMatch(Str) then begin
      Match := RegEx.Match(Str);
      S := Match.Value;
      Offs := Match.Index + Match.Length;
      Str := Str.Substring(Offs);
      FInternalBuf := FEncoding.GetBytes(Str);
      Exit(True)
    end;
  end;

begin
  Result := False;
  if Length(FInternalBuf) > 0 then begin
    Str := FEncoding.GetString(FInternalBuf);
    if FindMatch then
      Exit(True);
  end;
  FIgnoreInternalBuf := True;
  while ReadBytes(B) do begin
    Offs := Length(FInternalBuf);
    SetLength(FInternalBuf, Length(FInternalBuf) + Length(B));
    Move(B[0], FInternalBuf[Offs], Length(B));
    Str := FEncoding.GetString(FInternalBuf);
    if FindMatch then
      Exit(True);
  end;
  FIgnoreInternalBuf := False;
end;

function TAioProvider.ReadSingle(out Buf: Single): Boolean;
begin
  Result := Read(@Buf, SizeOf(Single)) = SizeOf(Single)
end;

function TAioProvider.ReadSmallInt(out Buf: SmallInt): Boolean;
begin
  Result := Read(@Buf, SizeOf(SmallInt)) = SizeOf(SmallInt)
end;

function TAioProvider.ReadString(Enc: TEncoding; out Buf: string;
  const EOL: string): Boolean;
begin
  Result := _ReadString(Enc, Buf, [EOL])
end;

procedure TAioProvider.SetEncoding(Value: TEncoding);
var
  NewEnc: TEncoding;
begin
  if FEncCopied then
    FEncoding.Free;
  NewEnc := Value.Clone;
  FEncCopied := NewEnc <> Value;
  FEncoding := NewEnc;
end;

procedure TAioProvider.SetEOL(const Value: string);
begin
  FEOL := Value
end;

procedure TAioProvider.SetPosition(const Value: Int64);
begin
  FPosition := Value;
  SetLength(FInternalBuf, 0);
end;

function TAioProvider.Write(Buf: Pointer; Size: Integer): LongWord;
begin
  if Size > 0 then
    Result := WriteFull(Buf, Size)
  else if Size < 0 then
    Result := WritePending(Buf, -Size)
  else
    Result := GetDriverSndBufSize;
end;

function TAioProvider.WriteByte(const Value: Byte): Boolean;
begin
  Result := Write(@Value, SizeOf(Byte)) = SizeOf(Byte)
end;

function TAioProvider.WriteBytes(const Bytes: TBytes): Boolean;
begin
  Result := Write(@Bytes[0], Length(Bytes)) = LongWord(Length(Bytes))
end;

function TAioProvider.WriteDouble(const Value: Double): Boolean;
begin
  Result := Write(@Value, SizeOf(Double)) = SizeOf(Double)
end;

function TAioProvider.WriteFull(Buf: Pointer; Size: LongWord): LongWord;
var
  AccumSz, WritedSz: LongWord;
  Offset: PByte;
begin
  AccumSz := 0;
  Offset := Buf;
  while AccumSz < Size do begin
    WritedSz := WritePending(Offset, Size - AccumSz);
    if WritedSz = 0 then
      Break;
    Inc(AccumSz, WritedSz);
    Inc(Offset, WritedSz);
  end;
  Result := AccumSz;
end;

function TAioProvider.WriteInteger(const Value: Integer): Boolean;
begin
  Result := Write(@Value, SizeOf(Integer)) = SizeOf(Integer)
end;

procedure TAioProvider.WriteLn(const S: array of string);
var
  I: string;
begin
  for I in S do
    WriteLn(I);
end;

procedure TAioProvider.WriteLn(const S: string);
begin
  WriteString(FEncoding, S, FEOL)
end;

function TAioProvider.WritePending(Buf: Pointer; Size: LongWord): LongWord;
var
  Check: Boolean;
begin
  try
    if not FUseDgramApi then
      Check := GetCurrentHub.Write(GetFd, Buf, Size, Cb, Self, FPosition)
    else
      Check := GetCurrentHub.WriteTo(GetFd, Buf, Size, GetDgramWriteAddress, Cb, Self);
    if not Check then begin
      OperationAborted;
      Exit(0);
    end;
    case FOnAfterWrite.WaitFor of
      wrSignaled: begin
        case FWriteIO.LastError of
          0: begin
            if FWriteIO.NumOfBytes > 0 then
              Exit(FWriteIO.NumOfBytes)
            else begin
              OperationAborted;
              Exit(0);
            end;
          end
          else begin
            SetLastError(FWriteIO.LastError);
            DoError(FWriteIO.LastError, ioWrite);
            OperationAborted;
            Exit(0)
          end;
        end
      end
      else begin
        Result := 0;
      end;
    end;
  except
    on E: Exception do begin
      raise Exception(AcquireExceptionObject)
    end;
  end;
end;

function TAioProvider.WriteSingle(const Value: Single): Boolean;
begin
  Result := Write(@Value, SizeOf(Single)) = SizeOf(Single)
end;

function TAioProvider.WriteSmallInt(const Value: SmallInt): Boolean;
begin
  Result := Write(@Value, SizeOf(SmallInt)) = SizeOf(SmallInt)
end;

function TAioProvider.WriteString(Enc: TEncoding; const Buf: string;
  const EOL: string): Boolean;
begin
  Result := WriteBytes(Enc.GetBytes(Buf + EOL))
end;

function TAioProvider._ReadString(Enc: TEncoding; out Buf: string;
  const EOLs: array of string): Boolean;
var
  S: string;
  B: TBytes;
  Offs: Integer;

  function Find: Boolean;
  var
    Ps: Integer;
    EOL: string;
  begin
    Ps := -1;
    for EOL in EOLs do begin
      Ps := S.IndexOf(EOL);
      if Ps >= 0 then
        Break;
    end;
    Result := Ps >= 0;
    if Result then begin
      Buf := S.Substring(0, Ps+Length(EOL));
      S := S.Substring(Length(Buf));
      FInternalBuf := Enc.GetBytes(S);
      Buf := Copy(Buf, 1, Length(Buf) - Length(EOL));
      Exit(True);
    end
  end;

begin
  Result := False;
  if Length(FInternalBuf) > 0 then begin
    S := Enc.GetString(FInternalBuf);
    if Find then
      Exit(True);
  end;
  FIgnoreInternalBuf := True;
  try
    while ReadBytes(B) do begin
      Offs := Length(FInternalBuf);
      SetLength(FInternalBuf, Length(FInternalBuf) + Length(B));
      Move(B[0], FInternalBuf[Offs], Length(B));
      S := Enc.GetString(FInternalBuf);
      if Find then
        Exit(True);
    end;
  finally
    FIgnoreInternalBuf := False;
  end;
end;

{ TStreamProxy }

constructor TStreamProxy.Create(Prov: TAioProvider);
begin
  FProv := Prov;
  FOnRead := Prov.OnStreamRead;
  FOnWrite := Prov.OnStreamWrite;
end;

function TStreamProxy.GetSize: Int64;
var
  Pos: Int64;
begin
  Pos := Seek(0, soCurrent);
  Result := Seek(0, soEnd)+1;
  Seek(Pos, soBeginning);
end;

function TStreamProxy.Read(var Buffer; Count: Integer): Longint;
begin
  Result := FOnRead(Buffer, Count);
end;

function TStreamProxy.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if Assigned(FOnSeek) then
    Result := FOnSeek(Offset, Origin)
  else
    Result := 0
end;

function TStreamProxy.Write(const Buffer; Count: Integer): Longint;
begin
  Result := FOnWrite(Buffer, Count)
end;

{ TAioComPort }

constructor TAioComPort.Create(const FileName: string);
begin
  inherited Create;
  FFileName := FileName;

  {$IFDEF MSWINDOWS}
  FFd := CreateFile(
    PChar(FileName), GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0
  );

  if FFd = INVALID_HANDLE_VALUE then
    raise EIOError.CreateFmt('Cannot create file "%s". %s',
      [ExpandFileName(FileName), SysErrorMessage(GetLastError)]);
  {$ELSE}

  {$ENDIF}

  FStateEvent := SyncObjs.TEvent.Create(nil, False, False, '');
  FOnState := TGevent.Create(FStateEvent.Handle);
  FOverlap.hEvent := FStateEvent.Handle;
  FEventMask := 0;

  {$IFDEF MSWINDOWS}
  WaitCommEvent(GetFd, FEventMask, @FOverlap);
  {$ENDIF}
end;

destructor TAioComPort.Destroy;
begin
  FOnState.Free;
  FStateEvent.Free;
  {$IFDEF MSWINDOWS}
  FlushFileBuffers(FFd);
  if FFd <> INVALID_HANDLE_VALUE then begin
    GetCurrentHub.Cancel(FFd);
    CloseHandle(FFd);
  end;
  {$ELSE}

  {$ENDIF}
  inherited;
end;

function TAioComPort.EventMask: TEventMask;
begin
  Result := GetEventMask
end;

function TAioComPort.GetEventMask: TEventMask;
begin
  Result := [];
  if Boolean(EV_BREAK and FEventMask) then
    Include(Result, evBreak);
  if Boolean(EV_CTS and FEventMask) then
    Include(Result, evCTS);
  if Boolean(EV_DSR and FEventMask) then
    Include(Result, evDSR);
  if Boolean(EV_ERR and FEventMask) then
    Include(Result, evERR);
  if Boolean(EV_RING and FEventMask) then
    Include(Result, evRING);
  if Boolean(EV_RLSD and FEventMask) then
    Include(Result, evRLSD);
  if Boolean(EV_RXCHAR and FEventMask) then
    Include(Result, evRXCHAR);
  if Boolean(EV_RXFLAG and FEventMask) then
    Include(Result, evRXFLAG);
  if Boolean(EV_TXEMPTY and FEventMask) then
    Include(Result, evTXEMPTY);
end;

function TAioComPort.GetFd: THandle;
begin
  Result := FFd
end;

function TAioComPort.OnState: TGevent;
begin
  Result := FOnState
end;

{ TAioSocket }

procedure TAioSocket.Bind(const Address: string; const Port: string);
var
  Sin: TVarSin;
begin
  if FSocket = INVALID_SOCKET then
    CreateInternal;
  if FSocket <> INVALID_SOCKET then begin
    if FBinded then
      raise ESockError.Create('Socket already binded');
    SetSin(Sin, Address, Port);
    CheckError(sock.Bind(FSocket, Sin));
    GetLocalSin;
    FBinded := True;
  end
  else
    raise ESockError.Create('Invalid socket handle');
end;

procedure TAioSocket.CheckError(RetCode: Integer);
begin
  if RetCode <> 0 then
    RaiseError(WSAGetLastError);
end;

function TAioSocket.Connect(const Address, Port: string; Timeout: LongWord): Boolean;
var
  Sin: TVarSin;
  BindSin: TVarSin;
begin
  if FSocket = INVALID_SOCKET then
    CreateInternal;
  if SetVarSin(Sin, AnsiString(Address), AnsiString(Port), GetAddressFamily,
    GetProtocolFamily, GetType, True) <> 0 then
      raise EAddressResolution.CreateFmt('%s', [GetErrorDescr(WSAGetLastError)]);
  if not FBinded then begin
    // binding
    FillChar(BindSin, SizeOf(BindSin), 0);
    BindSin.sin_family := AF_INET;
    BindSin.sin_addr.S_addr := INADDR_ANY;
    BindSin.sin_port := 0;
    CheckError(sock.bind(FSocket, BindSin));
    FBinded := True;
  end;
  {$IFDEF MSWINDOWS}
  // initialize
  FOverlap.hEvent := FEvent.Handle;
  if not ConnectEx(FSocket, @Sin, SizeOfVarSin(Sin), nil, 0, nil, @FOverlap) and
    (WSAGetLastError <> WSA_IO_PENDING) then
      RaiseError(WSAGetLastError);
  // fire!
  Result := FOnEvent.WaitFor(Timeout) = wrSignaled;
  {$ELSE}

  {$ENDIF}
  if Result then begin
    FOnDisconnect.ResetEvent;
    FAcive := True;
  end
  else begin
    // forcefully finish anyway
    Disconnect;
  end;
end;

constructor TAioSocket.Create;
begin
  inherited Create;
  FSocket := INVALID_SOCKET;
  FEvent := TEvent.Create(nil, False, False, '');
  FOnEvent := TGevent.Create(FEvent.Handle);
  FAcceptEvent := TEvent.Create(nil, False, False, '');
  FOnAccept := TGevent.Create(FAcceptEvent.Handle);
  FOnDisconnect := TGevent.Create(True, True);
end;

procedure TAioSocket.CreateInternal;
var
  {$IFDEF MSWINDOWS}
  ValBool: BOOL;
  {$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  FSocket := WSASocket(GetAddressFamily, GetType, GetProtocolFamily,
    nil, 0, WSA_FLAG_OVERLAPPED);
  {$ELSE}
  FSocket := Socket(GetAddressFamily, GetType, GetProtocolFamily);
  {$ENDIF}
  if FSocket <> INVALID_SOCKET then begin
    {$IFDEF MSWINDOWS}
    ValBool := True;
    CheckError(SetSockOpt(FSocket, SOL_SOCKET, SO_REUSEADDR, @ValBool,
      SizeOf(ValBool)));
    {$ELSE}
    CheckError(IoctlSocket(FSocket, FIONBIO, Argp))
    {$ENDIF}
  end
  else
    RaiseError(WSAGetLastError);
end;

destructor TAioSocket.Destroy;
begin
  Disconnect;
  if FSocket <> INVALID_SOCKET then
    CloseSocket(FSocket);
  FOnEvent.Free;
  FEvent.Free;
  FOnAccept.Free;
  FAcceptEvent.Free;
  FOnDisconnect.Free;
  inherited;
end;

procedure TAioSocket.Disconnect;
begin
  {$IFDEF MSWINDOWS}
  if FAcive then
    DisconnectEx(FSocket, @FOverlap, TF_REUSE_SOCKET, 0);
  {$ELSE}

  {$ENDIF}
  if FSocket <> INVALID_SOCKET then begin
    GetCurrentHub.Cancel(GetFd);
    Shutdown(FSocket, SD_BOTH);
    CloseSocket(FSocket);
    FSocket := INVALID_SOCKET;
    FBinded := False;
  end;
  FAcive := False;
  FOnDisconnect.SetEvent;
end;

procedure TAioSocket.DoAccept(AcceptSock: TAioSocket);
var
  AcceptBuf: TAcceptExBuffer;
  Bytes: Cardinal;
  B: TAddrBuffer absolute AcceptBuf;
  LocalAddrLen, RemoteAddrLen: Integer;
  PLocalAddr, PRemoteAddr: PSockAddr;
begin
  AcceptSock.SetEncoding(Self.GetEncoding);
  AcceptSock.SetEOL(Self.GetEOL);
  if AcceptSock.FSocket = INVALID_SOCKET then
    AcceptSock.CreateInternal;
  {$IFDEF MSWINDOWS}
  FOverlap.hEvent := FAcceptEvent.Handle;
  ZeroMemory(@AcceptBuf, SizeOf(AcceptBuf));
  if not AcceptEx(FSocket, AcceptSock.GetFd, @AcceptBuf, 0, SizeOf(TAddrBuffer),
    SizeOf(TAddrBuffer), Bytes, @FOverlap) and (WSAGetLastError <> WSA_IO_PENDING)  then
      RaiseError(WSAGetLastError);

  FOnAccept.WaitFor;

  GetAcceptExSockaddrs(@AcceptBuf, 0, SizeOf(TAddrBuffer),
      SizeOf(TAddrBuffer), PLocalAddr, LocalAddrLen,
      PRemoteAddr, RemoteAddrLen);
  Move(PLocalAddr^, AcceptSock.FLocalSin, SizeOf(TVarSin));
  Move(PRemoteAddr^, AcceptSock.FRemoteSin, SizeOf(TVarSin));
  {$ELSE}

  {$ENDIF}
end;

procedure TAioSocket.DoError(ErrorCode: LongWord;
  const Operation: TIOOperation);
begin
  raise ESockError.Create(GetWSAErrorDescriptor(ErrorCode));
end;

function TAioSocket.GetAddressFamily: Integer;
begin
  Result := AF_UNSPEC
end;

function TAioSocket.GetDriverRcvBufSize: LongWord;
var
  Value: Integer;
begin
  {$IFDEF MSWINDOWS}
  CheckError(IoctlSocket(FSocket, FIONREAD, Value));
  Result := LongWord(Value);
  {$ELSE}
  Result := inherited GetDriverRcvBufSize;
  {$ENDIF}
  Result := Result + LongWord(Length(FInternalBuf))
end;

function TAioSocket.GetErrorDescr(ErrorCode: Integer): string;
begin
  Result := GetWSAErrorDescriptor(ErrorCode)
end;

function TAioSocket.GetFd: THandle;
begin
  Result := FSocket;
end;

function TAioSocket.GetLocalAddress: string;
begin
  Result := GetSinAddress(FLocalSin);
end;

function TAioSocket.GetLocalPort: string;
begin
  Result := IntToStr(sock.GetSinPort(FLocalSin));
end;

procedure TAioSocket.GetLocalSin;
begin
  sock.GetSockName(FSocket, FLocalSin);
end;

function TAioSocket.GetProtocolFamily: Integer;
begin
  Result := IPPROTO_IP;
end;

function TAioSocket.GetRemoteAddress: string;
begin
  Result := GetSinAddress(FRemoteSin);
end;

function TAioSocket.GetRemotePort: string;
begin
  Result := IntToStr(sock.GetSinPort(FRemoteSin));
end;

procedure TAioSocket.GetRemoteSin;
begin
  sock.GetPeerName(FSocket, FRemoteSin);
end;

function TAioSocket.GetSinAddress(Sin: TVarSin): string;
begin
  Result := string(sock.GetSinIP(Sin));
end;

function TAioSocket.GetSinPort(Sin: TVarSin): Integer;
begin
  Result := sock.GetSinPort(Sin);
end;

function TAioSocket.GetType: Integer;
begin
  Result := SOCK_RAW
end;

procedure TAioSocket.Listen;
begin
  CheckError(sock.Listen(FSocket, SOMAXCONN))
end;

procedure TAioSocket.OperationAborted;
begin
  FAcive := False;
  FOnDisconnect.SetEvent;
  inherited;
end;

procedure TAioSocket.RaiseError(ErrorCode: Integer);
begin
  raise ESockError.Create(GetErrorDescr(ErrorCode));
end;

procedure TAioSocket.SetSin(var Sin: TVarSin; IP, Port: string);
begin
  CheckError(sock.SetVarSin(Sin, AnsiString(IP), AnsiString(Port),
    GetAddressFamily, GetProtocolFamily, GetType, True));
end;


function TAioSocket.Write(Buf: Pointer; Size: Integer): LongWord;
begin
  Result := inherited Write(Buf, Size);
  {if GetLastError <> 0 then
    raise ESockError.Create(GetWSAErrorDescriptor(GetLastError)); }
end;

{ TAioFile }

constructor TAioFile.Create(const FileName: string; Mode: Word);
var
  AccessMask, CreationFlag: LongWord;
  SzLo, SzHi: LongWord;
begin
  inherited Create;
  AccessMask := 0;
  if Mode in [fmOpenRead, fmOpenReadWrite] then
    AccessMask := AccessMask or GENERIC_READ;
  if Mode in [fmOpenWrite, fmOpenReadWrite] then
    AccessMask := AccessMask or GENERIC_WRITE;
  if Mode = fmCreate then begin
    AccessMask := GENERIC_READ or GENERIC_WRITE;
    CreationFlag := CREATE_ALWAYS;
  end
  else
    CreationFlag := OPEN_EXISTING;

  FMode := Mode;

  FFd := CreateFile(PChar(FileName), AccessMask, 0, nil, CreationFlag,
    FILE_FLAG_OVERLAPPED or FILE_ATTRIBUTE_NORMAL, 0);

  if FFd = INVALID_HANDLE_VALUE then
    raise EIOError.CreateFmt('Cannot create file "%s". %s',
      [ExpandFileName(FileName), SysErrorMessage(GetLastError)]);

  FSeekable := (GetFileType(FFd) = FILE_TYPE_DISK);
  if FSeekable then begin
    SzLo := GetFileSize(FFd, @SzHi);
    FFileSize := (SzHi shl 32) or SzLo;
    SetPosition(0);
  end;
  FFileName := FileName;
  TStreamProxy(FAsStream).OnSeek := Self.Seek;
  TStreamProxy(FAsFile).OnSeek := Self.Seek;
  FAcive := True;
end;

destructor TAioFile.Destroy;
begin
  FlushFileBuffers(FFd);
  if FFd <> INVALID_HANDLE_VALUE then begin
    GetCurrentHub.Cancel(FFd);
    CloseHandle(FFd);
  end;
  inherited;
end;

function TAioFile.GetFd: THandle;
begin
  Result := FFd
end;

function TAioFile.ReadPending(Buf: Pointer; Size: LongWord): LongWord;
begin
  Result := inherited ReadPending(Buf, Size);
  SetPosition(Position + Result);
end;

function TAioFile.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if not FSeekable then
    Result := 0
  else begin
    case Origin of
      // Код тестировался на совместимость с TFileStream
      soBeginning: SetPosition(Offset);
      soCurrent: SetPosition(Max(GetPosition + Offset, 0));
      soEnd: SetPosition(FFileSize+Offset-1);
    end;
    Result := GetPosition;
  end;
end;

procedure TAioFile.SetPosition(const Value: Int64);
begin
  if FSeekable then begin
    inherited SetPosition(Math.Min(Value, FFileSize));
    if GetPosition < 0 then
      SetPosition(FFileSize);
  end;
end;

function TAioFile.WritePending(Buf: Pointer; Size: LongWord): LongWord;
var
  NewPosition: Int64;
begin
  if not Boolean(FMode or fmOpenWrite or fmOpenReadWrite) then
    raise EIOError.CreateFmt('You have not access for writing on file %s', [FFileName]);
  Result := inherited WritePending(Buf, Size);
  NewPosition := Position + Result;
  if FSeekable and (NewPosition >= FFileSize) then
    FFileSize := NewPosition+1;
  SetPosition(NewPosition);
end;

{ TAioTCPSocket }

function TAioTCPSocket.Accept: IAioTCPSocket;
var
  Impl: TAioTCPSocket;
begin
  Impl := TAioTCPSocket.Create;
  Result := Impl;
  try
    DoAccept(Impl);
  except
    raise Exception(AcquireExceptionObject)
  end;
end;

procedure TAioTCPSocket.Bind(const Address: string; Port: Integer);
begin
  inherited Bind(Address, IntToStr(Port))
end;

function TAioTCPSocket.Connect(const Address: string;
  Port: Integer; Timeout: LongWord): Boolean;
begin
  Result := inherited Connect(Address, IntToStr(Port), Timeout)
end;

procedure TAioTCPSocket.Disconnect;
begin
  inherited Disconnect
end;

function TAioTCPSocket.GetAddressFamily: Integer;
begin
  Result := AF_INET
end;

function TAioTCPSocket.GetOnConnect: TGevent;
begin
  Result := OnEvent
end;

function TAioTCPSocket.GetProtocolFamily: Integer;
begin
  Result := IPPROTO_TCP;
end;

function TAioTCPSocket.GetType: Integer;
begin
  Result := SOCK_STREAM
end;

procedure TAioTCPSocket.Listen;
begin
  inherited Listen
end;

function TAioTCPSocket.LocalAddress: TAddress;
begin
  Result.IP := GetLocalAddress;
  Result.Port := StrToInt(GetLocalPort);
end;

function TAioTCPSocket.OnConnect: TGevent;
begin
  Result := GetOnConnect
end;

function TAioTCPSocket.OnDisconnect: TGevent;
begin
  Result := FOnDisconnect
end;

function TAioTCPSocket.RemoteAddress: TAddress;
begin
  Result.IP := GetRemoteAddress;
  Result.Port := StrToInt(GetRemotePort);
end;

{ TAioUDPSocket }

procedure TAioUDPSocket.Bind(const Address: string; Port: Integer);
begin
  inherited Bind(Address, IntToStr(Port));
end;

constructor TAioUDPSocket.Create;
begin
  inherited Create;
  FUseDgramApi := True;
end;

function TAioUDPSocket.GetAddressFamily: Integer;
begin
  Result := AF_INET
end;

function TAioUDPSocket.GetDgramReadAddress: TAnyAddress;
begin
  Result.AddrPtr := @FRemoteSin;
  Result.AddrLen := SizeOf(FRemoteSin)
end;

function TAioUDPSocket.GetDgramWriteAddress: TAnyAddress;
begin
  Result.AddrPtr := @FRemoteSin;
  Result.AddrLen := SizeOfVarSin(FRemoteSin)
end;

function TAioUDPSocket.GetProtocolFamily: Integer;
begin
  Result := IPPROTO_UDP;
end;

function TAioUDPSocket.GetRemoteAddress: TAddress;
begin
  Result.IP := inherited GetRemoteAddress;
  Result.Port := StrToInt(inherited GetRemotePort);
end;

function TAioUDPSocket.GetType: Integer;
begin
  Result := SOCK_DGRAM;
end;

procedure TAioUDPSocket.SetRemoteAddress(const Value: TAddress);
begin
  if FSocket = INVALID_SOCKET then
    CreateInternal;
  if FSocket <> INVALID_SOCKET then begin
    if SetVarSin(FRemoteSin, AnsiString(Value.IP), AnsiString(IntToStr(Value.Port)), GetAddressFamily,
      GetProtocolFamily, GetType, True) <> 0 then
        raise EAddressResolution.CreateFmt('%s', [GetErrorDescr(WSAGetLastError)]);
  end
  else
    raise ESockError.Create('Invalid socket handle');
end;

{ TAioConsoleApplication }

constructor TAioConsoleApplication.Create(const Cmd: string;
  const Args: array of const; const WorkDir: string);
var
  Succ: Boolean;
  NewEnc: TEncoding;
begin
  if WorkDir = '' then
    FWorkDir := GetCurrentDir
  else
    FWorkDir := WorkDir;

  FPath := Cmd.Replace('/', PathDelim);
  FPath := Cmd.Replace('\', PathDelim);

  FEOL := DEF_EOL;

  NewEnc := TEncoding.ASCII.GetEncoding(1251);
  FEncoding := TEncoding.ASCII.GetEncoding(1251);
  FEncCopied := NewEnc <> FEncoding;
  SetEncoding(NewEnc);
  if FEncCopied then
    NewEnc.Free;

  FGuid := Format('AioApplication_%d_%p', [GetProcessId(GetCurrentProcess), Pointer(Self)]);
  AllocPipes;

  Succ := TryCreate(FPath, Args);
  if not Succ then begin
    FinalPipes;
    raise TAioProvider.EIOError.CreateFmt('AioConsoleApplication error: %s', [SysErrorMessage(GetLastError)]);
  end;

  //FPath := ExtractRelativePath('C:\Temp', 'C:\cmd.exe')
end;

destructor TAioConsoleApplication.Destroy;
begin
  if FHandle <> 0 then begin
    Terminate;
    CloseHandle(FHandle);
  end;
  FinalPipes;
  if Assigned(FOnTerminate) then
    FOnTerminate.Free;
  if FEncCopied then
    FEncoding.Free;
  inherited;
end;

procedure TAioConsoleApplication.FinalPipes;
begin
  FError.Destroy;
  FInput.Destroy;
  FOutput.Destroy;
end;

function TAioConsoleApplication.GetEncoding: TEncoding;
begin
  Result := FEncoding
end;

function TAioConsoleApplication.GetEOL: string;
begin
  Result := FEOL
end;

function TAioConsoleApplication.GetExitCode(const Block: Boolean): Integer;
var
  Code: LongWord;
begin
  if Block then begin
    OnTerminate.WaitFor;
    if GetExitCodeProcess(FHandle, Code) then
       Result := Integer(Code)
    else
      raise TAioProvider.EIOError.CreateFmt('AioConsoleApplication.GetExitCode error: %s', [SysErrorMessage(GetLastError)]);
  end
  else begin
    if OnTerminate.WaitFor(0) = wrSignaled then begin
      if GetExitCodeProcess(FHandle, Code) then
        Result := Integer(Code)
      else
        raise TAioProvider.EIOError.CreateFmt('AioConsoleApplication.GetExitCode error: %s', [SysErrorMessage(GetLastError)]);
    end
    else
      raise TAioProvider.EIOError.Create('AioConsoleApplication.GetExitCode: process not terminated');
  end;
end;

function TAioConsoleApplication.OnTerminate: TGevent;
begin
  Result := FOnTerminate
end;

function TAioConsoleApplication.ProcessId: LongWord;
begin
  Result := FProcessId
end;

procedure TAioConsoleApplication.SetEncoding(Value: TEncoding);
var
  NewEnc: TEncoding;
begin
  if FEncCopied then
    FEncoding.Free;
  NewEnc := Value.Clone;
  FEncCopied := NewEnc <> Value;
  FEncoding := NewEnc;
  FInput.RefreshEncodings(Value, FEOL);
  FOutput.RefreshEncodings(Value, FEOL);
  FError.RefreshEncodings(Value, FEOL);
end;

procedure TAioConsoleApplication.SetEOL(const Value: string);
begin
  FInput.RefreshEncodings(FEncoding, Value);
  FOutput.RefreshEncodings(FEncoding, Value);
  FError.RefreshEncodings(FEncoding, Value);
end;

function TAioConsoleApplication.StdError: IAioProvider;
begin
  Result := FError.ParentSide
end;

function TAioConsoleApplication.StdIn: IAioProvider;
begin
  Result := FInput.ParentSide;
end;

function TAioConsoleApplication.StdOut: IAioProvider;
begin
  Result := FOutput.ParentSide
end;

procedure TAioConsoleApplication.AllocPipes;
begin
  FError := TInOut.Create(Format('%s_error', [FGuid]));
  FError.RefreshEncodings(FEncoding, FEOL);
  FInput := TInOut.Create(Format('%s_input', [FGuid]));
  FInput.RefreshEncodings(FEncoding, FEOL);
  FOutput := TInOut.Create(Format('%s_output', [FGuid]));
  FOutput.RefreshEncodings(FEncoding, FEOL);
end;

procedure TAioConsoleApplication.Terminate(ExitCode: Integer);
begin
  TerminateProcess(FHandle, ExitCode);
end;

function TAioConsoleApplication.TryCreate(const AbsPath: string;
  const Args: array of const): Boolean;
var
  CmdLine: string;
  SI: TStartupInfo;
  PI: TProcessInformation;
  ArgsStr: string;
  Tmp: array of string;
  I: Integer;
begin
  if Length(Args) = 0 then
    CmdLine := AbsPath + ' ' + ArgsStr
  else begin
    SetLength(Tmp, Length(Args));
    for I := 0 to High(Args) do
      Tmp[I] := Args[I].AsString;
    ArgsStr := string.Join(' ', Tmp);
    CmdLine := AbsPath;
  end;

  FillChar(SI, SizeOf(SI), 0);
  FillChar(PI, SizeOf(PI), 0);
  SI.cb := SizeOf(TStartupInfo);
  SI.hStdError := FError.ChildSide.GetFd;
  SI.hStdInput := FInput.ChildSide.GetFd;
  SI.hStdOutput := FOutput.ChildSide.GetFd;
  SI.dwFlags := STARTF_USESTDHANDLES;

  Result :=  CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
    PChar(FWorkDir), SI, PI);
  if Result then begin
    CloseHandle(PI.hThread);
    FProcessId := PI.dwProcessId;
    FHandle := PI.hProcess;
    FOnTerminate := TGevent.Create(FHandle);
  end;
end;

{ TAioNamedPipe }

procedure TAioNamedPipe.Open;
var
  Security: TSecurityAttributes;
begin
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  FFd := CreateFile(PChar(FPipeName), GENERIC_READ or
    GENERIC_WRITE, 0, @Security, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
  if FFd = INVALID_HANDLE_VALUE then begin
    raise EIOError.CreateFmt('AioNamedPipe. error: %s', [SysErrorMessage(GetLastError)]);
  end;
  FOpened := True;
end;

function TAioNamedPipe.Peek: TBytes;
var
  Readed: DWORD;
begin
  SetLength(Result, GetDriverRcvBufSize);
  if Length(Result) > 0 then begin
    if PeekNamedPipe(FFd, @Result[0], Length(Result), @Readed, nil, nil) then
      SetLength(Result, Readed)
    else
      SetLength(Result, 0);
  end;
end;

function TAioNamedPipe.WaitConnection(Timeout: LongWord): Boolean;
var
  FPendingCode: LongWord;
begin
  ConnectNamedPipe(FFd, @FOvlp);
  FPendingCode := GetLastError;
  case FPendingCode of
    ERROR_IO_PENDING: begin
      Result := FOnConnect.WaitFor(Timeout) = wrSignaled;
    end
    else
      raise EIOError.CreateFmt('AioNamedPipe.WaitConnection error: %s',
        [SysErrorMessage(GetLastError)]);
  end;
end;

constructor TAioNamedPipe.Create(const Name: string);
begin
  inherited Create;
  FPipeName := Format('\\.\pipe\%s', [Name]);
  FEvent := TEvent.Create(nil, False, False, '');
  FOnConnect := TGevent.Create(FEvent.Handle);
  FillChar(FOvlp, SizeOf(TOverlapped), 0);
  FOvlp.hEvent := FEvent.Handle;
end;

destructor TAioNamedPipe.Destroy;
begin
  if FOpened then
    DisconnectNamedPipe(FFd);
  GetCurrentHub.Cancel(FFd);
  CloseHandle(FFd);
  FOnConnect.Free;
  FEvent.Free;
  inherited;
end;

function TAioNamedPipe.GetDriverRcvBufSize: LongWord;
var
  Avail: DWORD;
begin
  if PeekNamedPipe(FFd, nil, 0, nil, @Avail, nil) then
    Result := Avail
  else
    Result := 0;
  Result := Result + LongWord(Length(FInternalBuf))
end;

function TAioNamedPipe.GetFd: THandle;
begin
  Result := FFd;
end;

procedure TAioNamedPipe.MakeServer(BufSize: Longword);
var
  Security: TSecurityAttributes;
begin
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;

  FFd := CreateNamedPipe(PChar(FPipeName), PIPE_ACCESS_DUPLEX or
    FILE_FLAG_OVERLAPPED, PIPE_TYPE_BYTE or PIPE_READMODE_BYTE,
    PIPE_UNLIMITED_INSTANCES, BufSize, BufSize, INFINITE, @Security);
  if FFd = INVALID_HANDLE_VALUE then begin
    raise EIOError.CreateFmt('AioNamedPipe.MakeServer error: %s', [SysErrorMessage(GetLastError)]);
  end;
end;

{ TAioConsoleApplication.TInOut }

constructor TAioConsoleApplication.TInOut.Create(const Name: string);
begin
  Pipe1 := TAioNamedPipe.Create(Name);
  Pipe1._AddRef;
  Pipe1.MakeServer;
  Pipe2 := TAioNamedPipe.Create(Name);
  Pipe2._AddRef;
  TSymmetric<TAioNamedPipe, LongWord>.Spawn(DelayedOpen, Pipe2, 0);
  Pipe1.WaitConnection
end;

class procedure TAioConsoleApplication.TInOut.DelayedOpen(const Pipe: TAioNamedPipe;
  const Timeout: LongWord);
begin
  GreenSleep(Timeout);
  Pipe.Open;
end;

procedure TAioConsoleApplication.TInOut.Destroy;
begin
  Pipe1._Release;
  Pipe2._Release;
end;

function TAioConsoleApplication.TInOut.ChildSide: TAioNamedPipe;
begin
  Result := Pipe2;
end;

function TAioConsoleApplication.TInOut.ParentSide: TAioNamedPipe;
begin
  Result := Pipe1;
end;

procedure TAioConsoleApplication.TInOut.RefreshEncodings(Enc: TEncoding;
  const EOL: string);
begin
  if Assigned(Pipe1) then begin
    Pipe1.SetEncoding(Enc);
    Pipe1.SetEOL(EOL);
  end;
  if Assigned(Pipe2) then begin
    Pipe2.SetEncoding(Enc);
    Pipe2.SetEOL(EOL);
  end;
end;

{ TAioConsole }

constructor TAioConsole.Create;
begin
  FStdIn := TStdHandle.Create(htInput);
  FStdIn._AddRef;
  FStdOut := TStdHandle.Create(htOutput);
  FStdOut._AddRef;
  FStdError := TStdHandle.Create(htError);
  FStdError._AddRef;
end;

destructor TAioConsole.Destroy;
begin
  FStdIn._Release;
  FStdOut._Release;
  FStdError._Release;
  inherited;
end;

function TAioConsole.StdError: IAioProvider;
begin
  Result := FStdError
end;

function TAioConsole.StdIn: IAioProvider;
begin
  Result := FStdIn
end;

function TAioConsole.StdOut: IAioProvider;
begin
  Result := FStdOut
end;

{ TAioConsole.TStdHandle }


class procedure TAioConsole.TStdHandle.CbRead(Parameter: Pointer;
  const TimerOrWaitFired: Boolean);
var
  Handler: TIOHandler;
  Readed: LongWord;
begin
  Handler := TIOHandler(Parameter);
  if ReadFile(Handler.Handle, Handler.GetBuf^, Handler.GetBufSize, Readed, nil) then begin
    Handler.ErrorCode := 0;
    Handler.ReallocBuf(Readed);
  end
  else begin
    Handler.ReallocBuf(0);
    Handler.ErrorCode := GetLastError;
  end;
  UnregisterWait(Handler.WaitHandle);
  Handler.Emitter.SetEvent;
  Handler._Release;
end;

class procedure TAioConsole.TStdHandle.CbWrite(Parameter: Pointer;
  const TimerOrWaitFired: Boolean);
var
  Handler: TIOHandler;
  Writed: LongWord;
begin
  Handler := TIOHandler(Parameter);
  if WriteFile(Handler.Handle, Handler.GetBuf^, Handler.GetBufSize, Writed, nil) then begin
    Handler.ErrorCode := 0;
    Handler.ReallocBuf(Writed);
  end
  else begin
    Handler.ReallocBuf(0);
    Handler.ErrorCode := GetLastError;
  end;
  UnregisterWait(Handler.WaitHandle);
  Handler.Emitter.SetEvent;
  Handler._Release;
end;

constructor TAioConsole.TStdHandle.Create(const Typ: THandleType);
begin
  inherited Create;
  case Typ of
    htInput:
      FHandle := GetStdHandle(STD_INPUT_HANDLE);
    htOutput:
      FHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    htError:
      FHandle := GetStdHandle(STD_ERROR_HANDLE);
  end;
end;

destructor TAioConsole.TStdHandle.Destroy;
begin
  CloseHandle(FHandle);
  inherited;
end;

function TAioConsole.TStdHandle.GetFd: THandle;
begin
  Result := FHandle
end;

function TAioConsole.TStdHandle.ReadPending(Buf: Pointer;
  Size: LongWord): LongWord;
var
  Handler: TIOHandler;
begin
  Result := 0;
  if not FIgnoreInternalBuf and (Length(FInternalBuf) > 0) then begin
    Result := Length(FInternalBuf);
    Move(FInternalBuf[0], Buf^, Result);
    SetLength(FInternalBuf, 0);
    Exit;
  end;
  Handler := TIOHandler.Create;
  Handler.Handle := FHandle;
  Handler.ReallocBuf(Size);
  Handler._AddRef;
  Handler._AddRef;
  try
    if RegisterWaitForSingleObject(Handler.FWaitHandle, FHandle, @CbRead, Handler, INFINITE,
          WT_EXECUTELONGFUNCTION or WT_EXECUTEONLYONCE) then
    begin
      if Handler.Emitter.WaitFor = wrSignaled then begin
        if Handler.ErrorCode = 0 then begin
          Move(Handler.GetBuf^, Buf^, Handler.GetBufSize);
          Result := Handler.GetBufSize
        end
        else
          raise EIOError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
      end
      else
        Result := 0;
    end
    else begin
      Handler._Release;
      raise EIOError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
    end;
  finally
    Handler._Release;
  end;
end;

function TAioConsole.TStdHandle.WritePending(Buf: Pointer;
  Size: LongWord): LongWord;
var
  Handler: TIOHandler;
begin
  Result := 0;
  Handler := TIOHandler.Create;
  Handler.Handle := FHandle;
  Handler.ReallocBuf(Size);
  Handler._AddRef;
  Handler._AddRef;
  try
    Move(Buf^, Handler.GetBuf^, Handler.GetBufSize);
    if RegisterWaitForSingleObject(Handler.FWaitHandle, FHandle, @CbWrite, Handler, INFINITE,
          WT_EXECUTELONGFUNCTION or WT_EXECUTEONLYONCE) then
    begin
      if Handler.Emitter.WaitFor = wrSignaled then begin
        if Handler.ErrorCode = 0 then
          Result := Handler.GetBufSize
        else
          raise EIOError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
      end
      else
        Result := 0;
    end
    else begin
      Handler._Release;
      raise EIOError.CreateFmt('Error Message: %s', [SysErrorMessage(GetLastError)]);
    end;
  finally
    Handler._Release;
  end;
end;

{ TAioSoundCard }

constructor TAioSoundCard.Create(SampPerFreq, Channels: LongWord; BitsPerSamp: LongWord);
var
  I: Integer;
begin
  FReadEvent := TEvent.Create(nil, False, False, '');
  FWriteEvent := TEvent.Create(nil, False, True, '');
  FOnRead := TGevent.Create(FReadEvent.Handle);
  FOnWrite := TGevent.Create(FWriteEvent.Handle);
  FFormat := AllocMem(SizeOf(TWaveFormatEx));
  PWaveFormatEx(FFormat)^.wFormatTag := WAVE_FORMAT_PCM;
  PWaveFormatEx(FFormat)^.nChannels := Channels;
  PWaveFormatEx(FFormat)^.nSamplesPerSec := SampPerFreq;
  PWaveFormatEx(FFormat)^.nBlockAlign := BitsPerSamp div 8;
  PWaveFormatEx(FFormat)^.nAvgBytesPerSec := SampPerFreq * BitsPerSamp div 8;
  PWaveFormatEx(FFormat)^.wBitsPerSample := BitsPerSamp;
  PWaveFormatEx(FFormat)^.cbSize := 0;
  // Recording
  if waveInOpen(@FInDev, WAVE_MAPPER, FFormat, FReadEvent.Handle, 0, CALLBACK_EVENT) = MMSYSERR_NOERROR then begin
    for I := 0 to BUF_COUNT-1 do begin
      FRecBufs[I] := AllocMem(SizeOf(TWaveHdr));
      FillChar(FRecBufs[I]^, SizeOf(TWaveHdr), 0);
      PWaveHdr(FRecBufs[I])^.dwBufferLength := PWaveFormatEx(FFormat)^.nAvgBytesPerSec;
      PWaveHdr(FRecBufs[I])^.lpData := nil;
      Inc(FRecBufState.ReadyBytesLen, PWaveHdr(FRecBufs[I])^.dwBufferLength);
    end;
    FRecBufState.ReadyCount := BUF_COUNT;
  end
  else begin
    FInDev := 0;
  end;
  // Playing
  if waveOutOpen(@FOutDev, WAVE_MAPPER, FFormat, FWriteEvent.Handle, 0, CALLBACK_EVENT) = MMSYSERR_NOERROR then begin
    for I := 0 to BUF_COUNT-1 do begin
      FPlayBufs[I] := AllocMem(SizeOf(TWaveHdr));
      FillChar(FPlayBufs[I]^, SizeOf(TWaveHdr), 0);
      PWaveHdr(FPlayBufs[I])^.dwBufferLength := PWaveFormatEx(FFormat)^.nAvgBytesPerSec;
      PWaveHdr(FPlayBufs[I])^.lpData := nil;
      Inc(FPlayBufsState.ReadyBytesLen, PWaveHdr(FPlayBufs[I])^.dwBufferLength);
    end;
    FPlayBufsState.ReadyCount := BUF_COUNT;
  end
  else begin
    FOutDev := 0;
  end;
end;

destructor TAioSoundCard.Destroy;
var
  I: Integer;
begin
  FOnRead.Free;
  FOnWrite.Free;
  FReadEvent.Free;
  FWriteEvent.Free;
  FreeMem(FFormat);
  waveInClose(FInDev);
  waveOutClose(FOutDev);
  for I := 0 to BUF_COUNT-1 do begin
    //FreeMem(PWaveHdr(FPlayBufs[I])^.lpData);
    FreeMem(FRecBufs[I]);
    FreeMem(FPlayBufs[I]);
  end;
  inherited;
end;

function TAioSoundCard.GetFd: THandle;
begin
  Result := FReadEvent.Handle
end;

function TAioSoundCard.ReadPending(Buf: Pointer; Size: LongWord): LongWord;
var
  Hdr: PWaveHdr;
  Offset: Pointer;
  Capacity, BytesToRead: LongWord;
begin
  Offset := Buf;
  Capacity := Size;
  while FRecBufState.ReadyBytesLen = 0 do begin
    if FOnRead.WaitFor <> wrSignaled then
      Exit(0);
    UpdateRecBuffersState;
  end;
  while (FRecBufState.ReadyBytesLen > 0) and (Capacity > 0) do begin
    Hdr := PWaveHdr(FRecBufs[FRecBufState.CurBufIndex]);
    BytesToRead := Min(Hdr.dwBufferLength, Capacity);
    //Move(Offset^, Hdr.lpData[0], BytesToRead);
    Hdr.lpData := Offset;
    Hdr.dwBufferLength := BytesToRead;
    waveInPrepareHeader(FInDev, Hdr, SizeOf(TWaveHdr));
    waveInAddBuffer(FInDev, Hdr, SizeOf(TWaveHdr));
    UpdateRecBuffersState;
    FRecBufState.CurBufIndex := (FRecBufState.CurBufIndex + 1) mod Length(FRecBufs);
    Offset := Pointer(NativeUint(Offset) + BytesToRead);
    Dec(Capacity, BytesToRead);
  end;
  if Capacity > 0 then
    Result := Size - Capacity
  else
    Result := Size;
  if not FRecStarted then begin
    if waveInStart(FInDev) = MMSYSERR_NOERROR then
      FRecStarted := True;
  end;
  FOnRead.WaitFor;
  UpdateRecBuffersState;
end;

procedure TAioSoundCard.UpdatePlayBuffersState;
var
  I: Integer;
  State: TBuffersState;
begin
  ZeroMemory(@State, SizeOf(State));
  for I := 0 to High(FPlayBufs) do begin
    if Boolean(PWaveHdr(FPlayBufs[I])^.dwFlags and WHDR_INQUEUE) then begin
      Inc(State.QueuedCount)
    end
    else begin
      Inc(State.ReadyCount);
      Inc(State.ReadyBytesLen, PWaveHdr(FPlayBufs[I])^.dwBufferLength);
    end
  end;
  FPlayBufsState.ReadyCount := State.ReadyCount;
  FPlayBufsState.QueuedCount := State.QueuedCount;
  FPlayBufsState.ReadyBytesLen := State.ReadyBytesLen;
end;

procedure TAioSoundCard.UpdateRecBuffersState;
var
  I: Integer;
  State: TBuffersState;
begin
  ZeroMemory(@State, SizeOf(State));
  for I := 0 to High(FRecBufs) do begin
    if Boolean(PWaveHdr(FRecBufs[I])^.dwFlags and WHDR_INQUEUE) then begin
      Inc(State.QueuedCount)
    end
    else begin
      Inc(State.ReadyCount);
      Inc(State.ReadyBytesLen, PWaveHdr(FRecBufs[I])^.dwBufferLength);
    end
  end;
  FRecBufState.ReadyCount := State.ReadyCount;
  FRecBufState.QueuedCount := State.QueuedCount;
  FRecBufState.ReadyBytesLen := State.ReadyBytesLen;
end;

function TAioSoundCard.WritePending(Buf: Pointer; Size: LongWord): LongWord;
var
  Hdr: PWaveHdr;
  Offset: Pointer;
  Capacity, BytesToWrite: LongWord;
begin
  Offset := Buf;
  Capacity := Size;
  while FPlayBufsState.ReadyBytesLen = 0 do begin
    if FOnWrite.WaitFor <> wrSignaled then
      Exit(0);
    UpdatePlayBuffersState;
  end;
  while (FPlayBufsState.ReadyBytesLen > 0) and (Capacity > 0) do begin
    Hdr := PWaveHdr(FPlayBufs[FPlayBufsState.CurBufIndex]);
    BytesToWrite := Min(Hdr.dwBufferLength, Capacity);
    Hdr.lpData := Offset;
    Hdr.dwBufferLength := BytesToWrite;
    waveOutPrepareHeader(FOutDev, Hdr, SizeOf(TWaveHdr));
    waveOutWrite(FOutDev, Hdr, SizeOf(TWaveHdr));
    UpdatePlayBuffersState;
    FPlayBufsState.CurBufIndex := (FPlayBufsState.CurBufIndex + 1) mod Length(FPlayBufs);
    Offset := Pointer(NativeUint(Offset) + BytesToWrite);
    Dec(Capacity, BytesToWrite);
  end;
  if Capacity > 0 then
    Result := Size - Capacity
  else
    Result := Size;
  FOnWrite.WaitFor;
  UpdatePlayBuffersState;
end;

{ TIOHandler }

constructor TIOHandler.Create;
begin
  FEmitter := TGevent.Create;
  FLock := TCriticalSection.Create;
end;

destructor TIOHandler.Destroy;
begin
  FreeMem(FAlloc, FCapacity);
  FLock.Free;
  inherited;
end;

function TIOHandler.Emitter: IGevent;
begin
  Result := FEmitter
end;

function TIOHandler.ReallocBuf(Size: LongWord): Pointer;
begin
  FSize := Size;
  if FCapacity < FSize then begin
    FAlloc := ReallocMemory(FAlloc, FSize);
    FCapacity := FSize;
  end;
  Result := FAlloc;
end;

function TIOHandler.GetBuf: Pointer;
begin
  Result := FAlloc;
end;

function TIOHandler.GetBufSize: LongWord;
begin
  Result := FSize
end;

procedure TIOHandler.Lock;
begin
  FLock.Acquire
end;

procedure TIOHandler.Unlock;
begin
  FLock.Release
end;

initialization
  InitSocketInterface('');
  sock.WSAStartup(WinsockLevel, WsaDataOnce);
  InitializeStubsEx;

finalization
  sock.WSACleanup;
  DestroySocketInterface;

end.


