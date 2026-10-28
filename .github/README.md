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
- New connections start fitted to the window, with the remote cursor shown and the VP9 codec. These defaults are set once, on first start; change them any time in Settings → Display. Devices you connected to before keep the view settings saved for them.

Builds are Windows x64 only.

## Download

[Releases](https://github.com/hnhan110/rustdesk-compact/releases) contain `rustdesk-<version>-compact.<n>-x86_64.exe` and `SHA256SUMS.txt`. The exe is the same kind of installer as the official `rustdesk-<version>-x86_64.exe`: run it, or install with `--silent-install`. Builds are not code-signed.

The protocol and configuration are those of the upstream tag, so a build works with official RustDesk clients and servers of the same version. Turn automatic updates off on the installed client (`rustdesk.exe --option allow-auto-update N`, as administrator), otherwise the updater replaces it with the official build.

## Source

`main` is an upstream RustDesk tag plus the changes below. Upstream files only get short hooks; the rest lives in new files.

| File | Change |
|---|---|
| `flutter/lib/desktop/pages/compact_home_page.dart` | new: the compact main window |
| `flutter/lib/common/widgets/compact_peer_row.dart` | new, part of `peer_card.dart`: one-line rows and name sorting |
| `flutter/lib/desktop/pages/compact_update.dart` | new: update check and install; `kCompactRepo` names the repository it reads releases from, so forks change it |
| `flutter/lib/desktop/pages/compact_release.dart` | new: the release tag, written by the build workflow (`dev` in source) |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | 2 lines: import and show the compact window |
| `flutter/lib/common/widgets/peer_card.dart` | 3 lines: `part` directive and the row hook |
| `flutter/lib/common/widgets/peers_view.dart` | 10 lines: row height, no margins, sorting |
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
