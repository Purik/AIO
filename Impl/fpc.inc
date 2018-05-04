{$IFDEF MSWINDOWS}
function CreateFiber(dwStackSize: SIZE_T; lpStartAddress: TFNFiberStartRoutine;
  lpParameter: Pointer): Pointer; stdcall; external kernel32 name 'CreateFiber';

function DeleteFiber(lpFiber: Pointer): BOOL; stdcall; external kernel32 name 'DeleteFiber';

function ConvertThreadToFiber(lpParameter: Pointer): DWORD; stdcall; external kernel32 name 'ConvertThreadToFiber';

procedure SwitchToFiber(lpFiber: Pointer); stdcall; external kernel32 name 'SwitchToFiber';

{$ENDIF}
