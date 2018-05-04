program AsyncChannels;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

type
  TChannel = TChannel<Integer>;

const
  DATA_COUNT = 10;

var
  AsyncChannel: TChannel;
  Producer: TSymmetric<TChannel>;
  Consumer: TSymmetric<TChannel>;

begin
  // create assync channel (non-zero buffer)
  AsyncChannel := TChannel.Make(5);

  // create producer/consumer workers
  Producer := TSymmetric<TChannel>.Spawn(
    procedure(const Chan: TChannel)
    var
      Data: Integer;
    begin
      for Data := 1 to DATA_COUNT do
      begin
        WriteLn(Format('-> Producer: send:%d', [Data]));
        Chan.Write(Data);
        WriteLn(Format('-> Producer: sended:%d', [Data]));
      end;
      WriteLn('-> Producer: close channel');
      Chan.Close;
    end,
    // put channel as argument
    AsyncChannel
  );

  Consumer := TSymmetric<TChannel>.Spawn(
    procedure(const Chan: TChannel)
    var
      Ping: Integer;
    begin
      while Chan.Read(Ping) do
      begin
        WriteLn(Format('<- Consumer: recieved:%d', [Ping]));
      end;
      WriteLn('<- Consumer: channel is closed');
    end,
    // put channel as argument
    AsyncChannel
  );

  // wait until ping-pong is terminated
  Join([Consumer, Producer]);

  Write('Press any key');
  ReadLn
end.
