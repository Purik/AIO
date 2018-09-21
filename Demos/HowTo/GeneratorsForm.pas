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
  N, I: Integer;
  Gen: TGenerator<UInt64>;
  Fibonacci: TSymmetricArgsRoutine;
begin

  // Declare filter function
  Fibonacci := procedure(const Args: array of const)
  var
    a, b, c: UInt64;
    i, n: Integer;
  begin
    n := Args[0].AsInteger;
    a := 0;
    b := 1;
    for i := 0 to n do
    begin
      c := a;
      a := b;
      b := c + b;
      TGenerator<UInt64>.Yield(c);
    end;
  end;

  N := StrToInt(EditEx1Input.Text);
  EditEx1Output.Text := '';
  // RUN !!!
  Gen := TGenerator<UInt64>.Create(Fibonacci, [N]);
  for I in Gen do
  begin
    EditEx1Output.Text := EditEx1Output.Text + IntToStr(I) + ' '
  end;

end;

end.
