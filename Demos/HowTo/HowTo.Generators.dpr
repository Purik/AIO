program HowTo.Generators;

uses
   {$I ../Impl.inc}
  {$I ../Includes.inc}
  Vcl.Forms,
  GeneratorsForm in 'GeneratorsForm.pas' {GeneratorsMainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TGeneratorsMainForm, GeneratorsMainForm);
  Application.Run;
end.
