unit MonkeyPatchForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Greenlets, GInterfaces, MonkeyPatch, Vcl.StdCtrls,
  Vcl.ExtCtrls;

type

  TMainForm = class(TForm)
    StartTimerBtn: TButton;
    StopTimerBtn: TButton;
    TimerLabel: TLabel;
    IntervalEdit: TLabeledEdit;
    procedure StartTimerBtnClick(Sender: TObject);
    procedure StopTimerBtnClick(Sender: TObject);
  private
    FTimer: TSymmetric<Integer>;
    procedure EnableStop(const Enable: Boolean);
  public

  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.EnableStop(const Enable: Boolean);
begin
  StopTimerBtn.Enabled := Enable;
  StartTimerBtn.Enabled := not Enable;
  IntervalEdit.Enabled := not Enable;
end;

procedure TMainForm.StartTimerBtnClick(Sender: TObject);
var
  Routine: TSymmetricRoutine<Integer>;
begin

  Routine := procedure(const Interval: Integer)
  var
    Counter: Integer;
  begin
    Counter := 0;
    try
      while True do
      begin
        TimerLabel.Caption := IntToStr(Counter);
        Inc(Counter);
        GreenSleep(Interval)
      end;
    finally
      TimerLabel.Caption := 'Terminated'
    end;
  end;

  FTimer := TSymmetric<Integer>.Spawn(Routine, StrToInt(IntervalEdit.Text));

  EnableStop(True)
end;

procedure TMainForm.StopTimerBtnClick(Sender: TObject);
begin
  EnableStop(False);
  FTimer.Kill
end;

initialization
  // Afterr calling this method you can use Greenlets engine in GUI
  // as native mechanism
  MonkeyPatch.PatchWinMsg(True);

end.
