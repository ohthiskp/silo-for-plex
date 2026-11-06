import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/video_quality_preference.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/settings/add_connection_screen.dart';
import '../screens/settings/general_settings_screen.dart';
import '../screens/settings/logs_screen.dart';
import '../screens/settings/services_settings_screen.dart';
import '../screens/settings/settings_utils.dart';
import '../screens/settings/subtitle_styling_screen.dart';
import '../screens/settings/theme_settings_screen.dart';
import '../services/settings_service.dart' as settings;
import '../services/update_service.dart';
import '../widgets/library_management_sheet.dart';
import '../widgets/settings_builder.dart';

const _purple = Color(0xFF7C4DFF);
const _ink = Color(0xFFF2F0F7);
const _muted = Color(0xA8F2F0F7);

/// Astra's Settings home: a grid of glass cards (app and updates, playback,
/// sources, library, appearance, advanced). Every control is wired to an
/// existing setting; "All Settings" opens the complete classic list.
class AstraSettingsDashboard extends StatelessWidget {
  const AstraSettingsDashboard({super.key, required this.openAllSettings});

  final VoidCallback openAllSettings;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final twoColumns = width >= 980;
    final pad = width >= 700 ? 40.0 : 16.0;
    final left = <Widget>[const _AppCard(), const _SourcesCard(), const _AppearanceCard()];
    final right = <Widget>[const _PlaybackCard(), const _LibraryCard(), _AdvancedCard(openAllSettings: openAllSettings)];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Soft violet light at the top, like the rest of Astra.
          Positioned(
            top: -220,
            left: width * 0.25,
            child: IgnorePointer(
              child: Container(
                width: 640,
                height: 420,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0x337C4DFF), Color(0x007C4DFF)]),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(width >= 900 ? 156 : pad, width >= 700 ? 36 : 12, pad, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: _ink,
                          fontSize: width >= 700 ? 40 : 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: width >= 700 ? 28 : 18),
                      if (twoColumns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _Column(children: left)),
                            const SizedBox(width: 28),
                            Expanded(child: _Column(children: right)),
                          ],
                        )
                      else
                        _Column(
                          children: [left[0], right[0], left[1], right[1], left[2], right[2]],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 22), children[i]],
    ],
  );
}

// ---------------------------------------------------------------- building blocks

class _Card extends StatelessWidget {
  const _Card({this.icon, this.title, this.subtitle, required this.children, this.header});
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        border: Border.all(color: const Color(0x17FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            if (title != null)
              Row(
                children: [
                  if (icon != null) ...[Icon(icon, color: _ink, size: 24), const SizedBox(width: 16)],
                  Text(title!, style: const TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w600)),
                ],
              ),
            if (subtitle != null)
              Padding(
                padding: EdgeInsets.only(left: icon != null ? 40 : 0, top: 4),
                child: Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 13.5)),
              ),
            const SizedBox(height: 6),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0x12FFFFFF)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: _ink.withValues(alpha: 0.85), size: 22),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(color: _ink, fontSize: 15.5, fontWeight: FontWeight.w500)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing! else if (onTap != null) const _Chevron(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();
  @override
  Widget build(BuildContext context) => const Icon(Icons.chevron_right_rounded, color: _muted, size: 24);
}

class _Value extends StatelessWidget {
  const _Value(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(color: _muted, fontSize: 14)),
        const SizedBox(width: 6),
        const _Chevron(),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.pref, required this.icon, required this.title, this.subtitle});
  final settings.Pref<bool> pref;
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<bool>(
      pref: pref,
      builder: (context, value, _) => _Row(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => settings.SettingsService.instance.write(pref, !value),
        trailing: Switch.adaptive(
          value: value,
          activeTrackColor: _purple,
          onChanged: (v) => settings.SettingsService.instance.write(pref, v),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

// ---------------------------------------------------------------- cards

class _AppCard extends StatelessWidget {
  const _AppCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              child: Image.asset('assets/plezy.png', width: 76, height: 76, semanticLabel: 'Astra'),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final info = snap.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Astra', style: TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        info == null ? ' ' : 'v${info.version} (Build ${info.buildNumber})',
                        style: const TextStyle(color: _muted, fontSize: 14),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (UpdateService.isUpdateCheckAvailable) const _CheckForUpdatesButton(),
          ],
        ),
      ),
      children: [
        _Row(
          icon: Icons.tune_rounded,
          title: 'General',
          subtitle: 'Language, startup screen and behavior',
          onTap: () => _push(context, const GeneralSettingsScreen()),
        ),
      ],
    );
  }
}

class _CheckForUpdatesButton extends StatefulWidget {
  const _CheckForUpdatesButton();
  @override
  State<_CheckForUpdatesButton> createState() => _CheckForUpdatesButtonState();
}

class _CheckForUpdatesButtonState extends State<_CheckForUpdatesButton> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (UpdateService.useNativeUpdater) {
        // Sparkle shows its own window: "You're up to date" or the update.
        await UpdateService.checkForUpdatesNative(inBackground: false);
      } else {
        final info = await UpdateService.checkForUpdates();
        if (!mounted) return;
        final has = info != null && info['hasUpdate'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(has ? 'Astra ${info['latestVersion']} is available.' : "You're on the latest version.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _check,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0x1FFFFFFF),
        foregroundColor: _ink,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _ink))
          : const Text('Check for Updates'),
    );
  }
}

class _PlaybackCard extends StatelessWidget {
  const _PlaybackCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.play_arrow_outlined,
      title: 'Playback',
      children: [
        const _VideoQualityPicker(),
        _Row(
          icon: Icons.subtitles_outlined,
          title: 'Subtitle Style',
          trailing: const _Chevron(),
          onTap: () => _push(context, const SubtitleStylingScreen()),
        ),
        _Toggle(
          pref: settings.SettingsService.rememberTrackSelections,
          icon: Icons.record_voice_over_outlined,
          title: 'Remember Audio and Subtitles',
          subtitle: 'Keep your track picks for the next episode',
        ),
        _Toggle(
          pref: settings.SettingsService.autoPlayNextEpisode,
          icon: Icons.skip_next_outlined,
          title: 'Autoplay Next Episode',
        ),
      ],
    );
  }
}

/// Settings → Playback → Preferred Quality: Auto, HD, 4K and nothing else. An
/// Apple-style sliding segmented control on a frosted track, saved for this
/// device only and applied to every playback (see PlaybackQualityManager).
class _VideoQualityPicker extends StatelessWidget {
  const _VideoQualityPicker();

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<VideoQualityPreference>(
      pref: settings.SettingsService.videoQualityPreference,
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.high_quality_outlined, color: _ink.withValues(alpha: 0.85), size: 22),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preferred Quality',
                        style: TextStyle(color: _ink, fontSize: 15.5, fontWeight: FontWeight.w500),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            value.detail,
                            key: ValueKey(value),
                            style: const TextStyle(color: _muted, fontSize: 12.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<VideoQualityPreference>(
                      groupValue: value,
                      backgroundColor: const Color(0x1AFFFFFF),
                      thumbColor: const Color(0x40FFFFFF),
                      padding: const EdgeInsets.all(3),
                      onValueChanged: (v) {
                        if (v == null) return;
                        settings.SettingsService.instance.write(settings.SettingsService.videoQualityPreference, v);
                      },
                      children: {
                        for (final p in VideoQualityPreference.values)
                          p: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Text(
                              p.label,
                              style: TextStyle(
                                color: p == value ? _ink : _muted,
                                fontSize: 14,
                                fontWeight: p == value ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard();

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<MultiServerProvider>().astraServers;
    return _Card(
      icon: Icons.storage_rounded,
      title: 'Sources',
      subtitle: 'Your connected media servers.',
      children: [
        for (final s in servers)
          _Row(
            icon: s.isPlex ? Icons.play_circle_outline : Icons.dns_outlined,
            title: s.displayName,
            subtitle: s.online ? 'Connected' : 'Offline',
            onTap: () => _push(context, const ServicesSettingsScreen()),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: TextButton.icon(
              onPressed: () {
                final active = context.read<ActiveProfileProvider>().active;
                _push(context, AddConnectionScreen(targetProfile: active));
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Source'),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0x14FFFFFF),
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.folder_outlined,
      title: 'Library',
      subtitle: 'What shows up and how.',
      children: [
        _Toggle(
          pref: settings.SettingsService.showUnwatchedCount,
          icon: Icons.filter_9_plus_outlined,
          title: 'Show Unwatched Count',
        ),
        _Toggle(
          pref: settings.SettingsService.hideSpoilers,
          icon: Icons.visibility_off_outlined,
          title: 'Hide Spoilers',
        ),
        _Row(
          icon: Icons.layers_outlined,
          title: 'Manage Libraries',
          onTap: () => showLibraryManagementSheet(context),
        ),
        _Row(
          icon: Icons.extension_outlined,
          title: 'Request Service',
          subtitle: 'Seerr, for titles you don’t have yet',
          onTap: () => _push(context, const ServicesSettingsScreen()),
        ),
      ],
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  static const _choices = <(settings.ThemeMode, String, IconData)>[
    (settings.ThemeMode.plum, 'Astra', Icons.auto_awesome_outlined),
    (settings.ThemeMode.oled, 'OLED', Icons.dark_mode_outlined),
    (settings.ThemeMode.ember, 'Ember', Icons.local_fire_department_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return _Card(
      icon: Icons.brush_outlined,
      title: 'Appearance',
      subtitle: 'Customize the look and feel.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              for (final (mode, label, icon) in _choices) ...[
                Expanded(
                  child: _ThemeChoice(
                    label: label,
                    icon: icon,
                    selected: theme.themeMode == mode,
                    onTap: () => theme.setThemeMode(mode),
                  ),
                ),
                if (mode != _choices.last.$1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        _Row(
          icon: Icons.palette_outlined,
          title: 'More Themes',
          trailing: _Value(themeModeLabel(theme.themeMode)),
          onTap: () => _push(context, const ThemeSettingsScreen()),
        ),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 84,
          decoration: BoxDecoration(
            color: selected ? const Color(0x1F7C4DFF) : const Color(0x0AFFFFFF),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(color: selected ? const Color(0xFF8B5CF6) : const Color(0x14FFFFFF), width: selected ? 1.6 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _ink, size: 26),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: selected ? _ink : _muted, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvancedCard extends StatelessWidget {
  const _AdvancedCard({required this.openAllSettings});
  final VoidCallback openAllSettings;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.code_rounded,
      title: 'Advanced',
      subtitle: 'Developer and power user options.',
      children: [
        _Toggle(
          pref: settings.SettingsService.enableHardwareDecoding,
          icon: Icons.bolt_outlined,
          title: 'Hardware Acceleration',
        ),
        _Row(
          icon: Icons.description_outlined,
          title: 'Playback Logs',
          onTap: () => _push(context, const LogsScreen()),
        ),
        _Row(icon: Icons.settings_outlined, title: 'All Settings', onTap: openAllSettings),
      ],
    );
  }
}

