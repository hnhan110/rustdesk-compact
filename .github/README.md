# RustDesk Compact

[RustDesk](https://github.com/rustdesk/rustdesk) with a compact, list-first main window. Remote sessions, file transfer, the protocol, settings and address books are unchanged RustDesk code; only the desktop main window is new.

## What is different

- A sidebar with Recent sessions, Favorites and each address book, with device counts.
- One box that searches the list or takes a remote ID. Enter connects to the typed ID, or to the first device in the list.
- One row per device: online status, name and ID, with connect and file transfer buttons on hover and the usual ⋮ menu.
- Online devices first, sorted by name (natural order, so "9" comes before "10") or by ID, and an "Online only" filter.
- Your own ID and one-time password in the status bar.
- A light/dark theme switch under the sidebar ("Follow system" stays in Settings → General).
- The version is shown under the sidebar. The app checks this repository's releases shortly after it starts and every 12 hours; when a newer one exists it asks before updating. Updating downloads the exe, checks its SHA-256 against the release's `SHA256SUMS.txt`, and runs it with `--update` after the Windows permission prompt. "Skip this version" stops the automatic prompt for that release; the button next to the version checks by hand.
- A "Scale down" view style: the remote screen shrinks to fit a smaller window, and a larger window shows it at 100%, centred and sharp, instead of enlarging it. It is in a session's Display menu and among the default view styles in Settings → Display.
- The normal arrow instead of RustDesk's blue dot while the remote side has sent no cursor shape, which it does not while its pointer is hidden (no mouse plugged in, for one).
- An Install button at the bottom of the sidebar when the exe runs without being installed ("Click to upgrade" over an older installed version), as the stock window has in its left pane.
- Drag files or folders from Explorer onto a remote screen to send them. With file copy and paste on (the default) and a Windows remote side that allows file transfer, they are pasted where you drop them, into the Explorer window or the desktop under the pointer, through the session's file clipboard; the remote side's Explorer shows its own copy window, and your clipboard now holds the files, as Copy in Explorer does. Drop on an empty spot of the target folder: a drop on a folder icon pastes beside it. Otherwise the file transfer window for that device opens, and they go to the folder its remote pane shows (the last one you used there, or the home folder), with the usual progress list and the usual question when a file exists already. Dropping them on that remote pane does the same (RustDesk's own drop zone there received nothing on Windows).
- New connections start with Scale down, the remote cursor shown, the VP9 codec and file copy and paste on (Ctrl+C a file in Explorer on one side, Ctrl+V in Explorer on the other, Windows to Windows). These defaults are set once, on first start or on updating from an earlier build (1.5.0-compact.2 meant to set them but kept only one); change them any time in Settings → Display. Each device you connected to before is brought to them once, at its next connection: Scale original or adaptive becomes Scale down, and the remote cursor and file copy and paste are turned on, each while it is the default. Scale custom stays, and what you change for a device afterwards is kept.

Builds are Windows x64 only.

## Download

[Releases](https://github.com/hnhan110/rustdesk-compact/releases) contain `rustdesk-<version>-compact.<n>-x86_64.exe` and `SHA256SUMS.txt`. The exe is the same kind of installer as the official `rustdesk-<version>-x86_64.exe`: run it and press Install in the sidebar, or install with `--silent-install`. Builds are not code-signed.

The protocol and configuration are those of the upstream tag, so a build works with official RustDesk clients and servers of the same version. Turn automatic updates off on the installed client (`rustdesk.exe --option allow-auto-update N`, as administrator), otherwise the updater replaces it with the official build.

## Source

`main` is an upstream RustDesk tag plus the changes below. Upstream files only get short hooks; the rest lives in new files.

| File | Change |
|---|---|
| `flutter/lib/desktop/pages/compact_home_page.dart` | new: the compact main window |
| `flutter/lib/common/widgets/compact_peer_row.dart` | new, part of `peer_card.dart`: one-line rows and name sorting |
| `flutter/lib/desktop/pages/compact_update.dart` | new: update check and install; `kCompactRepo` names the repository it reads releases from, so forks change it |
| `flutter/lib/desktop/pages/compact_release.dart` | new: the release tag, written by the build workflow (`dev` in source) |
| `flutter/lib/desktop/pages/compact_file_drop.dart` | new: files dropped on a remote screen, pasted through the file clipboard or sent through the file transfer window |
| `flutter/lib/native/compact_file_clipboard.dart`, `flutter/lib/web/compact_file_clipboard.dart` | new: puts the dropped files on the Windows clipboard, and the stub for the web build |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | 5 lines: imports, show the compact window, pass dropped files on |
| `flutter/lib/desktop/pages/file_manager_tab_page.dart` | 3 lines: import and the dropped-files hook |
| `flutter/lib/desktop/pages/file_manager_page.dart` | 3 lines: import, and the remote pane's drop handler calls the same code (RustDesk's sent the files the wrong way) |
| `flutter/windows/runner/flutter_window.cpp` | 3 lines: the drop plugin for the remote and file transfer windows; RustDesk registers it for the main window only |
| `flutter/lib/common/widgets/peer_card.dart` | 3 lines: `part` directive and the row hook |
| `flutter/lib/common/widgets/peers_view.dart` | 10 lines: row height, no margins, sorting |
| `flutter/lib/models/compact_view_style.dart` | new: the "Scale down" view style and the display defaults for each device |
| `flutter/lib/models/model.dart` | 3 lines: import, the scale hook, the defaults on session start |
| `flutter/lib/common/widgets/toolbar.dart` | 7 lines: import and the menu entry |
| `flutter/lib/desktop/pages/remote_page.dart` | 11 lines: imports, unfiltered drawing at 100%, the arrow without a cursor shape, the drop area around the remote screen |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | 12 lines: imports, Scale down as a default view style, the release tag in About |
| `.github/workflows/compact-windows.yml` | new: builds the Windows x64 exe and publishes a release |
| `.github/README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | new: this project's pages, shown instead of RustDesk's copies in `docs/` |
| `.github/pull_request_template.md` | new: pull request checklist |
| `.github/ISSUE_TEMPLATE/` | replaced: issue forms for this project |

No Rust code, configuration or version number is changed.

## Build

Actions → **Windows build** → Run workflow with a `release-tag` such as `1.5.0-compact.1` (raise the last number to rebuild the same upstream version). Published tags must have this form, because the update check compares them. Every published release is offered to installed copies, so try changes with `publish` off first. Untick `publish` to build without creating a release; the exe is then kept as a workflow artifact. The `dart-check` job reports Dart errors within minutes.

The first build of an upstream version takes about an hour: it compiles the C/C++ libraries (vcpkg), generates the Rust–Dart bridge and compiles all of RustDesk. Later builds reuse those from the Actions cache. GitHub drops cache entries unused for 7 days, so the first build after a long pause is slow again.

```bash
gh workflow run compact-windows.yml -R hnhan110/rustdesk-compact --ref main -f release-tag=1.5.0-compact.1
```

## Moving to a new upstream version

1. `git fetch https://github.com/rustdesk/rustdesk.git tag <tag> --no-tags`
2. `git merge <tag>` on `main`. Conflicts, if any, are in the hooks or issue forms listed above.
3. Compare the x64 steps of `build-for-windows-flutter` in `.github/workflows/flutter-build.yml` with `compact-windows.yml` (FLUTTER_VERSION, VCPKG_COMMIT_ID, RUST_VERSION, VERSION and the steps themselves).
4. Push and run the workflow with `release-tag=<tag>-compact.1`.

## Contributing

Issues and pull requests about the compact main window are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security problems privately as described in [SECURITY.md](SECURITY.md).

## License

AGPL-3.0, the same as RustDesk (see [LICENCE](../LICENCE)). RustDesk is developed by the RustDesk team; this project only changes the main window.
