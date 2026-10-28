# Contributing

Issues and pull requests are welcome, in English or Vietnamese.

## Scope

This project changes only the desktop main window of RustDesk. Problems with connecting, remote sessions, file transfer, servers or mobile apps happen in official RustDesk too; report or fix those in [RustDesk](https://github.com/rustdesk/rustdesk), and they will arrive here with the next RustDesk version.

## Issues

Use the bug report or feature request form. For a bug, say which release you installed and whether the same thing happens in official RustDesk of the same version. Hide IDs, passwords and names in screenshots.

## Pull requests

- Branch from `main`.
- Keep the change in the compact files: `flutter/lib/desktop/pages/compact_home_page.dart` and `flutter/lib/common/widgets/compact_peer_row.dart`. Edits to RustDesk's own files should stay short hooks, so that new RustDesk versions merge cleanly.
- One topic per pull request; no unrelated formatting or refactoring.
- Describe what changes on screen, with a screenshot if the layout changes.

The maintainer runs the Windows build before merging; it checks the Dart code first. To build locally, follow RustDesk's build instructions in the main `README.md`.

Contributions are licensed under AGPL-3.0, the license of this project and of RustDesk.

## Conduct

See the [code of conduct](CODE_OF_CONDUCT.md).
