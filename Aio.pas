// **************************************************************************************************
// Delphi Aio Library.
// Unit Aio
// https://github.com/Purik/AIO

// The contents of this file are subject to the Apache License 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
//
// The Original Code is Aio.pas.
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

unit Aio;

interface
uses Classes, Greenlets, Gevent, Hub, SysUtils, sock, RegularExpressions,
  SyncObjs, IdGlobal,
  {$IFDEF MSWINDOWS}
  Winapi.Windows
  {$ELSE}

  {$ENDIF};

const
  CR = #$0d;
  LF = #$0a;
  CRLF = CR + LF;

type

  IAioProvider = interface
    ['{2E14A16F-BDF8-4116-88A6-41C18591D444}']
    function GetFd: THandle;
    // io operations
    // if Size > 0 -> Will return control when all bytes will be transmitted
    // if Size < 0 -> Will return control when the operation is completed partially
    // if Size = 0 -> Will return data buffer length of driver
    function Read(Buf: Pointer; Size: Integer): LongWord;
    function Write(Buf: Pointer; Size: Integer): LongWord;
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
    procedure WriteLn(const S: string = ''); overload;
    procedure WriteLn(const S: array of string); overload;
    function WriteString(Enc: TEncoding; const Buf: string; const EOL: string = CRLF): Boolean;
    //  others
    function ReadBytes(out Buf: TBytes): Boolean; overload;
    function ReadBytes(out Buf: TIdBytes): Boolean; overload;
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

  IAioFile = interface(IAioProvider)
    ['{94C6A1A6-790D-4993-8C47-25B11E9994EC}']
    function GetPosition: Int64;
    procedure SetPosition(const Value: Int64);
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
  end;

  TAddress = record
    IP: string;
    Port: Integer;
    function ToString: string;
    constructor Create(const IP: string; Port: Integer);
  end;

  IAioTcpSocket = interface(IAioProvider)
    ['{AB418388-935A-4D8E-B772-E7C47760BAC5}']
    procedure Bind(const Address: string; Port: Integer);
    procedure Listen;
    function  Accept: IAioTcpSocket;
    function  Connect(const Address: string; Port: Integer; Timeout: LongWord): Boolean;
    procedure Disconnect;
    function  OnConnect: TGevent;
    function  OnDisconnect: TGevent;
    function  LocalAddress: TAddress;
    function  RemoteAddress: TAddress;
  end;

  IAioUdpSocket = interface(IAioProvider)
    ['{58614476-06E6-4C46-BAE5-CF69D129FD93}']
    procedure Bind(const Address: string; Port: Integer);
    function GetRemoteAddress: TAddress;
    procedure SetRemoteAddress(const Value: TAddress);
  end;

  TComState = (
      evBreak, evCTS, evDSR, evERR, evRING, evRLSD, evRXCHAR,
      evRXFLAG, evTXEMPTY
    );
  TEventMask = set of TComState;

  IAioComPort = interface(IAioProvider)
    ['{DC8E2309-EE04-4D49-AB83-36ED2D5FD7D3}']
    function EventMask: TEventMask;
    function OnState: TGevent;
  end;

  IAioNamedPipe = interface(IAioProvider)
    ['{3E60B4DE-3EEA-425C-8902-4A16DA187F28}']
    // server-side
    procedure MakeServer(BufSize: Longword=4096);
    function WaitConnection(Timeout: LongWord = INFINITE): Boolean;
    // client-side
    procedure Open;
    // not remove data from read buffer
    function Peek: TBytes;
  end;

  IAioConsoleApplication = interface
    ['{061B7959-057F-447F-9086-26FC6D93F26F}']
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

  IAioConsole = interface
    ['{6D99A321-A851-4FA6-9E19-649F085ADCD1}']
    function StdIn: IAioProvider;
    function StdOut: IAioProvider;
    function StdError: IAioProvider;
  end;

  IAioSoundCard = interface(IAioProvider)
    ['{E16E70D3-7052-431C-BD94-38B462D2B72F}']
  end;

function MakeAioFile(const FileName: string; Mode: Word): IAioFile;
function MakeAioTcpSocket: IAioTcpSocket; overload;
function MakeAioUdpSocket: IAioUdpSocket;
function MakeAioComPort(const FileName: string): IAioComPort;
function MakeAioNamedPipe(const Name: string): IAioNamedPipe;
function MakeAioConsoleApp(const Cmd: string; const Args: array of const;
  const WorkDir: string = ''): IAioConsoleApplication;
function MakeAioConsole: IAioConsole;
function MakeAioSoundCard(SampPerFreq: LongWord; Channels: LongWord = 1;
  BitsPerSamp: LongWord = 16): IAioSoundCard;

implementation
uses Math, MMSystem, AioImpl;

function MakeAioFile(const FileName: string; Mode: Word): IAioFile;
var
  Impl: TAioFile;
begin
  Impl := TAioFile.Create(FileName, Mode);
  Result := Impl;
end;

function MakeAioTcpSocket: IAioTcpSocket;
var
  Impl: TAioTCPSocket;
begin
  Impl := TAioTCPSocket.Create;
  Result := Impl;
end;

function MakeAioUdpSocket: IAioUdpSocket;
var
  Impl: TAioUDPSocket;
begin
  Impl := TAioUDPSocket.Create;
  Result := Impl;
end;

function MakeAioComPort(const FileName: string): IAioComPort;
var
  Impl: TAioComPort;
begin
  Impl := TAioComPort.Create(FileName);
  Result := Impl;
end;

function MakeAioNamedPipe(const Name: string): IAioNamedPipe;
var
  Impl: TAioNamedPipe;
begin
  Impl := TAioNamedPipe.Create(Name);
  Result := Impl;
end;

function MakeAioConsoleApp(const Cmd: string; const Args: array of const;
  const WorkDir: string = ''): IAioConsoleApplication;
var
  Impl: TAioConsoleApplication;
begin
  Impl := TAioConsoleApplication.Create(Cmd, Args, WorkDir);
  Result := Impl;
end;

function MakeAioConsole: IAioConsole;
var
  Impl: TAioConsole;
begin
  Impl := TAioConsole.Create;
  Result := Impl;
end;

function MakeAioSoundCard(SampPerFreq: LongWord; Channels: LongWord = 1;
  BitsPerSamp: LongWord = 16): IAioSoundCard;
var
  Impl: TAioSoundCard;
begin
  Impl := TAioSoundCard.Create(SampPerFreq, Channels, BitsPerSamp);
  Result := Impl;
end;

{ TAddress }

constructor TAddress.Create(const IP: string; Port: Integer);
begin
  Self.IP := IP;
  Self.Port := Port;
end;

function TAddress.ToString: string;
begin
  Result := Format('%s:%d', [IP, Port])
end;

end.


