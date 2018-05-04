unit AsyncThread;

interface
uses Classes, SyncObjs;

type
  TAnyMethod = procedure of object;

  TAnyMethodThread = class(TThread)
  protected
    FProc: TAnyMethod;
    procedure Execute; override;
  public
    constructor Create(Proc: TAnyMethod); overload;
  end;

implementation

{ TAnyMethodThread }

constructor TAnyMethodThread.Create(Proc: TAnyMethod);
begin
  FProc := Proc;
  Inherited Create(False);
end;

procedure TAnyMethodThread.Execute;
begin
  try
    FProc;
  finally

  end;
end;

end.
