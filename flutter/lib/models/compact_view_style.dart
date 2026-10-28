import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_hbb/common.dart';
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
const _kPeerOptionDefaultChecked = 'compact-scale-down-default';

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

/// With the Scale down default, a device on Scale adaptive (which is what the
/// stored default gives it) is switched once; a style picked for it later in
/// the session menu is kept.
Future<void> compactApplyScaleDownDefault(SessionID sessionId) async {
  if (bind.getLocalFlutterOption(k: kCompactOptionScaleDownDefault) != 'Y') {
    return;
  }
  final checked = await bind.sessionGetOption(
      sessionId: sessionId, arg: _kPeerOptionDefaultChecked);
  if (checked == 'Y') return;
  final style = await bind.sessionGetViewStyle(sessionId: sessionId);
  if (style == kRemoteViewStyleAdaptive) {
    await bind.sessionSetViewStyle(
        sessionId: sessionId, value: kCompactViewStyleScaleDown);
  }
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionDefaultChecked, value: 'Y');
}
