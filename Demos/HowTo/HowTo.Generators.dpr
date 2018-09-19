program HowTo.Generators;

uses
  Vcl.Forms,
  GeneratorsForm in 'GeneratorsForm.pas' {GeneratorsMainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TGeneratorsMainForm, GeneratorsMainForm);
  Application.Run;
end.
