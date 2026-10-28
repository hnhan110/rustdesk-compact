# Security policy

## Supported versions

Only the latest release gets fixes. Each release is built on one RustDesk version; security fixes in RustDesk reach this project when it moves to a newer RustDesk version.

## What to report here

Vulnerabilities in the code this project adds: the compact main window (`flutter/lib/desktop/pages/compact_home_page.dart`, `flutter/lib/common/widgets/compact_peer_row.dart` and their hooks) and the build workflow (`.github/workflows/compact-windows.yml`).

Everything else is RustDesk code, including the protocol, encryption, remote sessions, file transfer and servers. Report those to RustDesk as described in [their security policy](https://github.com/rustdesk/rustdesk/security/policy).

## How to report

Use **Report a vulnerability** on the [Security tab](https://github.com/hnhan110/rustdesk-compact/security/advisories/new). The report stays private between you and the maintainer. Please do not open a public issue.

This is a personal project maintained in spare time. You will get a reply as soon as possible, usually within a week.
