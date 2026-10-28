import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/compact_release.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Releases are looked up here; forks change it to their own repository.
const kCompactRepo = 'hnhan110/rustdesk-compact';
const _kSkipOption = 'compact-update-skip';

/// `1.5.0-compact.2` -> [1, 5, 0, 2]; null for anything else, such as `dev`.
List<int>? _parseRelease(String tag) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)-compact\.(\d+)$').firstMatch(tag);
  if (m == null) return null;
  return List.generate(4, (i) => int.parse(m.group(i + 1)!));
}

bool _isNewer(List<int> a, List<int> b) {
  for (var i = 0; i < 4; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Reads the latest release tag from the redirect of `releases/latest`,
/// which, unlike the REST API, is not rate limited per IP.
Future<String?> _latestReleaseTag() async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('https://github.com/$kCompactRepo/releases/latest'));
    request.followRedirects = false;
    final response = await request.close();
    await response.drain();
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null) return null;
    return RegExp(r'/releases/tag/([^/?#]+)$').firstMatch(location)?.group(1);
  } catch (e) {
    debugPrint('compact update: check failed: $e');
    return null;
  } finally {
    client.close();
  }
}

/// Offers the latest release when it is newer than this build. Automatic
/// checks stay quiet on errors, skip versions the user chose to skip, and do
/// nothing in development or portable builds.
Future<void> compactCheckForUpdate({required bool manual}) async {
  if (!isWindows) return;
  if (!bind.mainIsInstalled()) {
    if (manual) showToast(translate('Install RustDesk to get updates'));
    return;
  }
  final current = _parseRelease(kCompactRelease);
  if (current == null && !manual) return;
  final latestTag = await _latestReleaseTag();
  final latest = latestTag == null ? null : _parseRelease(latestTag);
  if (latestTag == null || latest == null) {
    if (manual) showToast(translate('Failed to check for updates'));
    return;
  }
  if (current != null && !_isNewer(latest, current)) {
    if (manual) showToast(translate('You have the latest version'));
    return;
  }
  if (!manual && bind.getLocalFlutterOption(k: _kSkipOption) == latestTag) {
    return;
  }
  _showUpdateDialog(latestTag);
}

void _showUpdateDialog(String tag) {
  final notesUrl = 'https://github.com/$kCompactRepo/releases/tag/$tag';
  final progress = ValueNotifier<double?>(null);
  var downloading = false;
  String? error;

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> update() async {
      setState(() {
        downloading = true;
        error = null;
      });
      error = await _downloadAndInstall(tag, progress);
      if (error == null) {
        close();
      } else {
        setState(() => downloading = false);
      }
    }

    return CustomAlertDialog(
      title: Text(translate('Update available')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${translate('New version')}: $tag\n'
              '${translate('Current version')}: $kCompactRelease'),
          const SizedBox(height: 12),
          Text(translate(
              'The installer is downloaded from GitHub and checked before it runs. Windows asks for permission to install; RustDesk then restarts and open remote sessions close.')),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => launchUrlString(notesUrl),
            child: Text(translate('Release notes'),
                style: const TextStyle(
                    color: MyTheme.accent,
                    decoration: TextDecoration.underline)),
          ),
          if (downloading) ...[
            const SizedBox(height: 12),
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, value, __) => LinearProgressIndicator(value: value),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        dialogButton('Skip this version',
            isOutline: true,
            onPressed: downloading
                ? null
                : () {
                    bind.setLocalFlutterOption(k: _kSkipOption, v: tag);
                    close();
                  }),
        dialogButton('Later', isOutline: true, onPressed: downloading ? null : close),
        dialogButton('Update', onPressed: downloading ? null : update),
      ],
      onCancel: downloading ? null : close,
    );
  });
}

/// Downloads the release exe, checks it against the release's SHA256SUMS.txt
/// and starts `<exe> --update` elevated. Returns an error message, or null.
Future<String?> _downloadAndInstall(
    String tag, ValueNotifier<double?> progress) async {
  final name = 'rustdesk-$tag-x86_64.exe';
  final base = 'https://github.com/$kCompactRepo/releases/download/$tag';
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
  final client = HttpClient();
  try {
    final sumsRequest = await client.getUrl(Uri.parse('$base/SHA256SUMS.txt'));
    final sumsResponse = await sumsRequest.close();
    if (sumsResponse.statusCode != 200) {
      return translate('Failed to download the update');
    }
    final sums = await sumsResponse.transform(utf8.decoder).join();
    final expected = RegExp(r'^([0-9a-fA-F]{64}) \*?' + RegExp.escape(name) + r'\s*$',
            multiLine: true)
        .firstMatch(sums)
        ?.group(1)
        ?.toUpperCase();
    if (expected == null) return translate('Failed to download the update');

    final request = await client.getUrl(Uri.parse('$base/$name'));
    final response = await request.close();
    if (response.statusCode != 200) {
      return translate('Failed to download the update');
    }
    final total = response.contentLength;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) progress.value = received / total;
    }
    await sink.close();

    // Single-quoted PowerShell string: a quote in the path is doubled.
    final path = file.path.replaceAll("'", "''");
    final hash = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "(Get-FileHash -Algorithm SHA256 -LiteralPath '$path').Hash",
    ]);
    if (hash.exitCode != 0 || (hash.stdout as String).trim() != expected) {
      await file.delete();
      return translate('The downloaded file did not pass the check. Nothing was installed.');
    }

    // Start-Process fails when the user declines the UAC prompt.
    final install = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "Start-Process -FilePath '$path' -ArgumentList '--update' -Verb RunAs",
    ]);
    if (install.exitCode != 0) {
      return translate('The update was cancelled.');
    }
    return null;
  } catch (e) {
    debugPrint('compact update: $e');
    return translate('Failed to download the update');
  } finally {
    client.close();
  }
}
