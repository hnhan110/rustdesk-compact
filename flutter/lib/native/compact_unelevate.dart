import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart' as win32;

// SECURITY_IMPERSONATION_LEVEL and TOKEN_TYPE values, not in package:win32.
const _kSecurityImpersonation = 2;
const _kTokenPrimary = 1;

final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _duplicateTokenEx = _advapi32.lookupFunction<
    Int32 Function(
        IntPtr hExistingToken,
        Uint32 dwDesiredAccess,
        Pointer lpTokenAttributes,
        Int32 impersonationLevel,
        Int32 tokenType,
        Pointer<IntPtr> phNewToken),
    int Function(
        int hExistingToken,
        int dwDesiredAccess,
        Pointer lpTokenAttributes,
        int impersonationLevel,
        int tokenType,
        Pointer<IntPtr> phNewToken)>('DuplicateTokenEx');

final _createProcessWithTokenW = _advapi32.lookupFunction<
        Int32 Function(
            IntPtr hToken,
            Uint32 dwLogonFlags,
            Pointer<Utf16> lpApplicationName,
            Pointer<Utf16> lpCommandLine,
            Uint32 dwCreationFlags,
            Pointer lpEnvironment,
            Pointer<Utf16> lpCurrentDirectory,
            Pointer<win32.STARTUPINFO> lpStartupInfo,
            Pointer<win32.PROCESS_INFORMATION> lpProcessInformation),
        int Function(
            int hToken,
            int dwLogonFlags,
            Pointer<Utf16> lpApplicationName,
            Pointer<Utf16> lpCommandLine,
            int dwCreationFlags,
            Pointer lpEnvironment,
            Pointer<Utf16> lpCurrentDirectory,
            Pointer<win32.STARTUPINFO> lpStartupInfo,
            Pointer<win32.PROCESS_INFORMATION> lpProcessInformation)>(
    'CreateProcessWithTokenW');

/// Main window: when the installed RustDesk runs elevated and Explorer does
/// not, starts it again with Explorer's token and exits.
///
/// The update runs elevated and reopens the main window from there, and so
/// does switching the service from an elevated window. Windows then keeps
/// files dragged from Explorer away from every RustDesk window.
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
void compactRelaunchUnelevated() {
  final exe = Platform.resolvedExecutable;
  if (!bind.mainIsInstalled() ||
      !path.equals(path.dirname(exe).toLowerCase(),
          bind.installInstallPath().toLowerCase())) {
    return;
  }
  if (_isElevated(win32.GetCurrentProcess()) != true) return;
  final shell = _shellProcess();
  if (shell == 0) return;
  final started = _isElevated(shell) == false && _startAs(shell, exe);
  win32.CloseHandle(shell);
  if (started) exit(0);
}

/// The process of the desktop's shell, or 0.
int _shellProcess() {
  final hwnd = win32.GetShellWindow();
  if (hwnd == 0) return 0;
  final pid = calloc<Uint32>();
  try {
    if (win32.GetWindowThreadProcessId(hwnd, pid) == 0) return 0;
    return win32.OpenProcess(
        win32.PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_LIMITED_INFORMATION,
        win32.FALSE,
        pid.value);
  } finally {
    calloc.free(pid);
  }
}

/// Whether [process] runs elevated, or null when its token cannot be read.
bool? _isElevated(int process) {
  final token = calloc<IntPtr>();
  final elevated = calloc<Uint32>();
  final size = calloc<Uint32>();
  try {
    if (win32.OpenProcessToken(
            process, win32.TOKEN_ACCESS_MASK.TOKEN_QUERY, token) ==
        0) {
      return null;
    }
    final ok = win32.GetTokenInformation(
            token.value,
            win32.TOKEN_INFORMATION_CLASS.TokenElevation,
            elevated,
            sizeOf<Uint32>(),
            size) !=
        0;
    win32.CloseHandle(token.value);
    return ok ? elevated.value != 0 : null;
  } finally {
    calloc.free(token);
    calloc.free(elevated);
    calloc.free(size);
  }
}

/// Starts [exe] with the token of [process], two seconds later: the main
/// window allows one instance, so this one has to be gone first.
bool _startAs(int process, String exe) {
  final cmd = path.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32', 'cmd.exe');
  final token = calloc<IntPtr>();
  final primary = calloc<IntPtr>();
  final startup = calloc<win32.STARTUPINFO>();
  final info = calloc<win32.PROCESS_INFORMATION>();
  final app = cmd.toNativeUtf16();
  // `timeout` would need a console input, which this cmd does not get.
  final line = '"$cmd" /c ping -n 3 127.0.0.1 >nul & "$exe"'.toNativeUtf16();
  try {
    if (win32.OpenProcessToken(
            process, win32.TOKEN_ACCESS_MASK.TOKEN_DUPLICATE, token) ==
        0) {
      return false;
    }
    final duplicated = _duplicateTokenEx(
            token.value,
            win32.TOKEN_ACCESS_MASK.TOKEN_QUERY |
                win32.TOKEN_ACCESS_MASK.TOKEN_ASSIGN_PRIMARY |
                win32.TOKEN_ACCESS_MASK.TOKEN_DUPLICATE |
                win32.TOKEN_ACCESS_MASK.TOKEN_ADJUST_DEFAULT |
                win32.TOKEN_ACCESS_MASK.TOKEN_ADJUST_SESSIONID,
            nullptr,
            _kSecurityImpersonation,
            _kTokenPrimary,
            primary) !=
        0;
    win32.CloseHandle(token.value);
    if (!duplicated) return false;
    startup.ref.cb = sizeOf<win32.STARTUPINFO>();
    final started = _createProcessWithTokenW(
            primary.value,
            0,
            app,
            line,
            win32.PROCESS_CREATION_FLAGS.CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            startup,
            info) !=
        0;
    win32.CloseHandle(primary.value);
    if (started) {
      win32.CloseHandle(info.ref.hProcess);
      win32.CloseHandle(info.ref.hThread);
    }
    return started;
  } finally {
    calloc.free(token);
    calloc.free(primary);
    calloc.free(startup);
    calloc.free(info);
    calloc.free(app);
    calloc.free(line);
  }
}
