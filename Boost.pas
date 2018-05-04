unit Boost;

interface
uses SysUtils;

const
  BOOST_CONTEXT_LIBRARY =
{$IFDEF CPUX86}
  {$IFDEF MSWINDOWS}
    'boost_context_i386.dll'
  {$ENDIF MSWINDOWS}
  {$IFDEF LINUX}
    'boost_context_i386.so'
  {$ENDIF LINUX}
  {$IFDEF IOS}
    {$MESSAGE ERROR 'Unknown condition'}
  {$ENDIF IOS}
{$ENDIF CPUX86}
{$IFDEF CPUX64}
  {$IFDEF MSWINDOWS}
    'boost_context_x64.dll'
  {$ENDIF MSWINDOWS}
  {$IFDEF LINUX}
    'boost_context_x64.so'
  {$ENDIF LINUX}
  {$IFDEF IOS}
    {$MESSAGE ERROR 'Unknown condition'}
  {$ENDIF IOS}
{$ENDIF CPUX64};


type
  // Контекст выполнения кода
  TContext = Pointer;

  // Ф-ия входа в контекст
  TEnterProc = procedure(Param: Pointer); cdecl;


procedure jump_fcontext(var ofc: TContext; nfc: TContext;
  param: Pointer; regs: Boolean);
function make_fcontext(StackPtr: Pointer; StackSize: NativeUInt;
  EnterProc: TEnterProc): TContext;

implementation
uses Windows;

var
  LibHandle: THandle;

  jump_fcontext_func: procedure(var ofc: TContext; nfc: TContext;
    param: Pointer; regs: Boolean); cdecl;
  make_fcontext_func: function(StackPtr: Pointer; StackSize: NativeUInt;
    EnterProc: TEnterProc): TContext; cdecl;

procedure jump_fcontext(var ofc: TContext; nfc: TContext; param: Pointer;
  regs: Boolean);
begin
  if LibHandle > 0 then
    jump_fcontext_func(ofc, nfc, param,regs );
end;

function make_fcontext(StackPtr: Pointer; StackSize: NativeUInt;
  EnterProc: TEnterProc): TContext;
begin
  if LibHandle > 0 then
    Result := make_fcontext_func(StackPtr, StackSize, EnterProc)
  else
    Result := nil;
end;

initialization
  LibHandle := LoadLibrary(BOOST_CONTEXT_LIBRARY);
  if LibHandle > 0 then begin
    @jump_fcontext_func := GetProcAddress(LibHandle, 'jump_fcontext');
    @make_fcontext_func := GetProcAddress(LibHandle, 'make_fcontext');
  end
end.
