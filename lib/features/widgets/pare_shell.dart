import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared building blocks so every screen has the SAME header and bottom bar.
//
// Place this file at:  lib/features/widgets/pare_shell.dart
// ─────────────────────────────────────────────────────────────────────────────

const Color _primaryBlue = Color(0xFF092C56);
const Color _softBlue = Color(0xFFE8EEF8);
const Color _tintBlue = Color.fromRGBO(9, 44, 86, 0.07);
const Color _mutedColor = Color(0xFF6B7686);
const Color _borderColor = Color(0xFFE4E9F0);
const Color _dangerColor = Color(0xFFC0392B);

/// Lets any screen's header show the update badge and open the Updates
/// screen. HomeScreen owns the real update logic and simply publishes
/// the result here (see the small hooks added to home_screen.dart).
class PareUpdateStatus {
  PareUpdateStatus._();

  static final PareUpdateStatus instance = PareUpdateStatus._();

  /// True when an app or model update is available.
  final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// Registered by HomeScreen; opens the Updates screen.
  VoidCallback? openUpdates;
}

/// Same header on every screen:
///   [title + subtitle]  ........  [update bell] [avatar]
///
/// Pass [onBack] for pushed screens (e.g. Updates): the bell and avatar are
/// replaced by a back button on the left.
class PareHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String username;
  final VoidCallback? onBack;

  const PareHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.username = '',
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    final isBack = onBack != null;

    return Row(
      children: [
        if (isBack) ...[
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 21,
                  color: _primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _primaryBlue,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        if (!isBack) ...[
          const _UpdateBell(),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _primaryBlue,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UpdateBell extends StatelessWidget {
  const _UpdateBell();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PareUpdateStatus.instance.available,
      builder: (context, hasUpdate, child) {
        return Semantics(
          button: true,
          label: hasUpdate ? 'Updates available' : 'Updates',
          child: GestureDetector(
            onTap: () => PareUpdateStatus.instance.openUpdates?.call(),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hasUpdate ? _tintBlue : _softBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: hasUpdate ? _primaryBlue : _mutedColor,
                      size: 23,
                    ),
                  ),
                  if (hasUpdate)
                    Positioned(
                      right: 0,
                      top: -2,
                      child: Container(
                        width: 17,
                        height: 17,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: _dangerColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Same bottom bar for the whole app: white bar, soft pill behind the
/// active tab.
class PareBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PareBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem('Home', Icons.home_outlined, Icons.home_rounded),
    _NavItem('History', Icons.history_rounded, Icons.history_rounded),
    _NavItem('Settings', Icons.settings_outlined, Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = i == currentIndex;

              return Semantics(
                button: true,
                selected: active,
                label: item.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active ? _softBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active ? item.activeIcon : item.icon,
                          size: 23,
                          color: active ? _primaryBlue : const Color(0xFF8A94A3),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? _primaryBlue
                                : const Color(0xFF8A94A3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItem(this.label, this.icon, this.activeIcon);
}