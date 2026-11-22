import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/primary_button.dart';
import '../pt/figure/guide_3d.dart';

class _Page {
  const _Page({
    required this.clipId,
    this.highlight = const {},
    this.caption,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  /// Mannequin clip shown on the page.
  final String clipId;

  /// Body parts flagged in the warning colour (mistake demo).
  final Set<String> highlight;
  final String? caption;
  final String eyebrow;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    clipId: 'push_up',
    eyebrow: 'ON-DEVICE TRACKING',
    title: 'Your camera counts\nevery rep',
    body:
        'Prop up your phone and go. Pose tracking runs on your device, so '
        'nothing is uploaded and every rep is counted from any angle.',
  ),
  _Page(
    clipId: 'squat',
    highlight: {'torso'},
    caption: 'Chest falling forward: the coach would say "chest up".',
    eyebrow: 'LIVE COACHING',
    title: 'Fix mistakes\nas they happen',
    body:
        '3D guides show the right way from any angle. During a set the coach '
        'calls out what to change: go deeper, chest up, hips in line.',
  ),
  _Page(
    clipId: 'jumping_jack',
    eyebrow: 'LEVEL UP',
    title: 'Earn XP.\nClimb the ranks',
    body:
        'Thirteen exercises, MY PT guided sessions, challenges with friends '
        'and a streak to protect. Every rep earns XP from Rookie to Legend.',
  ),
];

/// First-launch introduction: three pages with animated demos.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _pages.length - 1) {
      context.go(Routes.onboardingSetup);
      return;
    }
    _controller.nextPage(duration: AppTokens.slow, curve: AppTokens.curve);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
                  child: Row(
                    children: [
                      const Expanded(child: BrandWordmark(size: 18)),
                      TextButton(
                        onPressed: () => context.go(Routes.onboardingSetup),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) =>
                        _OnboardingPage(page: _pages[i], active: i == _index),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      Semantics(
                        label: 'Page ${_index + 1} of ${_pages.length}',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _pages.length; i++)
                              AnimatedContainer(
                                duration: AppTokens.normal,
                                curve: AppTokens.curve,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: i == _index ? 28 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: i == _index
                                      ? AppColors.brandGradient
                                      : null,
                                  color: i == _index ? null : AppColors.divider,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: isLast ? 'GET STARTED' : 'NEXT',
                        icon: isLast ? Icons.bolt_rounded : Icons.arrow_forward,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page, required this.active});

  final _Page page;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Centred when it fits, scrollable on short phones or large text.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: _page(theme),
        ),
      ),
    );
  }

  Widget _page(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:
            [
                  AppCard(
                    glow: true,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 210,
                          child: Guide3D(
                            clipId: page.clipId,
                            playing: active,
                            highlight: page.highlight,
                            interactive: false,
                          ),
                        ),
                        if (page.caption != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: AppColors.warning,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    page.caption!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    page.eyebrow,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(height: 1.1),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    page.body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ]
                .animate(interval: 70.ms)
                .fadeIn(duration: 350.ms)
                .slideY(begin: 0.08, end: 0, curve: AppTokens.curve),
      ),
    );
  }
}

/// Soft radial brand glow behind onboarding content.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.6),
            radius: 0.9,
            colors: [
              AppColors.primary.withValues(alpha: 0.07),
              AppColors.background,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
