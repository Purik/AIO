program PingPong1;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

type
  TPingPongChannel = TChannel<Integer>;

const
  PING_PONG_COUNT = 1000;

var
  Channel: TPingPongChannel;
  Pinger: TSymmetric<TPingPongChannel>;
  Ponger: TSymmetric<TPingPongChannel>;

begin
  // create channel for data transferring
  Channel := TPingPongChannel.Make;

  // create ping/pong workers
  Pinger := TSymmetric<TPingPongChannel>.Spawn(
    procedure(const Chan: TPingPongChannel)
    var
      Ping, Pong: Integer;
    begin
      for Ping := 1 to PING_PONG_COUNT do
      begin
        Chan.Write(Ping);
        Chan.Read(Pong);
        Assert(Ping = Pong);
      end;
      Chan.Close;
    end,
    // put channel as argument
    Channel
  );

  Ponger := TSymmetric<TPingPongChannel>.Spawn(
    procedure(const Chan: TPingPongChannel)
    var
      Ping: Integer;
    begin
      while Chan.Read(Ping) do
        Chan.Write(Ping)  // echo ping
    end,
    // put channel as argument
    Channel
  );

  // wait until ping-pong is terminated
  Join([Pinger, Ponger]);

  Write('Press any key');
  ReadLn
end.
