import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../chat/cubit/chat_cubit.dart';
import '../../chat/cubit/chat_state.dart';
import '../../chat/models/profile_and_home_models.dart';
import '../../home/screens/home_screen.dart';
import '../cubit/welcome_cubit.dart';
import '../cubit/welcome_state.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pageController = PageController();
  final List<String> _answers = [];
  int _stepIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WelcomeCubit>().startConversation();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  UserOnboardingProfile _buildProfile(WelcomeState welcomeState) {
    final uid = welcomeState.userContext['user_id']?.toString();
    final a0 = _answers[0];
    final a1 = _answers[1];
    final a2 = _answers[2];

    String userType;
    final low = a0.toLowerCase();
    if (low.contains('salaried')) {
      userType = 'Salaried professional';
    } else if (low.contains('new to investing')) {
      userType = 'New to investing';
    } else {
      userType = 'Savings-focused';
    }

    var income = 'Not specified';
    final incMatch = RegExp(
      r'(\d{1,3}(?:,\d{3})+|\d{4,})',
    ).firstMatch(a0);
    if (incMatch != null) {
      income = '₹${incMatch.group(1)} monthly (approx.)';
    }

    return UserOnboardingProfile(
      userType: userType,
      income: income,
      goal: a1,
      onboardingPreference: a2,
      userId: (uid == null || uid.isEmpty) ? null : uid,
    );
  }

  Future<void> _finishOnboarding(WelcomeState welcomeState) async {
    if (_answers.length < 3 || !mounted) return;

    final chatCubit = context.read<ChatCubit>();
    final profile = _buildProfile(welcomeState);
    chatCubit.setUserProfile(profile);
    try {
      await chatCubit.fetchPersonalizedHome();
      if (!mounted) return;
      if (chatCubit.state.homeInsightsStatus == HomeInsightsStatus.success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
      } else {
        if (_answers.isNotEmpty) {
          _answers.removeLast();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              chatCubit.state.homeErrorMessage ??
                  'Could not load your personalized home.',
            ),
          ),
        );
      }
    }
  }

  String _stepTitle(int step) {
    if (step == 0) return 'Question 1: Financial Stage';
    if (step == 1) return 'Question 2: Main Goal';
    return 'Question 3: Preferred Onboarding';
  }

  String _stepPrompt(int step) {
    if (step == 0) {
      return 'What best describes your situation? Pick one option below.';
    }
    if (step == 1) {
      return 'What is your main goal right now? Pick one option below.';
    }
    return 'How would you like us to help you next? Pick one option below.';
  }

  List<String> _stepOptions(int step) {
    if (step == 0) {
      return const [
        'I am salaried and earn around 40,000',
        'I am new to investing',
        'I only use savings account',
      ];
    }
    if (step == 1) {
      return const [
        'I want to start SIP investing',
        'I want to build savings first',
        'I want to learn investing basics',
      ];
    }
    return const [
      'Show 2-3 best ET products for me',
      'Create a beginner onboarding path',
      'Keep it simple and jargon-free',
    ];
  }

  Future<void> _submitAnswer(String answer) async {
    final trimmed = answer.trim();
    if (trimmed.isEmpty || _busy) return;

    _answers.add(trimmed);
    setState(() => _busy = true);

    try {
      await context.read<WelcomeCubit>().sendMessage(trimmed);
      if (!mounted) return;

      final current = context.read<WelcomeCubit>().state;

      if (_stepIndex < 2) {
        setState(() {
          _stepIndex += 1;
        });
        await _pageController.animateToPage(
          _stepIndex,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
        );
      } else {
        await _finishOnboarding(current);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ET Welcome Concierge')),
      body: SafeArea(
        child: BlocConsumer<WelcomeCubit, WelcomeState>(
          listener: (context, state) {
            if (state.status == WelcomeStatus.error &&
                state.errorMessage != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            }
          },
          builder: (context, state) {
            final stepProgress =
                (state.completed ? 3 : (_stepIndex + 1).clamp(1, 3)) / 3.0;
            final showTyping = state.isTyping || _busy;

            return Column(
              children: [
                _HeaderBanner(
                  stepProgress: stepProgress,
                  completed: state.completed,
                  stepLabel: 'Step ${_stepIndex + 1} of 3',
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: _QuestionCard(
                          title: _stepTitle(index),
                          prompt: _stepPrompt(index),
                          options: _stepOptions(index),
                          optionsEnabled: !showTyping && !state.completed,
                          onOptionTap: (value) => _submitAnswer(value),
                        ),
                      );
                    },
                  ),
                ),
                if (showTyping) const _TypingIndicator(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.stepProgress,
    required this.completed,
    required this.stepLabel,
  });

  final double stepProgress;
  final bool completed;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final subtitle = completed
        ? 'Almost done...'
        : 'Answer 3 quick questions, then open your personalized home.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Welcome Concierge',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textColor,
                  ),
                ),
              ),
              Text(
                stepLabel,
                style: const TextStyle(
                  color: AppColors.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textColor)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: stepProgress.clamp(0.0, 1.0),
            minHeight: 7,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: AppColors.backgroundColor,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.title,
    required this.prompt,
    required this.options,
    required this.optionsEnabled,
    required this.onOptionTap,
  });

  final String title;
  final String prompt;
  final List<String> options;
  final bool optionsEnabled;
  final ValueChanged<String> onOptionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textColor,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(prompt, style: const TextStyle(color: AppColors.textColor)),
            const SizedBox(height: 14),
            ...options.map((option) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  onPressed: optionsEnabled ? () => onOptionTap(option) : null,
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.textColor,
                    backgroundColor: AppColors.backgroundColor,
                    disabledForegroundColor: AppColors.textColor.withValues(
                      alpha: 0.4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: Text(
                    option,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.white,
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Saving your answer…',
            style: TextStyle(color: AppColors.textColor),
          ),
        ],
      ),
    );
  }
}
