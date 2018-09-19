unit GeneratorsForm;

interface

uses
  (*AIO modules*)
  Aio,
  GInterfaces,
  Greenlets,

  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Generics.Collections;

type
  TGeneratorsMainForm = class(TForm)
    PanelExample1: TPanel;
    LabelExample1: TLabel;
    EditEx1Input: TEdit;
    LabelEx1Input: TLabel;
    EditEx1Output: TEdit;
    LabelEx1Output: TLabel;
    ButtonEx1Run: TButton;
    procedure ButtonEx1RunClick(Sender: TObject);  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  GeneratorsMainForm: TGeneratorsMainForm;

implementation

{$R *.dfm}

procedure TGeneratorsMainForm.ButtonEx1RunClick(Sender: TObject);
type
  TInput = TList<Integer>;
var
  S, Raw: string;
  Input: TInput;
  Even: Integer;
  Gen: TGenerator<Integer>;
  Filter: TSymmetricArgsRoutine;
begin

  // Declare filter function
  Filter := procedure(const Args: array of const)
  var
    List: TInput;
    I: Integer;
  begin
    List := TInput(Args[0].AsObject);
    for I := 0 to List.Count-1 do
      if (List[I] mod 2) = 0 then
        TGenerator<Integer>.Yield(List[I]);
  end;

  Input := TInput.Create;
  try
    Raw := EditEx1Input.Text;
    for S in Raw.Split([',']) do
    begin
      Input.Add(StrToInt(S))
    end;


    EditEx1Output.Text := '';

    // RUN !!!
    Gen := TGenerator<Integer>.Create(Filter, [Input]);
    for Even in Gen do
    begin
      EditEx1Output.Text := EditEx1Output.Text + IntToStr(Even) + ','
    end;

  finally
    Input.Free;
  end;
end;

end.
