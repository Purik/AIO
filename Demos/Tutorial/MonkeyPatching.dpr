program MonkeyPatching;

uses
  Vcl.Forms,
  MonkeyPatchForm in 'MonkeyPatchForm.pas' {MainForm},
  AioImpl in '..\..\Impl\AioImpl.pas',
  ChannelImpl in '..\..\Impl\ChannelImpl.pas',
  GreenletsImpl in '..\..\Impl\GreenletsImpl.pas',
  PasMP in '..\..\Ext\PasMP.pas',
  sock in '..\..\Ext\sock.pas',
  Aio in '..\..\Aio.pas',
  Boost in '..\..\Boost.pas',
  GarbageCollector in '..\..\GarbageCollector.pas',
  Gevent in '..\..\Gevent.pas',
  GInterfaces in '..\..\GInterfaces.pas',
  Greenlets in '..\..\Greenlets.pas',
  Hub in '..\..\Hub.pas',
  MonkeyPatch in '..\..\MonkeyPatch.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
