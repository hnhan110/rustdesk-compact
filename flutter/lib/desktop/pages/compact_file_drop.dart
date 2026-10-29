import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/native/compact_file_clipboard.dart'
    if (dart.library.html) 'package:flutter_hbb/web/compact_file_clipboard.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

/// Window message for files dropped on a remote screen. The remote window
/// sends it to the main window, which opens the peer's file transfer tab and
/// passes it on; there the files go to the folder the remote pane shows.
///
/// A file transfer window is where the peer accepts file actions, shows the
/// progress and asks about files that exist already. A second session in the
/// remote window would also overwrite the per-peer state the remote page
/// reads (current display, permissions).
const kCompactWindowDropFiles = 'compact_drop_files';

/// Wraps the remote screen: files dragged from the desktop onto it are pasted
/// where they land through the session's file copy and paste or, when that
/// cannot carry them, sent to the peer through the file transfer window.
class CompactFileDrop extends StatefulWidget {
  final FFI ffi;
  final String id;
  final Widget child;

  const CompactFileDrop(
      {Key? key, required this.ffi, required this.id, required this.child})
      : super(key: key);

  @override
  State<CompactFileDrop> createState() => _CompactFileDropState();
}

class _CompactFileDropState extends State<CompactFileDrop> {
  final _hover = false.obs;

  bool get _connected => widget.ffi.ffiModel.pi.isSet.isTrue;

  void _onDragDone(DropDoneDetails details) {
    _hover.value = false;
    if (!_connected) return;
    final files = details.files
        .map((f) => f.path)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (files.isEmpty) return;
    if (_fileClipboardOn(widget.ffi)) {
      unawaited(_pasteOnPeer(files, details.globalPosition));
    } else {
      _sendThroughFileTransfer(files);
    }
  }

  /// Explorer on the peer takes the files from the session's file clipboard
  /// and shows its own copy window: a click at the drop point focuses the
  /// window there, and Ctrl+V pastes into it.
  Future<void> _pasteOnPeer(List<String> files, Offset at) async {
    if (!await compactSetClipboardFiles(files)) {
      _sendThroughFileTransfer(files);
      return;
    }
    final input = widget.ffi.inputModel;
    input.handleMouse(InputModel.getMouseEventMove(), at);
    await input.tap(MouseButtons.left);
    // The clipboard watcher sends the file list from its own thread; give it
    // and the click a moment to reach the peer before the paste.
    await Future.delayed(const Duration(milliseconds: 600));
    await bind.sessionInputKey(
        sessionId: widget.ffi.sessionId,
        name: 'v',
        down: false,
        press: true,
        alt: false,
        ctrl: true,
        shift: false,
        command: false);
  }

  void _sendThroughFileTransfer(List<String> files) {
    final connToken = bind.sessionGetConnToken(sessionId: widget.ffi.sessionId);
    rustDeskWinManager.call(WindowType.Main, kCompactWindowDropFiles,
        jsonEncode({'id': widget.id, 'connToken': connToken, 'files': files}));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DropTarget(
        onDragEntered: (_) => _hover.value = _connected,
        onDragExited: (_) => _hover.value = false,
        onDragDone: _onDragDone,
        child: widget.child,
      ),
      Obx(() => _hover.isFalse
          ? const Offstage()
          : Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.upload_file_rounded,
                          size: 56, color: Colors.white),
                      const SizedBox(height: 12),
                      Text(translate('Transfer file'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20)),
                    ],
                  ),
                ),
              ),
            )),
    ]);
  }
}

/// Whether the session's file copy and paste can carry the files: the
/// conditions under which the toolbar offers that switch, and the switch.
bool _fileClipboardOn(FFI ffi) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  if (!isWindows || ffi.connType != ConnType.defaultConn) return false;
  if (!ffiModel.keyboard ||
      ffiModel.viewOnly ||
      ffiModel.permissions['file'] == false) {
    return false;
  }
  final supported = versionCmp(pi.version, '1.2.4') < 0
      ? pi.platform == kPeerPlatformWindows
      : bind.mainHasFileClipboard() &&
          pi.platformAdditions.containsKey(kPlatformAdditionsHasFileClipboard);
  return supported &&
      bind.sessionGetToggleOptionSync(
          sessionId: ffi.sessionId, arg: kOptionEnableFileCopyPaste);
}

/// Main window: opens or raises the peer's file transfer tab, then hands the
/// files to that window. One just created answers only once its page has set
/// a message handler, so the message is repeated for a while.
void compactRelayDroppedFiles(String args) {
  unawaited(_relayDroppedFiles(args));
}

Future<void> _relayDroppedFiles(String args) async {
  final a = jsonDecode(args);
  final String id = a['id'];
  await rustDeskWinManager.newFileTransfer(id, connToken: a['connToken']);
  final msg = jsonEncode({'id': id, 'files': a['files']});
  for (var i = 0; i < 40; i++) {
    try {
      final res = await rustDeskWinManager.call(
          WindowType.FileTransfer, kCompactWindowDropFiles, msg);
      if (res.result == true) return;
    } catch (e) {
      debugPrint('compact drop: file transfer window not ready: $e');
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }
  debugPrint('compact drop: file transfer window did not answer');
}

/// File transfer window: sends the files to the folder the peer's remote pane
/// shows, once that tab has connected and read both panes.
bool compactReceiveDroppedFiles(String args) {
  final a = jsonDecode(args);
  final String id = a['id'];
  unawaited(_sendDroppedFiles(
      () => Get.isRegistered<FFI>(tag: 'ft_$id')
          ? Get.find<FFI>(tag: 'ft_$id').fileModel
          : null,
      List<String>.from(a['files'])));
  return true;
}

/// File transfer window: files dropped on a tab's remote pane go the same
/// way, so folders arrive with their empty folders too.
void compactSendDroppedFiles(FileModel model, List<String> files) {
  unawaited(_sendDroppedFiles(() => model, files));
}

// FileType of the protocol: 1 is a directory, 4 a file.
const _kEntryTypeDir = 1;
const _kEntryTypeFile = 4;

Future<void> _sendDroppedFiles(
    FileModel? Function() find, List<String> files) async {
  final paths = files.where((p) => p.isNotEmpty).toList(growable: false);
  if (paths.isEmpty) return;
  FileModel? model;
  for (var i = 0; i < 120; i++) {
    final m = find();
    if (m != null &&
        m.localController.directory.value.path.isNotEmpty &&
        m.remoteController.directory.value.path.isNotEmpty) {
      model = m;
      break;
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }
  if (model == null) {
    debugPrint('compact drop: the file transfer is not ready');
    return;
  }
  final byFolder = <String, List<String>>{};
  for (final f in paths) {
    byFolder.putIfAbsent(path.dirname(f), () => []).add(f);
  }
  for (final e in byFolder.entries) {
    // Empty folders inside a dropped folder are recreated relative to the
    // folder the local pane shows, so it is moved to the files' folder.
    await model.localController.openDirectory(e.key);
    final items = SelectedItems(isLocal: true);
    for (final f in e.value) {
      final isDir = FileSystemEntity.isDirectorySync(f);
      var size = 0;
      if (!isDir) {
        try {
          size = File(f).lengthSync();
        } catch (_) {}
      }
      items.add(Entry()
        ..entryType = isDir ? _kEntryTypeDir : _kEntryTypeFile
        ..name = path.basename(f)
        ..path = f
        ..size = size);
    }
    await model.localController
        .sendFiles(items, model.remoteController.directoryData());
  }
}
