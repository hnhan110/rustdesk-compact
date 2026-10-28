import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/compact_release.dart';
import 'package:flutter_hbb/desktop/pages/compact_update.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

const _kCompactDisplayDefaultsApplied = 'compact-display-defaults-v1';

/// Display defaults for new connections: fit to window, the remote cursor
/// shown, VP9. Applied once, so changes in Settings → Display stick.
void _applyCompactDisplayDefaults() {
  if (bind.getLocalFlutterOption(k: _kCompactDisplayDefaultsApplied) == 'Y') {
    return;
  }
  const defaults = {
    kOptionViewStyle: kRemoteViewStyleAdaptive,
    kOptionShowRemoteCursor: 'Y',
    kOptionCodecPreference: 'vp9',
  };
  defaults.forEach((key, value) {
    if (isOptionFixed(key) != true) {
      bind.mainSetUserDefaultOption(key: key, value: value);
    }
  });
  bind.setLocalFlutterOption(k: _kCompactDisplayDefaultsApplied, v: 'Y');
}

/// Compact main window: lists on the left, one box that both searches the
/// list and takes a remote ID, and the peer list filling the rest.
class CompactHomePage extends StatefulWidget {
  const CompactHomePage({Key? key}) : super(key: key);

  @override
  State<CompactHomePage> createState() => _CompactHomePageState();
}

class _CompactHomePageState extends State<CompactHomePage> {
  static const double _sidebarWidth = 200;

  final _recentView = RecentPeersView(menuPadding: kDesktopMenuPadding);
  final _favoriteView = FavoritePeersView(menuPadding: kDesktopMenuPadding);
  final _abView = AddressBookPeersView(menuPadding: kDesktopMenuPadding);
  final _showPassword = false.obs;
  Timer? _updateTimer;

  bool get _abEnabled => gFFI.peerTabModel.isEnabled[PeerTabIndex.ab.index];

  @override
  void initState() {
    super.initState();
    compactPeerRows = true;
    peerCardUiType.value = PeerUiType.list;
    _applyCompactDisplayDefaults();
    final sort = bind.getLocalFlutterOption(k: kCompactOptionSort);
    if (sort.startsWith(kCompactSortName) || sort.startsWith(kCompactSortId)) {
      compactSortMode.value = sort;
    }
    peerSearchText.value = '';
    peerSearchTextController.clear();
    _updateTimer = Timer(const Duration(seconds: 10), () {
      compactCheckForUpdate(manual: false);
      _updateTimer = Timer.periodic(const Duration(hours: 12),
          (_) => compactCheckForUpdate(manual: false));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = gFFI.peerTabModel;
      final tab = model.currentTab;
      if (tab != PeerTabIndex.recent.index && tab != PeerTabIndex.fav.index) {
        model.setCurrentTab(
            _abEnabled ? PeerTabIndex.ab.index : PeerTabIndex.recent.index);
      }
      if (model.currentTab == PeerTabIndex.ab.index) {
        gFFI.abModel.unsetSelectedTags();
        if (gFFI.userModel.isLogin) {
          gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(context),
                const VerticalDivider(width: 1),
                Expanded(child: _buildMain(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildStatusBar(context),
        ],
      ),
    );
  }

  Future<void> _selectTab(PeerTabIndex tab, {String? abName}) async {
    final model = gFFI.peerTabModel;
    if (model.currentTab != tab.index) {
      model.setCurrentTabCachedPeers([]);
      model.setCurrentTab(tab.index);
      await bind.setLocalFlutterOption(
          k: kOptionPeerTabIndex, v: tab.index.toString());
    }
    if (abName != null && abName != gFFI.abModel.currentName.value) {
      await gFFI.abModel.setCurrentName(abName);
      await bind.setLocalFlutterOption(k: kOptionCurrentAbName, v: abName);
    }
    if (tab == PeerTabIndex.ab) {
      gFFI.abModel.unsetSelectedTags();
    }
  }

  List<String> _abNames() {
    final names = gFFI.abModel.addressBookNames();
    final personal = gFFI.abModel.personalAddressBookName();
    final hasPersonal = names.remove(personal);
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (hasPersonal) names.insert(0, personal);
    return names;
  }

  Widget _buildSidebar(BuildContext context) {
    final mutedColor =
        Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.5);
    Widget sectionLabel(String text, {Widget? trailing}) => Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                  overflow: TextOverflow.ellipsis),
            ),
            if (trailing != null) trailing,
          ],
        ).paddingOnly(left: 10, right: 2, top: 14, bottom: 4);

    return Container(
      width: _sidebarWidth,
      color: Theme.of(context).colorScheme.background,
      child: Column(
        children: [
          Expanded(child: _buildNavigation(context, sectionLabel, mutedColor)),
          _buildVersion(context, mutedColor),
        ],
      ),
    );
  }

  Widget _buildVersion(BuildContext context, Color? mutedColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Text('${translate('Version')} $kCompactRelease',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: mutedColor)),
        ),
        if (isOptionFixed(kCommConfKeyTheme) != true)
          Tooltip(
            message: translate(isDark ? 'Light' : 'Dark'),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => MyTheme.changeDarkMode(
                  isDark ? ThemeMode.light : ThemeMode.dark),
              child: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 16,
                      color: mutedColor)
                  .paddingAll(4),
            ),
          ),
        Tooltip(
          message: translate('Check for updates'),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => compactCheckForUpdate(manual: true),
            child: Icon(Icons.system_update_alt, size: 16, color: mutedColor)
                .paddingAll(4),
          ),
        ),
      ],
    ).paddingOnly(left: 18, right: 10, top: 4, bottom: 8);
  }

  Widget _buildNavigation(BuildContext context,
      Widget Function(String, {Widget? trailing}) sectionLabel,
      Color? mutedColor) {
    return Consumer<PeerTabModel>(
        builder: (context, model, _) => Obx(() {
          final current = model.currentTab;
          final currentAb = gFFI.abModel.currentName.value;
          final isLogin = gFFI.userModel.isLogin;
          final names = isLogin ? _abNames() : <String>[];
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              sectionLabel(translate('Connection')),
              _navItem(
                context,
                icon: Icons.access_time,
                label: translate('Recent sessions'),
                selected: current == PeerTabIndex.recent.index,
                onTap: () => _selectTab(PeerTabIndex.recent),
              ),
              _navItem(
                context,
                icon: Icons.star_border,
                label: translate('Favorites'),
                selected: current == PeerTabIndex.fav.index,
                onTap: () => _selectTab(PeerTabIndex.fav),
              ),
              if (_abEnabled) ...[
                sectionLabel(
                  translate('Address book'),
                  trailing: isLogin
                      ? Tooltip(
                          message: translate('Refresh'),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => gFFI.abModel.pullAb(
                                force: ForcePullAb.listAndCurrent,
                                quiet: false),
                            child: Icon(Icons.refresh,
                                    size: 16, color: mutedColor)
                                .paddingAll(4),
                          ),
                        )
                      : null,
                ),
                if (!isLogin)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: loginDialog,
                        child: Text(translate('Login'))),
                  ),
                for (final name in names)
                  _navItem(
                    context,
                    icon: IconFont.addressBook,
                    label: gFFI.abModel.translatedName(name),
                    count: gFFI.abModel.addressbooks[name]?.peers.length,
                    selected: current == PeerTabIndex.ab.index &&
                        currentAb == name,
                    onTap: () => _selectTab(PeerTabIndex.ab, abName: name),
                  ),
              ],
            ],
          );
        }));
  }

  Widget _navItem(BuildContext context,
      {required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      int? count}) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.titleLarge?.color;
    final color = selected ? MyTheme.accent : textColor?.withOpacity(0.8);
    return Material(
      color: selected ? MyTheme.accent.withOpacity(0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: color)),
            ),
            if (count != null)
              Text('$count',
                  style: TextStyle(
                      fontSize: 12, color: textColor?.withOpacity(0.5))),
          ],
        ).paddingSymmetric(horizontal: 10, vertical: 8),
      ),
    ).marginOnly(bottom: 2);
  }

  Widget _buildMain(BuildContext context) {
    return Consumer<PeerTabModel>(
      builder: (context, model, _) {
        final tab = model.currentTab;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(context)
                .paddingOnly(left: 12, right: 12, top: 12, bottom: 10),
            _buildListHeader(context, tab).paddingSymmetric(horizontal: 12),
            _buildColumnHeader(context),
            Expanded(
              child: tab == PeerTabIndex.recent.index
                  ? _recentView
                  : tab == PeerTabIndex.fav.index
                      ? _favoriteView
                      : _buildAddressBook(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: peerSearchTextController,
            autofocus: true,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _connect(),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: translate('Search name or enter ID'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: Obx(() => peerSearchText.value.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        peerSearchTextController.clear();
                        peerSearchText.value = '';
                      },
                    )),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: ElevatedButton(
            onPressed: _connect,
            child: Text(translate('Connect')).paddingSymmetric(horizontal: 8),
          ),
        ),
      ],
    );
  }

  void _onSearchChanged(String text) {
    final compact = text.replaceAll(' ', '');
    peerSearchText.value =
        RegExp(r'^\d+$').hasMatch(compact) ? compact : text;
  }

  void _connect() {
    final text = peerSearchTextController.text.trim();
    if (text.isEmpty) return;
    final model = gFFI.peerTabModel;
    final tab = PeerTabIndex.values[model.currentTab];
    final peers = model.currentTabCachedPeers;
    final id = text.replaceAll(' ', '');
    final match = peers.firstWhereOrNull((p) => p.id == id);
    if (match != null) {
      connectInPeerTab(context, match, tab);
    } else if (RegExp(r'^\d{6,}$').hasMatch(id)) {
      connect(context, id);
    } else if (peers.isNotEmpty) {
      connectInPeerTab(context, peers.first, tab);
    } else if (RegExp(r'^[\w-]{6,16}$').hasMatch(text)) {
      connect(context, text);
    } else {
      showToast(translate('No matching device'));
    }
  }

  Peers _peersOf(int tab) {
    if (tab == PeerTabIndex.recent.index) return gFFI.recentPeersModel;
    if (tab == PeerTabIndex.fav.index) return gFFI.favoritePeersModel;
    return gFFI.abModel.peersModel;
  }

  Widget _buildListHeader(BuildContext context, int tab) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final peers = _peersOf(tab);
    return Row(
      children: [
        Obx(() {
          final abName = gFFI.abModel.currentName.value;
          return Text(
              tab == PeerTabIndex.recent.index
                  ? translate('Recent sessions')
                  : tab == PeerTabIndex.fav.index
                      ? translate('Favorites')
                      : gFFI.abModel.translatedName(abName),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
        }),
        const SizedBox(width: 10),
        AnimatedBuilder(
          animation: peers,
          builder: (context, _) {
            final online = peers.peers.where((p) => p.online).length;
            return Text(
              '${peers.peers.length} ${translate('devices')} · $online ${translate('online')}',
              style: TextStyle(fontSize: 12, color: textColor?.withOpacity(0.6)),
            );
          },
        ),
        const Spacer(),
        Obx(() {
          final sort = compactSortMode.value;
          final onlineOnly = sort.endsWith(kCompactOnlineOnlySuffix);
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _setSort(
                sort.startsWith(kCompactSortId) ? kCompactSortId : kCompactSortName,
                !onlineOnly),
            child: Row(
              children: [
                Icon(
                    onlineOnly
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: onlineOnly
                        ? MyTheme.accent
                        : textColor?.withOpacity(0.6)),
                const SizedBox(width: 6),
                Text(translate('Online only'),
                    style: TextStyle(
                        fontSize: 13, color: textColor?.withOpacity(0.8))),
              ],
            ).paddingSymmetric(horizontal: 4, vertical: 4),
          );
        }),
      ],
    ).marginOnly(bottom: 6);
  }

  void _setSort(String mode, bool onlineOnly) {
    final value = onlineOnly ? '$mode$kCompactOnlineOnlySuffix' : mode;
    compactSortMode.value = value;
    bind.setLocalFlutterOption(k: kCompactOptionSort, v: value);
  }

  Widget _buildColumnHeader(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.titleLarge?.color?.withOpacity(0.6);
    return Obx(() {
      final sort = compactSortMode.value;
      final byId = sort.startsWith(kCompactSortId);
      final onlineOnly = sort.endsWith(kCompactOnlineOnlySuffix);
      Widget label(String text, String mode, bool active) => InkWell(
            onTap: () => _setSort(mode, onlineOnly),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text,
                    style: TextStyle(
                        fontSize: 12,
                        color: mutedColor,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal)),
                if (active)
                  Icon(Icons.arrow_drop_down, size: 16, color: mutedColor),
              ],
            ),
          );
      return Container(
        height: 30,
        padding: const EdgeInsets.only(left: 56, right: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor.withOpacity(0.08)),
            bottom: BorderSide(color: theme.dividerColor.withOpacity(0.08)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: label(translate('Name'), kCompactSortName, !byId),
              ),
            ),
            SizedBox(
              width: kCompactIdColumnWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: label(translate('ID'), kCompactSortId, byId),
              ),
            ),
            const SizedBox(width: kCompactActionsWidth),
          ],
        ),
      );
    });
  }

  Widget _buildAddressBook(BuildContext context) {
    return Obx(() {
      if (!gFFI.userModel.isLogin) {
        return Center(
          child: ElevatedButton(
              onPressed: loginDialog, child: Text(translate('Login'))),
        );
      }
      if (gFFI.userModel.networkError.isNotEmpty) {
        return netWorkErrorWidget();
      }
      return Column(
        children: [
          if (gFFI.abModel.currentAbLoading.value &&
              gFFI.abModel.currentAbEmpty)
            const LinearProgressIndicator(),
          buildErrorBanner(context,
              loading: gFFI.abModel.currentAbLoading,
              err: gFFI.abModel.abPullError,
              retry: null,
              close: gFFI.abModel.clearPullErrors),
          buildErrorBanner(context,
              loading: gFFI.abModel.currentAbLoading,
              err: gFFI.abModel.currentAbPushError,
              retry: null,
              close: () => gFFI.abModel.currentAbPushError.value = ''),
          Expanded(child: _abView),
        ],
      );
    });
  }

  Widget _buildStatusBar(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const Expanded(child: OnlineStatusWidget()),
          if (!bind.isOutgoingOnly()) _buildMyDesktop(context),
        ],
      ),
    );
  }

  Widget _buildMyDesktop(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final textColor = Theme.of(context).textTheme.titleLarge?.color;
        final labelStyle =
            TextStyle(fontSize: 13, color: textColor?.withOpacity(0.6));
        const valueStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        Widget iconButton(IconData icon, String tip, VoidCallback onTap) =>
            Tooltip(
              message: translate(tip),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onTap,
                child: Icon(icon, size: 16, color: textColor?.withOpacity(0.6))
                    .paddingAll(5),
              ),
            );
        return Row(
          children: [
            Text('${translate('ID')}: ', style: labelStyle),
            Text(model.serverId.text, style: valueStyle),
            iconButton(Icons.copy, 'Copy', () {
              Clipboard.setData(ClipboardData(text: model.serverId.text));
              showToast(translate('Copied'));
            }),
            if (showOneTime) ...[
              const SizedBox(width: 12),
              Text('${translate('One-time Password')}: ', style: labelStyle),
              Obx(() => Text(
                  _showPassword.value ? model.serverPasswd.text : '••••••',
                  style: valueStyle)),
              Obx(() => iconButton(
                  _showPassword.value
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  'Show password',
                  () => _showPassword.value = !_showPassword.value)),
              iconButton(Icons.refresh, 'Refresh Password',
                  () => bind.mainUpdateTemporaryPassword()),
            ],
          ],
        ).paddingOnly(right: 12);
      }),
    );
  }
}
