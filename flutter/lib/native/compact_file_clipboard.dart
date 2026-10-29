import 'dart:ffi';

import 'package:win32/win32.dart' as win32;

/// Puts [paths] on the clipboard as CF_HDROP, what Copy in Explorer leaves
/// there; the session's file copy and paste then offers them to the peer.
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
Future<bool> compactSetClipboardFiles(List<String> paths) async {
  final list = '${paths.join('\u0000')}\u0000\u0000';
  final header = sizeOf<win32.DROPFILES>();
  final hMem = win32.GlobalAlloc(
      win32.GLOBAL_ALLOC_FLAGS.GHND, header + list.length * 2);
  if (hMem == nullptr) return false;
  final mem = win32.GlobalLock(hMem);
  if (mem == nullptr) {
    win32.GlobalFree(hMem);
    return false;
  }
  mem.cast<win32.DROPFILES>().ref
    ..pFiles = header
    ..fWide = 1;
  final chars = Pointer<Uint16>.fromAddress(mem.address + header);
  for (var i = 0; i < list.length; i++) {
    chars[i] = list.codeUnitAt(i);
  }
  win32.GlobalUnlock(hMem);
  // Another program may hold the clipboard for a moment.
  var opened = false;
  for (var i = 0; i < 10 && !opened; i++) {
    opened = win32.OpenClipboard(0) != 0;
    if (!opened) await Future.delayed(const Duration(milliseconds: 20));
  }
  if (!opened) {
    win32.GlobalFree(hMem);
    return false;
  }
  win32.EmptyClipboard();
  final ok =
      win32.SetClipboardData(win32.CLIPBOARD_FORMAT.CF_HDROP, hMem.address) !=
          0;
  win32.CloseClipboard();
  if (!ok) win32.GlobalFree(hMem);
  return ok;
}
