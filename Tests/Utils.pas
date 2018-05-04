unit Utils;

interface

// start calculation
procedure StartTime;
// stop time calculation and get timeout in millisec
function StopTime: LongWord;

implementation
uses GreenletsImpl, SysUtils;

var
  Stamp: TTime;

procedure StartTime;
begin
  Stamp := Now;
end;

function StopTime: LongWord;
begin
  Result := Time2TimeOut(Now - Stamp)
end;


end.
