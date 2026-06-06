package muse

import win32 "core:sys/windows"

is_stdout_tty :: proc() -> bool {
  handle := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
  mode: win32.DWORD
  return bool(win32.GetConsoleMode(handle, &mode))
}

is_stdin_piped :: proc() -> bool {
  handle := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
  mode: win32.DWORD
  return !bool(win32.GetConsoleMode(handle, &mode))
}
