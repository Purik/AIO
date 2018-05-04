object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Timer example'
  ClientHeight = 152
  ClientWidth = 386
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object TimerLabel: TLabel
    Left = 151
    Top = 53
    Width = 154
    Height = 29
    Caption = '-'
    Color = clWhite
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -24
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentColor = False
    ParentFont = False
  end
  object StartTimerBtn: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Start Timer'
    TabOrder = 0
    OnClick = StartTimerBtnClick
  end
  object StopTimerBtn: TButton
    Left = 151
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Stop Timer'
    Enabled = False
    TabOrder = 1
    OnClick = StopTimerBtnClick
  end
  object IntervalEdit: TLabeledEdit
    Left = 8
    Top = 53
    Width = 92
    Height = 21
    EditLabel.Width = 73
    EditLabel.Height = 13
    EditLabel.Caption = 'Interval (msec)'
    TabOrder = 2
    Text = '1000'
  end
end
