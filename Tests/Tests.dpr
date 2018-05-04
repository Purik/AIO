program Tests;
{

  Delphi DUnit Test Project
  -------------------------
  This project contains the DUnit test framework and the GUI/Console test runners.
  Add "CONSOLE_TESTRUNNER" to the conditional defines entry in the project options
  to use the console test runner.  Otherwise the GUI test runner will be used by
  default.

}

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  Windows,
  DUnitTestRunner,
  Boost in '..\Boost.pas',
  Hub in '..\Hub.pas',
  Greenlets in '..\Greenlets.pas',
  Gevent in '..\Gevent.pas',
  HubTests in 'HubTests.pas',
  GreenletTests in 'GreenletTests.pas',
  AsyncThread in 'AsyncThread.pas',
  HubStressTests in 'HubStressTests.pas',
  Utils in 'Utils.pas',
  GSyncObjTests in 'GSyncObjTests.pas',
  Aio in '..\Aio.pas',
  AioTests in 'AioTests.pas',
  GreenletsImpl in '..\Impl\GreenletsImpl.pas',
  ChannelImpl in '..\Impl\ChannelImpl.pas',
  sock in '..\Ext\sock.pas',
  PasMP in '..\Ext\PasMP.pas',
  ChannelTests in 'ChannelTests.pas',
  MonkeyPatch in '..\MonkeyPatch.pas',
  AioImpl in '..\Impl\AioImpl.pas',
  GInterfaces in '..\GInterfaces.pas',
  GarbageCollector in '..\GarbageCollector.pas';

{$R *.RES}

begin
  DUnitTestRunner.RunRegisteredTests;
  ReportMemoryLeaksOnShutdown := True;
end.

