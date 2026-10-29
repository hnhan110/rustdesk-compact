import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Scale down: fits the remote screen to the window like Scale adaptive, but
/// never enlarges it past 100% (one remote pixel per screen pixel); a larger
/// window shows it centred as Scale original does.
const kCompactViewStyleScaleDown = 'compact-scale-down';

/// The Rust side only accepts original or adaptive as the default view style,
/// so a Scale down default is stored as adaptive plus this flag.
const kCompactOptionScaleDownDefault = 'compact-default-scale-down';
const _kPeerOptionDefaultsApplied = 'compact-display-defaults';
const _kPeerOptionCopyPasteApplied = 'compact-file-copy-paste';

double _originalScale(double devicePixelRatio) =>
    kIgnoreDpi ? 1.0 / devicePixelRatio : 1.0;

double compactScaleDownScale(ViewStyle v) {
  final original = _originalScale(ui.window.devicePixelRatio);
  if (v.width == 0 ||
      v.height == 0 ||
      v.displayWidth == 0 ||
      v.displayHeight == 0) {
    return original;
  }
  return min(
      original, min(v.width / v.displayWidth, v.height / v.displayHeight));
}

/// At 100% the image is drawn unfiltered, as Scale original is: centring can
/// put it on a half pixel, and filtering would then blur every pixel.
bool compactScaleDownAtOriginal(CanvasModel c) =>
    c.viewStyle.style == kCompactViewStyleScaleDown &&
    c.scale >= _originalScale(c.devicePixelRatio);

String compactGetDefaultViewStyle() {
  final style = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
  return style == kRemoteViewStyleAdaptive &&
          bind.getLocalFlutterOption(k: kCompactOptionScaleDownDefault) == 'Y'
      ? kCompactViewStyleScaleDown
      : style;
}

Future<void> compactSetDefaultViewStyle(String style) async {
  final scaleDown = style == kCompactViewStyleScaleDown;
  await bind.mainSetUserDefaultOption(
      key: kOptionViewStyle,
      value: scaleDown ? kRemoteViewStyleAdaptive : style);
  await bind.setLocalFlutterOption(
      k: kCompactOptionScaleDownDefault, v: scaleDown ? 'Y' : '');
}

/// Brings each device to the display defaults once, at its first connection
/// with this build: devices saved earlier mostly kept Scale original with the
/// remote cursor hidden, as 1.5.0-compact.2 lost those defaults. Scale custom
/// stays, and what is picked for a device afterwards is kept.
Future<void> compactApplyDisplayDefaults(SessionID sessionId, String id) async {
  await _applyFileCopyPasteDefault(sessionId);
  final applied = await bind.sessionGetOption(
      sessionId: sessionId, arg: _kPeerOptionDefaultsApplied);
  if (applied == 'Y') return;
  if (bind.getLocalFlutterOption(k: kCompactOptionScaleDownDefault) == 'Y') {
    final style = await bind.sessionGetViewStyle(sessionId: sessionId);
    if (style == kRemoteViewStyleAdaptive ||
        style == kRemoteViewStyleOriginal) {
      await bind.sessionSetViewStyle(
          sessionId: sessionId, value: kCompactViewStyleScaleDown);
    }
  }
  if (bind.mainGetUserDefaultOption(key: kOptionShowRemoteCursor) == 'Y' &&
      !bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor')) {
    await bind.sessionToggleOption(
        sessionId: sessionId, value: 'show-remote-cursor');
    // The session page read the toggle when it opened.
    ShowRemoteCursorState.find(id).value = true;
  }
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionDefaultsApplied, value: 'Y');
}

/// File copy and paste is stored with each device, so devices saved before
/// the default was set keep it off; each is turned on once while it is the
/// default, and what is picked for a device afterwards is kept.
Future<void> _applyFileCopyPasteDefault(SessionID sessionId) async {
  final applied = await bind.sessionGetOption(
      sessionId: sessionId, arg: _kPeerOptionCopyPasteApplied);
  if (applied == 'Y') return;
  if (bind.mainGetUserDefaultOption(key: kOptionEnableFileCopyPaste) == 'Y' &&
      !bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: kOptionEnableFileCopyPaste)) {
    await bind.sessionToggleOption(
        sessionId: sessionId, value: kOptionEnableFileCopyPaste);
  }
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionCopyPasteApplied, value: 'Y');
}
