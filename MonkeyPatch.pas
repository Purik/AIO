unit MonkeyPatch;

interface

procedure PatchWinMsg(Patch: Boolean);
procedure PatchEvent(Patch: Boolean);

implementation
uses Hub, SysUtils, Gevent, SyncObjs,
  {$IFDEF MSWINDOWS}
  Windows
  {$ENDIF}
  ;

const
  INSTR_SIZE = 6;

{$IFDEF MSWINDOWS}
var
  OldBytesGetMessageW: array [0..INSTR_SIZE-1] of Byte;
  OldBytesWaitMessage: array [0..INSTR_SIZE-1] of Byte;
  OldBytesWaitEvent: array [0..INSTR_SIZE-1] of Byte;
  WinMsgPatched: Boolean = False;
  EventPatched: Boolean = False;

{$ENDIF}

{$IFDEF MSWINDOWS}

function PatchedWaitMessage: BOOL; stdcall;
var
  Ev: TSingleThreadHub.TMultiplexorEvent;
  lpMsg: TMsg;
begin
  Result := PeekMessageW(lpMsg, 0, 0, 0, PM_NOREMOVE);
  while not Result do begin
    Ev := DefHub.Wait(INFINITE, [], False);
    case Ev of
      meWinMsg:
        Exit(True)
      else
        DefHub.Serve(0)
    end;
  end;
end;

function PatchedGetMessageW(var lpMsg: TMsg; hWnd: HWND;
  wMsgFilterMin, wMsgFilterMax: UINT): BOOL; stdcall;
var
  Ev: TSingleThreadHub.TMultiplexorEvent;
begin
  Result := PeekMessageW(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax, PM_REMOVE);
  while not Result do begin
    Ev := DefHub.Wait(INFINITE, [], False);
    Result := (Ev = meWinMsg) and PeekMessageW(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax, PM_REMOVE);
  end;
end;

function PatchedWaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD; stdcall;
var
  E: TGevent;
begin
  E := TGevent.Create(hHandle);
  try
    case E.WaitFor(dwMilliseconds) of
      wrSignaled:
        Exit(WAIT_OBJECT_0);
      wrTimeout:
        Exit(WAIT_TIMEOUT);
      else
        Exit(WAIT_ABANDONED)
    end;
  finally
    E.Free
  end;
end;

procedure ApiRedirect(OrigFunction, NewFunction: Pointer; var Old);
const
   TEMP_JMP: array[0..INSTR_SIZE-1] of Byte = ($E9,$90,$90,$90,$90,$C3);
var
  JmpSize: DWORD;
  JMP: array [0..INSTR_SIZE-1] of Byte;
  OldProtect: DWORD;
begin
  Move(TEMP_JMP, JMP, INSTR_SIZE);
  JmpSize := DWORD(NewFunction) - DWORD(OrigFunction) - 5;
  if not VirtualProtect(LPVOID(OrigFunction), INSTR_SIZE, PAGE_EXECUTE_READWRITE, OldProtect) then
    raise Exception.CreateFmt('%s', [SysErrorMessage(GetLastError)]);
  Move(OrigFunction^, Old, INSTR_SIZE);
  Move(JmpSize, JMP[1], 4);
  Move(JMP, OrigFunction^, INSTR_SIZE);
  VirtualProtect(LPVOID(OrigFunction), INSTR_SIZE, OldProtect, nil);
end;

procedure PatchWinMsg(Patch: Boolean);
var
  OrigGetMessageW: Pointer;
  OrigWaitMessage: Pointer;
begin
  if Patch <> WinMsgPatched then begin
    OrigGetMessageW := GetProcAddress(GetModuleHandle('user32.dll'), 'GetMessageW');
    OrigWaitMessage := GetProcAddress(GetModuleHandle('user32.dll'), 'WaitMessage');
    if Patch then begin
      ApiRedirect(OrigGetMessageW, @PatchedGetMessageW, OldBytesGetMessageW);
      ApiRedirect(OrigWaitMessage, @PatchedWaitMessage, OldBytesWaitMessage);
    end
    else begin
      Move(OldBytesGetMessageW, OrigGetMessageW, INSTR_SIZE);
      Move(OldBytesWaitMessage, OrigWaitMessage, INSTR_SIZE);
    end;
    WinMsgPatched := Patch;
  end;
end;

procedure PatchEvent(Patch: Boolean);
var
  OrigWaitEvent: Pointer;
begin
  //OldWaitEvent
  if Patch <> EventPatched then begin
    OrigWaitEvent := GetProcAddress(GetModuleHandle('kernel32.dll'), 'WaitForSingleObject');
    if Patch then begin
      ApiRedirect(OrigWaitEvent, @PatchedWaitForSingleObject, OldBytesWaitEvent);
    end
    else begin
      Move(OldBytesWaitEvent, OrigWaitEvent, INSTR_SIZE);
    end;
    WinMsgPatched := Patch;
  end;
end;

{$ENDIF}

end.
