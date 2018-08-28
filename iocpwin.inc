type
  FARPROC = Pointer;
  EIdWinsockStubError = class(Exception)
  protected
    FWin32Error : DWORD;
    FWin32ErrorMessage : String;
    FTitle : String;
  public
    constructor Create(AWin32Error: DWORD; const ATitle: String; AArgs: array of const);
    property Win32Error : DWORD read FWin32Error;
    property Win32ErrorMessage : String read FWin32ErrorMessage;
    property Title : String read FTitle;
  end;

const
  RSWinsockCallError = 'Error on call to Winsock2 library function %s';

  SIZE_GUID = DWORD(SizeOf(TGuid));

  SIZE_FARPROC = DWORD(SizeOf(FARPROC));

  TF_REUSE_SOCKET    = $02;

  SOL_SOCKET       = $FFFF;

  SO_UPDATE_ACCEPT_CONTEXT = $700B;

  SD_RECEIVE = $00;
  SD_SEND    = $01;
  SD_BOTH    = $02;

  MSG_OOB          = $1;             // process out-of-band data
  MSG_PEEK         = $2;             // peek at incoming message
  MSG_DONTROUTE    = $4;             // send without using routing tables
  MSG_PARTIAL      = $8000;          // partial send or recv for message xport

  WSAID_ACCEPTEX: TGuid = (D1:$b5367df1;D2:$cbac;D3:$11cf;D4:($95,$ca,$00,$80,$5f,$48,$a1,$92));
  WSAID_CONNECTEX: TGuid = (D1:$25a207b9;D2:$ddf3;D3:$4660;D4:($8e,$e9,$76,$e5,$8c,$74,$06,$3e));
  WSAID_DISCONNECTEX: TGuid = (D1:$7fda2e11;D2:$8630;D3:$436f;D4:($a0,$31,$f5,$36,$a6,$ee,$c1,$57));
  WSAID_GETACCEPTEXSOCKADDRS: TGuid = (D1:$b5367df2;D2:$cbac;D3:$11cf;D4:($95,$ca,$00,$80,$5f,$48,$a1,$92));
  WSAID_WSARECVMSG: TGuid = (D1:$f689d7c8;D2:$6f1f;D3:$436b;D4:($8a,$53,$e5,$4f,$e3,$51,$c3,$22));
  WSAID_WSASENDMSG : TGuid = (D1:$a441e712;D2:$754f;D3:$43ca;D4:($84,$a7,$0d,$ee,$44,$cf,$60,$6d));
  
  WSA_FLAG_OVERLAPPED  = $01;
  WSA_IO_PENDING       = ERROR_IO_PENDING;
  
  IOC_OUT      = $40000000;
  IOC_IN       = $80000000;
  IOC_INOUT    = (IOC_IN or IOC_OUT);

  IOC_WS2      = $08000000;

  SIO_GET_EXTENSION_FUNCTION_POINTER  =  DWORD(IOC_INOUT or IOC_WS2 or 6);
  SIO_ROUTING_INTERFACE_QUERY         = DWORD(IOC_INOUT or IOC_WS2 or 20);
  
type
  WSABUF = record
    len: u_long;    { the length of the buffer }
    buf: PAnsiChar; { the pointer to the buffer }
  end;

  TWSABuf = WSABUF;
  PWSABuf = ^TWSABuf;
  LPWSABUF = PWSABUF;

  WSAEVENT = THandle;

  WSAMSG = record
    name : PSOCKADDR;  ///* Remote address */
    namelen : Integer; ///* Remote address length *
    lpBuffers : LPWSABUF;  //  /* Data buffer array */
    dwBufferCount : DWord; //  /* Number of elements in the array */
    Control : WSABUF;  //  /* Control buffer */
    dwFlags : DWord; //  /* Flags */
  end;
  TWSAMSG = WSAMSG;
  PWSAMSG = ^TWSAMSG;
  LPWSAMSG = PWSAMSG;

  LPWSAOVERLAPPED_COMPLETION_ROUTINE = procedure(const dwError, cbTransferred: DWORD;
    const lpOverlapped : pOverlapped; const dwFlags: DWORD); stdcall;

  LPFN_CONNECTEX = function(const s : TSocket; const name: PSOCKADDR;
    const namelen: Integer; lpSendBuffer : Pointer; dwSendDataLength : DWORD;
    lpdwBytesSent : Pointer; lpOverlapped : POverlapped) : BOOL; stdcall;
  LPFN_DISCONNECTEX = function(const hSocket : TSocket; AOverlapped: Pointer;
    const dwFlags : DWORD; const dwReserved : DWORD) : BOOL; stdcall;
  LPFN_ACCEPTEX = function(sListenSocket, sAcceptSocket: TSocket;
    lpOutputBuffer: Pointer; dwReceiveDataLength, dwLocalAddressLength,
    dwRemoteAddressLength: DWORD; var lpdwBytesReceived: DWORD;
    lpOverlapped: POverlapped): BOOL; stdcall;
  LPFN_GETACCEPTEXSOCKADDRS = procedure(lpOutputBuffer: Pointer;
    dwReceiveDataLength, dwLocalAddressLength, dwRemoteAddressLength: DWORD;
    var LocalSockaddr: PSockAddr; var LocalSockaddrLength: Integer;
    var RemoteSockaddr: PSockAddr; var RemoteSockaddrLength: Integer); stdcall;
  LPFN_WSASOCKET = function(af, iType, protocol : Integer;
    lpProtocolInfo : Pointer; g : DWORD; dwFlags : DWORD): TSocket; stdcall;
  LPFN_SETSOCKOPT = function(const s: TSocket; const level, optname: Integer;
    optval: PAnsiChar; const optlen: Integer): Integer; stdcall;
  LPFN_WSARECVFROM = function(const s : TSocket; lpBuffers : LPWSABUF;
    dwBufferCount : DWORD; lpNumberOfBytesRecvd : PDWORD;
    var lpFlags : DWORD; lpFrom : PSOCKADDR; lpFromlen : PInteger;
    AOverlapped: Pointer;
    lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
  LPFN_WSASENDTO = function(const s : TSocket; lpBuffers : LPWSABUF;
    dwBufferCount : DWORD; var lpNumberOfBytesSent : DWORD; dwFlags : DWORD;
    lpTo : PSOCKADDR; iTolen : Integer; lpOverlapped : pOverlapped;
    lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
  LPFN_WSARECVMSG = function(const s : TSocket; lpMsg : LPWSAMSG;
    var lpNumberOfBytesRecvd : DWORD; AOverlapped: Pointer;
    lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
  LPFN_WSASENDMSG = function(const s : TSocket; lpMsg : LPWSAMSG;
    const dwFlags : DWORD; var lpNumberOfBytesSent : DWORD;
    lpOverlapped : POverlapped;
    lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE) : Integer; stdcall;
  
  TAddrUnion = record
    case Integer of
      0: (IPv4: TSockAddrIn);
      1: (IPv6: TSockAddrIn6);
  end;
  TAddrBuffer = record
    Addr: TAddrUnion;
    Extra: array [0..15] of Byte;
  end;
  TAcceptExBuffer = array[0..SizeOf(TAddrBuffer) * 2 - 1] of Byte;

	
var
  AcceptEx : LPFN_ACCEPTEX = nil;
  ConnectEx: LPFN_CONNECTEX = nil;
  DisconnectEx: LPFN_DISCONNECTEX = nil;
  GetAcceptExSockaddrs: LPFN_GETACCEPTEXSOCKADDRS = nil;
  WSASocket: LPFN_WSASOCKET = nil;
  setsockopt: LPFN_SETSOCKOPT = nil;
  WSASendTo: LPFN_WSASENDTO = nil;
  WSARecvFrom: LPFN_WSARECVFROM = nil;
  WSARecvMsg: LPFN_WSARECVMSG = nil;
  WSASendMsg: LPFN_WSASENDMSG = nil;
  
function FixupStubEx(hSocket: TSocket; const AName: string; const AGuid: TGUID): Pointer;
var
  LStatus: LongInt;
  LBytesSend: DWORD;
begin
  LStatus := WSAIoctl(hSocket, SIO_GET_EXTENSION_FUNCTION_POINTER, @AGuid, LongWord(SIZE_GUID),
    @Result, SIZE_FARPROC, @LBytesSend, nil, nil);
  if LStatus <> 0 then begin
    raise EIdWinsockStubError.Create(WSAGetLastError, RSWinsockCallError, [AName]);
  end;
end;

procedure InitializeStubsEx;
var
  LSocket: TSocket;
  LibHandle: THandle;
begin
  LibHandle := LoadLibrary(DLLStackName);
  @WSASocket := GetProcAddress(LibHandle, 'WSASocketW');
  @setsockopt := GetProcAddress(LibHandle, 'setsockopt');
  @WSASendTo := GetProcAddress(LibHandle, 'WSASendTo');
  @WSARecvFrom := GetProcAddress(LibHandle, 'WSARecvFrom');
  LSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  try
    @AcceptEx := FixupStubEx(LSocket, 'AcceptEx', WSAID_ACCEPTEX);
    @GetAcceptExSockaddrs := FixupStubEx(LSocket, 'GetAcceptExSockaddrs', WSAID_GETACCEPTEXSOCKADDRS);
    @ConnectEx := FixupStubEx(LSocket, 'ConnectEx', WSAID_CONNECTEX);
    @DisconnectEx := FixupStubEx(LSocket, 'DisconnectEx', WSAID_DISCONNECTEX);
    @WSARecvMsg := FixupStubEx(LSocket, 'WSARecvMsg', WSAID_WSARECVMSG);
    @WSASendMsg := FixupStubEx(LSocket, 'WSASendMsg', WSAID_WSASENDMSG);
  finally
    closesocket(LSocket);
  end;
end;

constructor EIdWinsockStubError.Create(AWin32Error: DWORD; const ATitle: String; AArgs: array of const);
begin
  FTitle := Format(ATitle, AArgs, TFormatSettings.Create);
  FWin32Error := AWin32Error;
  if AWin32Error = 0 then begin
    inherited Create(FTitle);
  end else
  begin
    FWin32ErrorMessage := SysUtils.SysErrorMessage(AWin32Error);
    inherited Create(FTitle + ': ' + FWin32ErrorMessage);
  end;
end;

function GetWSAErrorDescriptor(ErrorCode: Integer): string;
begin
  case ErrorCode of
    0:
      Result := '';
    WSAEINTR: {10004}
      Result := 'Interrupted system call';
    WSAEBADF: {10009}
      Result := 'Bad file number';
    WSAEACCES: {10013}
      Result := 'Permission denied';
    WSAEFAULT: {10014}
      Result := 'Bad address';
    WSAEINVAL: {10022}
      Result := 'Invalid argument';
    WSAEMFILE: {10024}
      Result := 'Too many open files';
    WSAEWOULDBLOCK: {10035}
      Result := 'Operation would block';
    WSAEINPROGRESS: {10036}
      Result := 'Operation now in progress';
    WSAEALREADY: {10037}
      Result := 'Operation already in progress';
    WSAENOTSOCK: {10038}
      Result := 'Socket operation on nonsocket';
    WSAEDESTADDRREQ: {10039}
      Result := 'Destination address required';
    WSAEMSGSIZE: {10040}
      Result := 'Message too long';
    WSAEPROTOTYPE: {10041}
      Result := 'Protocol wrong type for Socket';
    WSAENOPROTOOPT: {10042}
      Result := 'Protocol not available';
    WSAEPROTONOSUPPORT: {10043}
      Result := 'Protocol not supported';
    WSAESOCKTNOSUPPORT: {10044}
      Result := 'Socket not supported';
    WSAEOPNOTSUPP: {10045}
      Result := 'Operation not supported on Socket';
    WSAEPFNOSUPPORT: {10046}
      Result := 'Protocol family not supported';
    WSAEAFNOSUPPORT: {10047}
      Result := 'Address family not supported';
    WSAEADDRINUSE: {10048}
      Result := 'Address already in use';
    WSAEADDRNOTAVAIL: {10049}
      Result := 'Can''t assign requested address';
    WSAENETDOWN: {10050}
      Result := 'Network is down';
    WSAENETUNREACH: {10051}
      Result := 'Network is unreachable';
    WSAENETRESET: {10052}
      Result := 'Network dropped connection on reset';
    WSAECONNABORTED: {10053}
      Result := 'Software caused connection abort';
    WSAECONNRESET: {10054}
      Result := 'Connection reset by peer';
    WSAENOBUFS: {10055}
      Result := 'No Buffer space available';
    WSAEISCONN: {10056}
      Result := 'Socket is already connected';
    WSAENOTCONN: {10057}
      Result := 'Socket is not connected';
    WSAESHUTDOWN: {10058}
      Result := 'Can''t send after Socket shutdown';
    WSAETOOMANYREFS: {10059}
      Result := 'Too many references:can''t splice';
    WSAETIMEDOUT: {10060}
      Result := 'Connection timed out';
    WSAECONNREFUSED: {10061}
      Result := 'Connection refused';
    WSAELOOP: {10062}
      Result := 'Too many levels of symbolic links';
    WSAENAMETOOLONG: {10063}
      Result := 'File name is too long';
    WSAEHOSTDOWN: {10064}
      Result := 'Host is down';
    WSAEHOSTUNREACH: {10065}
      Result := 'No route to host';
    WSAENOTEMPTY: {10066}
      Result := 'Directory is not empty';
    WSAEPROCLIM: {10067}
      Result := 'Too many processes';
    WSAEUSERS: {10068}
      Result := 'Too many users';
    WSAEDQUOT: {10069}
      Result := 'Disk quota exceeded';
    WSAESTALE: {10070}
      Result := 'Stale NFS file handle';
    WSAEREMOTE: {10071}
      Result := 'Too many levels of remote in path';
    WSASYSNOTREADY: {10091}
      Result := 'Network subsystem is unusable';
    WSAVERNOTSUPPORTED: {10092}
      Result := 'Winsock DLL cannot support this application';
    WSANOTINITIALISED: {10093}
      Result := 'Winsock not initialized';
    WSAEDISCON: {10101}
      Result := 'Disconnect';
    WSAHOST_NOT_FOUND: {11001}
      Result := 'Host not found';
    WSATRY_AGAIN: {11002}
      Result := 'Non authoritative - host not found';
    WSANO_RECOVERY: {11003}
      Result := 'Non recoverable error';
    WSANO_DATA: {11004}
      Result := 'Valid name, no data record of requested type'
  else
    Result := 'Other Winsock error (' + IntToStr(ErrorCode) + ')';
  end;
end;

  