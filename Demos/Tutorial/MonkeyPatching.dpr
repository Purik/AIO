program MonkeyPatching;

uses
  Vcl.Forms,
  MonkeyPatchForm in 'MonkeyPatchForm.pas' {MainForm},
  {$I ../Impl.inc}
  {$I ../Includes.inc}
  System.SysUtils;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
