import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
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

/// Wraps the remote screen: files dragged from the desktop onto it are sent
/// to the peer through the file transfer window.
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
    final connToken =
        bind.sessionGetConnToken(sessionId: widget.ffi.sessionId);
    rustDeskWinManager.call(
        WindowType.Main,
        kCompactWindowDropFiles,
        jsonEncode(
            {'id': widget.id, 'connToken': connToken, 'files': files}));
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
  unawaited(_sendDroppedFiles(a['id'], List<String>.from(a['files'])));
  return true;
}

// FileType of the protocol: 1 is a directory, 4 a file.
const _kEntryTypeDir = 1;
const _kEntryTypeFile = 4;

Future<void> _sendDroppedFiles(String id, List<String> files) async {
  FileModel? model;
  for (var i = 0; i < 120; i++) {
    if (Get.isRegistered<FFI>(tag: 'ft_$id')) {
      final m = Get.find<FFI>(tag: 'ft_$id').fileModel;
      if (m.localController.directory.value.path.isNotEmpty &&
          m.remoteController.directory.value.path.isNotEmpty) {
        model = m;
        break;
      }
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }
  if (model == null) {
    debugPrint('compact drop: file transfer to $id is not ready');
    return;
  }
  final byFolder = <String, List<String>>{};
  for (final f in files) {
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
