part of 'peer_card.dart';

// Compact home (see flutter/lib/desktop/pages/compact_home_page.dart):
// one-line peer rows and name sorting for the list view.

/// Set by the compact home page. When true, peer cards render as one-line rows
/// and [compactSortPeers] re-sorts the list after the default sorting.
bool compactPeerRows = false;

const kCompactOptionSort = 'compact-peer-sort';
const kCompactSortName = 'compact-name';
const kCompactSortId = 'compact-id';
const kCompactOnlineOnlySuffix = '-online';

/// Kept apart from `peerSort`, whose value the default sorting validates and
/// rewrites. Read while the peers view builds, so changes rebuild the list.
final compactSortMode = kCompactSortName.obs;
const double kCompactRowHeight = 36;
const double kCompactIdColumnWidth = 130;
const double kCompactActionsWidth = 96;

/// Compares strings so that "9 - A" sorts before "10 - A".
int compactNaturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null)
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

String compactPeerName(Peer peer) =>
    peer.alias.isEmpty ? formatID(peer.id) : peer.alias;

/// Online peers first, then by name or ID. Recent sessions keep their order.
List<Peer> compactSortPeers(List<Peer> peers, bool keepOrder) {
  final sortedBy = compactSortMode.value;
  if (sortedBy.endsWith(kCompactOnlineOnlySuffix)) {
    peers = peers.where((p) => p.online).toList();
  }
  if (keepOrder) return peers;
  final byId = sortedBy.startsWith(kCompactSortId);
  peers.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    if (byId) return a.id.compareTo(b.id);
    return compactNaturalCompare(
        compactPeerName(a).toLowerCase(), compactPeerName(b).toLowerCase());
  });
  return peers;
}

extension _CompactPeerRow on _PeerCardState {
  Widget _compactBuildRow(BuildContext context, Peer peer) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.titleLarge?.color;
    final mutedColor = textColor?.withOpacity(0.55);
    final hover = false.obs;

    Widget action(IconData icon, String tip, VoidCallback onTap) {
      return Tooltip(
        message: translate(tip),
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Icon(icon, size: 18, color: mutedColor).paddingAll(5),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => hover.value = true,
      onExit: (_) => hover.value = false,
      child: Obx(() => Container(
            height: kCompactRowHeight,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: hover.value ? theme.hoverColor : Colors.transparent,
              border: Border(
                  bottom: BorderSide(
                      color: theme.dividerColor.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Tooltip(
                  message: translate(peer.online ? 'Online' : 'Offline'),
                  waitDuration: const Duration(seconds: 1),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: peer.online
                        ? Colors.green
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 10),
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      mutedColor ?? Colors.grey, BlendMode.srcIn),
                  child: getPlatformImage(peer.platform, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    compactPeerName(peer),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        color: peer.online ? textColor : mutedColor),
                  ),
                ),
                if (_shouldBuildPasswordIcon(peer))
                  Icon(Icons.key, size: 12, color: mutedColor)
                      .marginOnly(right: 8),
                SizedBox(
                  width: kCompactIdColumnWidth,
                  child: Text(
                    formatID(peer.id),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: mutedColor),
                  ),
                ),
                SizedBox(
                  width: kCompactActionsWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Visibility(
                        visible: hover.value,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Row(children: [
                          action(Icons.desktop_windows_outlined, 'Connect',
                              () => widget.connect(context, peer.id)),
                          action(
                              Icons.folder_outlined,
                              'Transfer file',
                              () => connectInPeerTab(context, peer, widget.tab,
                                  isFileTransfer: true)),
                        ]),
                      ),
                      checkBoxOrActionMoreLandscape(peer, isTile: true),
                    ],
                  ),
                ),
              ],
            ),
          )),
    );
  }
}
