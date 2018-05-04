unit AioTests;

interface
uses
  Greenlets,
  Classes,
  SyncObjs,
  SysUtils,
  AsyncThread,
  GreenletsImpl,
  Generics.Collections,
  Winapi.Windows,
  GInterfaces,
  Aio,
  AioImpl,
  Hub,
  TestFramework;

type

  TTestData = class(TComponent)
  strict private
    FX: Integer;
    FY: Single;
    FZ: string;
    FArr: TBytes;
    procedure ReadStreamParams(Stream: TStream);
    procedure WriteStreamParams(Stream: TStream);
  protected
    procedure DefineProperties(Filer: TFiler); override;
  public
    property Arr: TBytes read FArr write FArr;
    function IsEqual(Other: TTestData): Boolean;
  published
    property X: Integer read FX write FX;
    property Y: Single read FY write FY;
    property Z: string read FZ write FZ;
  end;

  TFakeOSProvider = class(TAioProvider)
  strict private
    FStream: TMemoryStream;
  public
    constructor Create;
    destructor Destroy; override;
    function  Write(Buf: Pointer; Len: Integer): LongWord; override;
    function  Read(Buf: Pointer; Len: Integer): LongWord; override;
    property Stream: TMemoryStream read FStream;
    procedure Clear;
  end;

  tArrayOfString = array of string;

  TAioTests = class(TTestCase)
  private
    FReadData: AnsiString;
    FDataSz: Integer;
    FAioList, FFSList: TList<string>;
    FCliOutput: TStrings;
    FServOutput: TStrings;
    FOutput: TStrings;
    procedure GWriteFile(const A: array of const);
    procedure GReadFile(const A: array of const);
    procedure RandomPosWrite(const A: array of const);
    procedure SeekAndWrite(const A: array of const);
    procedure SeekAndRead(const A: array of const);
    function  ReadAStrFromFile(const FName: string): AnsiString;
    procedure WriteAToFile(const FName: string; const S: AnsiString);
    procedure RunAsync(const Routine: TSymmetricArgsRoutine; const A: array of const);
    procedure ReadWriteByStream(const A: array of const);
    procedure ReadComp(const A: array of const);
    procedure WriteComp(const A: array of const);
    procedure EchoCliRoutine(const A: array of const);
    procedure EchoTCPServRoutine;
    procedure TCPSockEventsRoutine(const A: array of const);
    procedure TcpWriter(const A: array of const);
    procedure TcpReader(const A: array of const);
    procedure NamedPipeEchoClient(const PipeName: string);
    //
    procedure ReadThreaded(const S: IAioTcpSocket; const Log: tArrayOfString);
    procedure WriteThreaded(const S: IAioTcpSocket; const Data: TStrings; const SendTimeout: Integer);
    //
    procedure TcpStressClient(const Count: Integer;
      const Port: Integer; const Index: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;

    // soundcard (temporary hide this test)
    procedure SoundCard;
  published
    procedure CreateAioFile;
    procedure WriteAioFile;
    procedure ReadAioFile;
    procedure CompareAioFileAndStdFStream;
    procedure ReadWriteComponent;
    // tcp
    procedure AioSocksCreateDestroy;
    procedure AioTCPServerRunStop;
    procedure AioProvFormatter;
    procedure MBCSEncMemLeak;
    procedure AioTCPConn;
    procedure AioTCPConnNonRoot;
    procedure AioTCPConnFalse;
    procedure AioTCPConnFalseNonRoot;
    procedure AioTCPConDisconn;
    procedure AioTCPSocketEvents;
    procedure AioTCPSocketConnect;
    procedure AioTCPReaderWriter;
    procedure AioTcpStress;
    // aio потокобезопасны
    procedure ReadWriteMultithreaded;
    // udp
    procedure AioUdpRoundBobin;
    // named pipes
    procedure CreateNamedPipe;
    procedure NamedPipePingPong;
    // console applications
    procedure ConsoleApp;
    procedure Console;
  end;

implementation


{ TAioTests }

procedure TAioTests.AioProvFormatter;
var
  Prov: TFakeOSProvider;
  B: Byte;
  Bytes: TBytes;
  Int, Ps: Integer;
  Utf8DataExpected, Utf8Terminator: string;
  S, Tmp: string;
  List: TStringList;
  ExceptionClass: TClass;
begin
  Prov := TFakeOSProvider.Create;
  try
    // 1
    SetLength(Bytes, 3);
    Bytes[0] := 0; Bytes[1] := 1; Bytes[2] := 2;
    Prov.Clear;
    Prov.WriteBytes(Bytes);
    Prov.Stream.Position := 0;
    SetLength(Bytes, 0);
    Prov.ReadBytes(Bytes);
    Check(Length(Bytes) = 3);
    Check(Bytes[0] = 0); Check(Bytes[1] = 1); Check(Bytes[2] = 2);
    // 2
    Prov.Clear;
    Prov.WriteString(TEncoding.ASCII, '1234567890');
    Prov.Stream.Position := 0;
    Prov.ReadString(TEncoding.ASCII, S);
    Check(S = '1234567890');
    // 3
    Prov.Clear;
    Prov.WriteString(TEncoding.ASCII, '0987654321', 'xyz');
    Prov.Stream.Position := 0;
    Prov.ReadString(TEncoding.ASCII, S, 'xyz');
    Check(S = '0987654321');
    // 4
    Prov.Clear;
    Prov.WriteByte(253);
    Prov.Stream.Position := 0;
    Prov.ReadByte(B);
    Check(B = 253);
    // 5
    Prov.Clear;
    Prov.WriteInteger(1986);
    Prov.Stream.Position := 0;
    Prov.ReadInteger(Int);
    Check(Int = 1986);
    // 6
    Utf8DataExpected := 'тестовая строка ла-ла-ла';
    Utf8Terminator := 'конец*';
    Prov.Clear;
    Prov.WriteString(TEncoding.UTF8, Utf8DataExpected, Utf8Terminator);
    Prov.WriteString(TEncoding.UTF8, 'advanced', '');
    Prov.Stream.Position := 0;
    Check(Prov.ReadString(TEncoding.UTF8, S, Utf8Terminator));
    Check(S = Utf8DataExpected);
    CheckFalse(Prov.ReadString(TEncoding.UTF8, S, Utf8Terminator));
    // 7
    Prov.Clear;
    Prov.WriteString(TEncoding.Unicode, 'testxyz_suffix', 'xyz');
    Prov.Stream.Position := 0;
    Check(Prov.ReadString(TEncoding.Unicode, S, 'xyz'));
    Check(S = 'test');
    // 8
    List := TStringList.Create;
    try
      Prov.Clear;
      Prov.WriteLn('msg1');
      Prov.WriteLn('msg2');
      Prov.WriteLn('msg3');
      for S in Prov.ReadLns do begin
        List.Add(S);
      end;
      Check(List.CommaText = '');
      Prov.Stream.Position := 0;
      for S in Prov.ReadLns do begin
        List.Add(S);
      end;
      Check(List.CommaText = 'msg1,msg2,msg3');
    finally
      List.Free;
    end;
    // 9
    Prov.Clear;
    S := 'hallo' + Prov.GetEOL;
    Bytes := Prov.GetEncoding.GetBytes(S);
    for Int := 0 to High(Bytes) do begin
      B := Bytes[Int];
      Prov.WriteByte(B);
      Prov.Stream.Position := Prov.Stream.Position - 1;
      try
        Tmp := Prov.ReadLn;
      except
        Tmp := '';
      end;
      if Int < High(Bytes) then
        Check(Tmp = '')
      else
        Check(Tmp = 'hallo');
    end;
    Ps := Prov.Stream.Position;
    Prov.WriteLn('world');
    Prov.Stream.Position := Ps;
    S := Prov.ReadLn;
    Check(S = 'world');
    Check(Prov.Stream.Position = Prov.Stream.Size);
    // 10
    Prov.Clear;
    Prov.WriteLn('Delphi <a href="tdlite.exe">download</a> ');
    Prov.Stream.Position := 0;
    Check(Prov.ReadRegEx('href="(.*?)"', S));
    // 11
    List := TStringList.Create;
    try
      Prov.Clear;
      Prov.WriteLn('<msg1> trash...');
      Prov.WriteLn('<msg2> lololo');
      Prov.WriteLn('<msg3 bla-bla-bla');
      Prov.Stream.Position := 0;
      for S in Prov.ReadRegEx('<.*>') do
        List.Add(S);
      Check(List.CommaText = '<msg1>,<msg2>');
    finally
      List.Free;
    end;
    // 12
    Prov.Clear;
    Prov.WriteLn('1');
    Prov.WriteLn('');
    Prov.WriteLn('');
    Prov.Stream.Position := 0;
    S := Prov.ReadLn;
    Check(S = '1');
    S := Prov.ReadLn;
    Check(S = '');
    S := Prov.ReadLn;
    Check(S = '');
    ExceptionClass := nil;
    try
      Prov.ReadLn;
    except
      on E: TAioProvider.AEOF do begin
        ExceptionClass := TAioProvider.AEOF
      end;
    end;
    Check(ExceptionClass = TAioProvider.AEOF, 'EOF error');
  finally
    Prov.Free
  end;
end;

procedure TAioTests.RandomPosWrite(const A: array of const);
var
  F: IAioFile;
  FileName, Chunk: AnsiString;
begin
  FileName := A[0].AsAnsiString;
  Chunk := A[1].AsAnsiString;
  F := MakeAioFile(string(FileName), fmCreate);
  try
    F.Write(Pointer(Chunk), Length(Chunk));
    F.Write(Pointer(Chunk), Length(Chunk));
    F.SetPosition(F.GetPosition - 3);
    F.Write(Pointer(Chunk), Length(Chunk));
  finally
    //F.Free;
  end;
end;

procedure TAioTests.AioTCPConDisconn;
const
  cTestMsg = 'test message';
var
  Server: TGreenlet;
  S: IAioTCPSocket;
  Str: string;
begin
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  S := MakeAioTcpSocket;
  S.SetEncoding(TEncoding.ANSI);
  Check(S.Connect('localhost', 1986, INFINITE));

  S.WriteLn(cTestMsg);
  Str := S.ReadLn;


  FCliOutput.Add(string(Str));

  Check(FServOutput[0] = 'listen');
  Check(FServOutput[1] = 'listen');
  Check(FCliOutput[0] = cTestMsg);
  Check(FCliOutput[1] = cTestMsg);

  S.Disconnect;
  GreenSleep(100);

  Check(FCliOutput.Count >= 3);
  Check(FCliOutput[2] = 'cli disconnect');

  FServOutput.Clear;
  Check(S.Connect('localhost', 1986, 1000));
  GreenSleep(100);
  Check(FServOutput.Count > 0);
  Check(FServOutput[0] = 'listen');

end;

procedure TAioTests.AioTCPConn;
var
  Server: TGreenlet;
  S: IAioTCPSocket;
begin
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  S := MakeAioTcpSocket;
  Check(S.Connect('127.0.0.1', 1986, 1000));
  // дадим серверному сокету отработать disconnect
  GreenSleep(500);
end;

procedure TAioTests.AioTCPConnFalse;
var
  Server: TGreenlet;
  S: IAioTCPSocket;
begin
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  S := MakeAioTcpSocket;
  CheckFalse(S.Connect('localhost', 1987, 500));
end;

procedure TAioTests.AioTCPConnFalseNonRoot;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(AioTCPConnFalse);
  try
    G.Join
  finally
  end;
end;

procedure TAioTests.AioTCPConnNonRoot;
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(AioTCPConn);
  try
    G.Join
  finally
  end;
end;

procedure TAioTests.AioTCPReaderWriter;
var
  Server, R, W: IRawGreenlet;
  S: IAioTCPSocket;
begin
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  S := MakeAioTcpSocket;
  S.SetEncoding(TEncoding.ASCII);
  R := TGreenlet.Create(TcpReader, [S]);
  Check(S.Connect('localhost', 1986, 500), 'connection timeout');
  R.Switch;
  W := TGreenlet.Create(TcpWriter, [S, 'first', 'second', 'third']);
  W.Join;
  // дадим ридеру поработать
  GreenSleep(300);
  CheckEqualsString('first,second,third', FOutput.CommaText);
end;

procedure TAioTests.AioSocksCreateDestroy;
var
  TCP: IAioTCPSocket;
  UDP: IAioUDPSocket;
begin
  TCP := MakeAioTcpSocket;
  TCP := nil;
  UDP := MakeAioUdpSocket;
  UDP := nil;
end;

procedure TAioTests.AioTCPServerRunStop;
var
  Server: TGreenlet;
begin
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  Join([Server], 100)
end;

procedure TAioTests.AioTCPSocketConnect;
var
  Sock: IAioTCPSocket;
  A: string;
begin
  Sock := MakeAioTcpSocket;
  Check(Sock.Connect('uranus.dfpost.ru', 80, 1000), 'connection timeout');

  Sock.SetEncoding(TEncoding.ANSI);
  Sock.SetEOL(LF);
  Sock.WriteLn('GET /');
  A := Sock.ReadLn;

  Check(Sock.Read(nil, 0) > 0);
  Check(A <> '');
end;

procedure TAioTests.AioTCPSocketEvents;
var
  C: IAioTCPSocket;
  Server, Events: TGreenlet;
begin
  C := MakeAioTcpSocket;
  Server := TGreenlet.Spawn(EchoTCPServRoutine);
  Events := TGreenlet.Spawn(TCPSockEventsRoutine, [C]);
  Check(C.Connect('localhost', 1986, 1000));
  GreenSleep(100);
  Check(FOutput.Count = 1);
  Check(FOutput[0] = '0');
  FOutput.Clear;
  C.Disconnect;
  GreenSleep(100);
  Check(FOutput.Count > 0);
  Check(FOutput[0] = '1');
  Check(FCliOutput.Count = 1);
  Check(FCliOutput[0] = 'cli disconnect');
end;


procedure TAioTests.AioTcpStress;
const
  CLI_COUNT = 50;
  STRESS_FACTOR = 100;
var
  Server: IRawGreenlet;
  Clients: TGreenGroup<Integer>;
  I: Integer;
begin
  Server := TSymmetric.Spawn(EchoTCPServRoutine);
  for I := 1 to CLI_COUNT do begin
    Clients[I] := TSymmetric<Integer, Integer, Integer>.Spawn(TcpStressClient, STRESS_FACTOR, 1986, I);
  end;
  Check(Clients.Join, 'Clients.Join');
end;

procedure TAioTests.AioUdpRoundBobin;
var
  S1, S2: IAioUDPSocket;
  G1: IRawGreenlet;
  Str: string;
begin
 
  S1 := MakeAioUdpSocket;
  S1.Bind('0.0.0.0', 1986);
  G1 := TGreenlet.Spawn(EchoCliRoutine, [S1]);

  S2 := MakeAioUdpSocket;
  S2.SetRemoteAddress(TAddress.Create('localhost', 1986));
  S2.WriteLn('hallo1');
  Str := S2.ReadLn;
  CheckEquals('hallo1', Str);

  S2.WriteLn('hallo2');
  Str := S2.ReadLn;
  CheckEquals('hallo2', Str);

end;

procedure TAioTests.CompareAioFileAndStdFStream;
const
  cFileName = 'aio_fs_test.txt';
  cEtalon1 = 'chunk_chuchunk_';
  cEtalon2_1 = '0_1_2_3_4_5_6_7_8_9';
  cEtalon2_2 = '0_1x2_x_4x5_x_7x8_x';
  cEtalon3_1 = '123456789';
  cEtalon3_2 = '6789';
  cTestSequence = '123456789';
var
  Test: AnsiString;
  S: TStream;
  AioFile: IAioFile;
  I: Integer;
begin
  FAioList := TList<string>.Create;
  FFSList := TList<string>.Create;
  try
    // test 1
    RunAsync(RandomPosWrite, [cFileName, 'chunk_']);
    Test := ReadAStrFromFile(cFileName);
    Check(Test = cEtalon1, 'test 1 problem');
    // test 2
    WriteAToFile(cFileName, cEtalon2_1);
    RunAsync(SeekAndWrite, [cFileName]);
    Test := ReadAStrFromFile(cFileName);
    Check(Test = cEtalon2_2, 'test 2 problem');
    // test 3
    WriteAToFile(cFileName, cEtalon3_1);
    RunAsync(SeekAndRead, [cFileName, 5]);
    Check(FReadData = cEtalon3_2);
    Check(FDataSz = 4);
    // big megatest
    S := TFileStream.Create(cFileName, fmCreate);
    RunAsync(ReadWriteByStream, [S, FFSList, cTestSequence]);
    S.Free;
    AioFile := MakeAioFile(cFileName, fmCreate);
    S := AioFile.AsStream;
    RunAsync(ReadWriteByStream, [S, FAioList, cTestSequence]);
    AioFile := nil;
    Check(FFSList.Count = FAioList.Count);
    for I := 0 to FFSList.Count-1 do begin
      Check(FFSList[I] = FAioList[I], Format('megacheck error on %d iteration', [I]));
    end
  finally
    DeleteFile(cFileName);
    FAioList.Free;
    FFSList.Free;
  end;
end;

procedure TAioTests.Console;
var
  Console: IAioConsole;
begin
  Console := MakeAioConsole;
  Check(Console.StdIn <> nil);
  Check(Console.StdOut <> nil);
  Check(Console.StdError <> nil);
end;

procedure TAioTests.ConsoleApp;
var
  App: IAioConsoleApplication;
  Str: string;
  Cnt: Integer;
  Encoding: TEncoding;
begin
  Encoding := TEncoding.ANSI.GetEncoding(866);
  try
    App := MakeAioConsoleApp('cmd', []);
    App.SetEncoding(Encoding);
    for Str in App.StdOut.ReadLns([CRLF, '>']) do begin
      if Str = '' then
        Break;
      FOutput.Add(Str)
    end;
    Check(FOutput.Count > 0);
    FOutput.Clear;
    App.StdIn.WriteLn('help');
    Cnt := 0;
    for Str in App.StdOut.ReadLns do begin
      FOutput.Add(Str);
      Inc(Cnt);
      if Cnt > 5 then
        Break;
    end;
    Check(FOutput.Count > 0);
    App.Terminate(-123);
    Check(App.GetExitCode = -123)
  finally
    Encoding.Free
  end;
end;

procedure TAioTests.CreateAioFile;
const
  cFileName = 'AioCreateTest.txt';
var
  F: IAioFile;
  FS: TFileStream;
begin
  DeleteFile(cFileName);
  F := MakeAioFile(cFileName, fmCreate);
  Check(FileExists(cFileName));
  F := nil;

  FS := TFileStream.Create(cFileName, fmOpenRead);
  try
    Check(FS.Size = 0)
  finally
    FS.Free;
  end;

  try
    Check(FileExists(cFileName));
  finally
    DeleteFile(cFileName)
  end;

end;


procedure TAioTests.CreateNamedPipe;
var
  Pipe: IAioNamedPipe;
begin
  Pipe := MakeAioNamedPipe('test');
  Pipe.SetEncoding(TEncoding.ANSI);
  Pipe.MakeServer;
  TSymmetric<string>.Spawn(NamedPipeEchoClient, 'test');
  Pipe.WaitConnection;
  Pipe.WriteLn('hallo');
  GreenSleep(100);
  Check(FCliOutput.CommaText = 'hallo');
end;

procedure TAioTests.EchoCliRoutine(const A: array of const);
var
  Sock: IAioProvider;
  Msg: string;
begin
  Sock := A[0].AsInterface as IAioProvider;
  Sock.SetEncoding(TEncoding.ASCII);
  try
    while Sock.ReadLn(Msg) do begin
      FCliOutput.Add(Msg);
      Sock.WriteLn(Msg);
    end;
  finally
    FCliOutput.Add('cli disconnect')
  end;
end;

procedure TAioTests.EchoTCPServRoutine;
var
  S, C: IAioTCPSocket;
  Clients: TGreenGroup<Integer>;
begin
  S := MakeAioTcpSocket;
  S.Bind('localhost', 1986);
  while True do begin
    FServOutput.Add('listen');
    S.Listen;
    C := S.Accept;
    Clients[Clients.Count] := TGreenlet.Spawn(EchoCliRoutine, [C])
  end;
end;

procedure TAioTests.WriteAioFile;
const
  cChars: AnsiString = 'test_data_for_write_';
var
  F: IAioFile;
  G: IRawGreenlet;
  FName: string;
  Rand: Int64;
  Enthropy: Double;
  I, Iter: Integer;
  vReadData, TestData: AnsiString;
  FS: TFileStream;
begin
  SetLength(TestData, 1024*100);
  Iter := 0;
  for I := 1 to High(TestData) do begin
    TestData[I] := cChars[Iter+1];
    Iter := (Iter + 1) mod Length(cChars);
  end;
  Enthropy := Now;
  Move(Enthropy, Rand, SizeOf(Rand));
  FName := Format('TestWriteFile%d.txt', [Rand and $FFFF]);
  F := MakeAioFile(FName, fmCreate);
  G := TGreenlet.Spawn(GWriteFile, [F, TestData]);
  try
    G.Join
  finally
    F := nil
  end;

  FS := TFileStream.Create(FName, fmOpenRead);
  with FS do try
    SetLength(vReadData, Length(TestData));
    ReadData(Pointer(vReadData), Length(vReadData));
    Check(vReadData = TestData, 'write test data broked after read');
    Check(FDataSz = Length(TestData), 'Returned datasize problems');
  finally
    Free;
    DeleteFile(PChar(FName));
  end;
end;

procedure TAioTests.WriteAToFile(const FName: string; const S: AnsiString);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FName, fmCreate);
  try
    FS.Write(Pointer(S)^, Length(S));
  finally
    FS.Free;
  end;
end;

procedure TAioTests.WriteComp(const A: array of const);
var
  S: TStream;
  Comp: TComponent;
begin
  S := TStream(A[0].AsObject);
  Comp := TComponent(A[1].AsObject);
  S.WriteComponent(Comp)
end;

procedure TAioTests.WriteThreaded(const S: IAioTcpSocket; const Data: TStrings; const SendTimeout: Integer);
var
  I: Integer;
begin
  BeginThread;
  for I := 0 to Data.Count-1 do begin
    S.WriteLn(Data[I]);
    GreenSleep(SendTimeout);
  end;
  EndThread;
end;

procedure TAioTests.GReadFile(const A: array of const);
var
  F: IAioFile;
  Sz: Integer;
begin
  F := A[0].AsInterface as IAioFile;
  Sz := A[1].AsInteger;
  SetLength(FReadData, Sz);
  FDataSz := F.Read(Pointer(FReadData), Sz);
end;

procedure TAioTests.GWriteFile(const A: array of const);
var
  F: IAioFile;
  S: AnsiString;
begin
  F := A[0].AsInterface as IAioFile;
  S := AnsiString(A[1].AsAnsiString);
  FDataSz := F.Write(Pointer(S), Length(S));
end;

procedure TAioTests.MBCSEncMemLeak;
var
  Prov: TFakeOSProvider;
  Encoding: TEncoding;
begin
  Encoding := TEncoding.ANSI.GetEncoding(1201);
  try
    Prov := TFakeOSProvider.Create;
    try
      Prov.SetEncoding(Encoding);
      Prov.WriteLn('message1');
      Prov.WriteLn('message2');
      Prov.Stream.Position := 0;
      CheckEquals('message1', Prov.ReadLn);
      CheckEquals('message2', Prov.ReadLn);
    finally
      Prov.Free
    end;
  finally
    Encoding.Free
  end;
end;

procedure TAioTests.NamedPipeEchoClient(const PipeName: string);
var
  Pipe: IAioNamedPipe;
  Msg: string;
begin
  GreenSleep(100);
  Pipe := MakeAioNamedPipe(PipeName);
  Pipe.SetEncoding(TEncoding.ANSI);
  try
    Pipe.Open;
    while  Pipe.ReadLn(Msg) do begin
      FCliOutput.Add(Msg);
      Pipe.WriteLn(Msg);
    end;
  finally
    FCliOutput.Add('cli disconnect')
  end;
end;

procedure TAioTests.NamedPipePingPong;
const
  PIPE_NAME = 'test_server';
var
  Pipe: IAioNamedPipe;
  Msg: string;
begin
  Pipe := MakeAioNamedPipe(PIPE_NAME);
  Pipe.SetEncoding(TEncoding.ANSI);
  Pipe.MakeServer;
  TSymmetric<string>.Spawn(NamedPipeEchoClient, PIPE_NAME);
  Pipe.WaitConnection;

  Pipe.WriteLn('message1');
  Check(Pipe.ReadLn(Msg));
  Check(Msg = 'message1');
  Pipe.WriteLn('message2');
  Check(Pipe.ReadLn(Msg));
  Check(Msg = 'message2');
  Pipe.WriteLn('message3');
  Check(Pipe.ReadLn(Msg));
  Check(Msg = 'message3');
end;

procedure TAioTests.ReadAioFile;
var
  Rand: Int64;
  Enthropy: Double;
  FName: string;
  F: IAioFile;
  G: IRawGreenlet;
  TestData: AnsiString;
  FS: TFileStream;
begin
  Enthropy := Now;
  Move(Enthropy, Rand, SizeOf(Rand));
  FName := Format('TestReadFile%d.txt', [Rand and $FFFF]);
  TestData := 'test_read_data_';

  FS := TFileStream.Create(FName, fmCreate);
  with FS do try
    Write(Pointer(TestData)^, Length(TestData));
  finally
    Free;
  end;
  
  F := MakeAioFile(FName, fmOpenRead);
  G := TGreenlet.Spawn(GReadFile, [F, Length(TestData)]);
  try
    G.Join;
    Check(FReadData = TestData, 'Test data broked on reading');
    Check(FDataSz = Length(TestData), 'Returned datasize problems');
  finally
    F := nil;
    DeleteFile(PChar(FName));
  end;
end;

function TAioTests.ReadAStrFromFile(const FName: string): AnsiString;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FName, fmOpenRead);
  try
    SetLength(Result, FS.Seek(0, soFromEnd));
    FS.Position := 0;
    FS.Read(Pointer(Result)^, Length(Result));
  finally
    FS.Free;
  end;
end;

procedure TAioTests.ReadComp(const A: array of const);
var
  S: TStream;
  Comp: TComponent;
begin
  S := TStream(A[0].AsObject);
  Comp := TComponent(A[1].AsObject);
  S.ReadComponent(Comp)
end;

procedure TAioTests.ReadThreaded(const S: IAioTcpSocket; const Log: tArrayOfString);
var
  Msg: string;
  Cnt: Integer;
begin
  BeginThread;
  Cnt := 0;
  while S.ReadLn(Msg) do begin
    //Log.Add(Msg);
    Log[Cnt] := Msg;
    Inc(Cnt);
  end;
  EndThread;
end;

procedure TAioTests.ReadWriteByStream(const A: array of const);
var
  Stream: TStream;
  List: TList<string>;
  Chunk, Readed: AnsiString;

  procedure ReadAndAddToList;
  var
    ReadLen: Integer;
  begin
    ReadLen := Stream.Read(Pointer(Readed)^, Length(Readed));
    List.Add(Copy(string(Readed), 1, ReadLen));
  end;

begin
  Stream := TStream(A[0].AsObject);
  List := TList<string>(A[1].AsObject);
  Chunk := A[2].AsAnsiString;
  SetLength(Readed, Length(Chunk)*10);
  Stream.Write(Pointer(Chunk)^, Length(Chunk));
  Stream.Write(Pointer(Chunk)^, Length(Chunk));
  Stream.Seek(Length(Chunk) div 2 + 1, soFromBeginning);
  // 1
  ReadAndAddToList;
  Stream.Seek(-(Length(Chunk) div 3), soFromCurrent);
  // 2
  ReadAndAddToList;

  Stream.Write(Pointer(Chunk)^, Length(Chunk));
  Stream.Position := 3;
  // 3
  ReadAndAddToList;

  Stream.Seek(-5, soFromCurrent);
  // 4
  ReadAndAddToList;

  Stream.Seek(5, soFromEnd);
  // 5
  ReadAndAddToList;

  Stream.Seek(-5, soFromEnd);
  // 6
  ReadAndAddToList;
  Stream.Position := Length(Chunk) div 2;
  // 7
  ReadAndAddToList;
  Stream.Position := -1000;
  // 8
  ReadAndAddToList;
  //9
  Stream.Position := 1000;
  ReadAndAddToList;
  //10
  Stream.Seek(-1000, soFromCurrent);
  ReadAndAddToList;
  //10
  Stream.Seek(1000, soFromCurrent);
  ReadAndAddToList;
  //11
  Stream.Seek(1000, soFromBeginning);
  ReadAndAddToList;
  //12
  Stream.Seek(1, soFromBeginning);
  ReadAndAddToList;
  //13
  Stream.Seek(100, soFromEnd);
  ReadAndAddToList;
  //14
  Stream.Seek(-100, soFromEnd);
  ReadAndAddToList;
  //15
  Stream.Seek(2, soFromBeginning);
  Stream.Seek(3, soFromCurrent);
  Stream.Seek(-1, soFromCurrent);
  Stream.Seek(10, soFromCurrent);
  ReadAndAddToList;
end;

procedure TAioTests.ReadWriteComponent;
const
  cTestFile = 'read_write_comp.bin';
var
  F: IAioFile;
  FS: TFileStream;
  Etalon, Test: TTestData;
  I: Integer;
  Arr: TBytes;
  FileSz: Integer;
begin
  Etalon := TTestData.Create(nil);
  Etalon.X := 123;
  Etalon.Y := 432.654;
  Etalon.Z := 'test_string';
  SetLength(Arr, 100);
  for I := 0 to High(Arr) do
    Arr[I] := I;
  Etalon.Arr := Arr;

  try
    // read component
    FS := TFileStream.Create(cTestFile, fmCreate);
    try
      FS.WriteComponent(Etalon);
      FileSz := FS.Size;
    finally
      FS.Free;
    end;
    F := MakeAioFile(cTestFile, fmOpenRead);
    Test := TTestData.Create(nil);
    try
      F.AsStream.ReadComponent(Test);
      Check(F.AsStream.Size = FileSz, 'filesize');
      F.Seek(0, soBeginning);
      RunAsync(ReadComp, [F.AsStream, Test]);
    finally
      F := nil
    end;
    try
      Check(Test.IsEqual(Etalon), 'reading component problems');
    finally
      Test.Free;
    end;
    // write component
    F := MakeAioFile(cTestFile, fmCreate);
    try
      RunAsync(WriteComp, [F.AsStream, Etalon]);
      F.AsStream.WriteComponent(Etalon);
    finally
      F := nil
    end;
    Test := TTestData.Create(nil);
    FS := TFileStream.Create(cTestFile, fmOpenRead);
    try
      FS.ReadComponent(Test);
    finally
      FS.Free;
    end;
    try
      Check(Test.IsEqual(Etalon), 'writing component problems')
    finally
      Test.Free
    end;
  finally
    Etalon.Free;
    DeleteFile(cTestFile)
  end;
end;

procedure TAioTests.ReadWriteMultithreaded;
const
  SND_TIMEOUT = 300;
var
  Server: TGreenlet;
  Sock: IAioTCPSocket;
  Reader: TSymmetric<IAioTcpSocket, tArrayOfString>;
  Writer: TSymmetric<IAioTcpSocket, TStrings, Integer>;
  Data, Tmp: TStrings;
  Log: tArrayOfString;
  I: Integer;
begin
  Data := TStringList.Create;
  Tmp := TStringList.Create;
  Sock := MakeAioTcpSocket;
  try
    Server := TGreenlet.Spawn(EchoTCPServRoutine);
    Check(Sock.Connect('localhost', 1986, 1000));
    for I := 1 to 3 do
      Data.Add(Format('message%d', [I]));
    SetLength(Log, Data.Count);
    Reader := TSymmetric<IAioTcpSocket, tArrayOfString>.Spawn(ReadThreaded, Sock, Log);
    Writer := TSymmetric<IAioTcpSocket, TStrings, Integer>.Spawn(WriteThreaded, Sock, Data, SND_TIMEOUT);
    Join([Server, Reader, Writer], SND_TIMEOUT * Data.Count * 2);
    for I := 0 to High(Log) do
      Tmp.Add(Log[I]);
    CheckEquals(Data.CommaText, Tmp.CommaText);
  finally
    Data.Free;
    Tmp.Free;
  end;
end;

procedure TAioTests.RunAsync(const Routine: TSymmetricArgsRoutine;
  const A: array of const);
var
  G: IRawGreenlet;
begin
  G := TGreenlet.Spawn(Routine, A);
  try
    G.Join
  finally
  end;
end;

procedure TAioTests.SeekAndRead(const A: array of const);
var
  F: IAioFile;
  SeekPos: Integer;
begin
  F := MakeAioFile(A[0].AsString, fmOpenReadWrite);
  SeekPos := A[1].AsInteger;
  SetLength(FReadData, F.Seek(0, soEnd) - SeekPos + 1);
  F.Seek(SeekPos, soBeginning);
  FDataSz := F.Read(Pointer(FReadData), Length(FReadData))
end;

procedure TAioTests.SeekAndWrite(const A: array of const);
var
  F: IAioFile;
  CurPos, Sz: Int64;
begin
  F := MakeAioFile(A[0].AsString, fmOpenReadWrite);
  F.Seek(0, soEnd);
  Sz := F.GetPosition+1;
  F.Seek(0, soBeginning);
  CurPos := 3;
  F.SetPosition(CurPos);
  while F.GetPosition < Sz do begin
    F.WriteString(TEncoding.ANSI, 'x', '');
    F.SetPosition(F.GetPosition + 2)
  end;
end;

procedure TAioTests.SetUp;
begin
  inherited;
  JoinAll(0);
  FCliOutput := TStringList.Create;
  FServOutput := TStringList.Create;
  FOutput := TStringList.Create;
  {$IFDEF DEBUG}
  GreenletCounter := 0;
  GeventCounter := 0;
  IOEventTupleCounter := 0;
  IOFdTupleCounter := 0;
  IOTimeTupleCounter := 0;
  {$ENDIF}
end;

procedure TAioTests.SoundCard;
var
  SC: IAioSoundCard;
  Buffer: array of SmallInt;
  Readed, Writed, I: LongWord;
  NonZero: Boolean;
begin
  SC := MakeAioSoundCard(16000);
  SetLength(Buffer, 16000);
  Readed := SC.Read(@Buffer[0], Length(Buffer)*SizeOf(SmallInt));
  Check(Readed = 16000*SizeOf(SmallInt));
  NonZero := False;
  for I := 0 to High(Buffer) do
    if Buffer[I] <> 0 then begin
      NonZero := True;
      Break;
    end;
  Writed := SC.Write(@Buffer[0], Readed);
  CheckEquals(Readed, Writed);
end;

procedure TAioTests.TcpReader(const A: array of const);
var
  S: IAioTCPSocket;
  Str: string;
begin
  S := A[0].AsInterface as IAioTcpSocket;
  while S.ReadLn(Str) do begin
    FOutput.Add(Str)
  end;
end;

procedure TAioTests.TCPSockEventsRoutine(const A: array of const);
var
  S: IAioTCPSocket;
  Index: Integer;
begin
  S := A[0].AsInterface as IAioTcpSocket;
  while True do begin
    if S.OnDisconnect.WaitFor(0) = wrSignaled then
      Select([S.OnConnect], Index)
    else
      Select([S.OnConnect, S.OnDisconnect], Index);
    FOutput.Add(IntToStr(Index))
  end;
end;

procedure TAioTests.TcpStressClient(const Count: Integer;
  const Port: Integer; const Index: Integer);
var
  Actual, Expected: string;
  I: Integer;
  Sock: IAioTcpSocket;
begin
  Sock := MakeAioTcpSocket;
  Check(Sock.Connect('localhost', Port, 1000), 'conn timeout for ' + IntToStr(Index));
  DebugString(Format('Connected socket[%d]', [Index]));
  for I := 1 to Count do begin
    Expected := Format('message[%d][%d]', [Index, I]);
    Sock.WriteLn(Expected);
    Actual := Sock.ReadLn;
    CheckEquals(Expected, Actual);
  end;
end;

procedure TAioTests.TcpWriter(const A: array of const);
var
  S: IAioTCPSocket;
  I: Integer;
begin
  S := A[0].AsInterface as IAioTcpSocket;
  for I := 1 to High(A) do
    S.WriteString(TEncoding.ANSI, A[I].AsString);
end;

procedure TAioTests.TearDown;
begin
  inherited;
  FCliOutput.Free;
  FServOutput.Free;
  FOutput.Free;
  {$IFDEF DEBUG}
  // некоторые тесты привоят к вызову DoSomethingLater
  DefHub.Serve(0);
  Check(GreenletCounter = 0, 'GreenletCore.RefCount problems');
  Check(GeventCounter = 0, 'Gevent.RefCount problems');
  JoinAll;
  Check(IOEventTupleCounter = 0, 'IOEventTupleCounter problems');
  Check(IOFdTupleCounter = 0, 'IOFdTupleCounter problems');
  Check(IOTimeTupleCounter = 0, 'IOTimeTupleCounter problems');
  {$ENDIF}
end;

{ TTestData }

procedure TTestData.DefineProperties(Filer: TFiler);
begin
  inherited;
  Filer.DefineBinaryProperty('StreamProps', ReadStreamParams,
    WriteStreamParams, True);
end;

function TTestData.IsEqual(Other: TTestData): Boolean;
var
  I: Integer;
begin
  Result := (Self.FX = Other.FX) and (Self.FY = Other.FY)
    and (Self.FZ = Other.FZ) and (Length(Self.FArr) = Length(Other.FArr));
  if Result then begin
    for I := 0 to High(Self.FArr) do
      if Self.FArr[I] <> Other.FArr[I] then
        Exit(False);
  end;
end;

procedure TTestData.ReadStreamParams(Stream: TStream);
var
  Sz: Integer;
begin
  Stream.Read(Sz, SizeOf(Sz));
  SetLength(FArr, Sz);
  Stream.Read(FArr[0], Sz);
end;

procedure TTestData.WriteStreamParams(Stream: TStream);
var
  Sz: Integer;
begin
  Sz := Length(FArr);
  Stream.Write(Sz, SizeOf(Sz));
  Stream.Write(FArr[0], Sz)
end;

{ TFakeOSProvider }

procedure TFakeOSProvider.Clear;
begin
  FStream.Clear;
  SetLength(FInternalBuf, 0);
end;

constructor TFakeOSProvider.Create;
begin
  inherited;
  FStream := TMemoryStream.Create
end;

destructor TFakeOSProvider.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TFakeOSProvider.Read(Buf: Pointer; Len: Integer): LongWord;
begin
  if Len = 0 then
    Exit(FStream.Size);
  Result := FStream.Read(Buf^, Abs(Len));
end;

function TFakeOSProvider.Write(Buf: Pointer; Len: Integer): LongWord;
begin
  Result := FStream.Write(Buf^, Len);
end;

initialization
  RegisterTest('AioTests', TAioTests.Suite);

end.
