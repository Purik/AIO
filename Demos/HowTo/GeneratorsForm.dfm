object GeneratorsMainForm: TGeneratorsMainForm
  Left = 0
  Top = 0
  Caption = 'Generators'
  ClientHeight = 133
  ClientWidth = 579
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object PanelExample1: TPanel
    Left = 0
    Top = 0
    Width = 579
    Height = 133
    Align = alClient
    TabOrder = 0
    DesignSize = (
      579
      133)
    object LabelExample1: TLabel
      Left = 8
      Top = 8
      Width = 153
      Height = 13
      Caption = 'Example1: Enumerate fibonacci '
    end
    object LabelEx1Input: TLabel
      Left = 8
      Top = 35
      Width = 26
      Height = 13
      Caption = 'Input'
    end
    object LabelEx1Output: TLabel
      Left = 8
      Top = 94
      Width = 34
      Height = 13
      Caption = 'Output'
    end
    object EditEx1Input: TEdit
      Left = 88
      Top = 32
      Width = 474
      Height = 21
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
      Text = '10'
    end
    object EditEx1Output: TEdit
      Left = 88
      Top = 91
      Width = 474
      Height = 21
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 1
    end
    object ButtonEx1Run: TButton
      Left = 88
      Top = 60
      Width = 201
      Height = 25
      Caption = 'RUN !!! (filter even numbers)'
      TabOrder = 2
      OnClick = ButtonEx1RunClick
    end
  end
end
