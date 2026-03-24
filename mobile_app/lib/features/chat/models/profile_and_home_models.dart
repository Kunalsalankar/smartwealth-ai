import 'package:equatable/equatable.dart';

/// Structured profile after welcome onboarding (sent to Gemini for home).
class UserOnboardingProfile extends Equatable {
  const UserOnboardingProfile({
    required this.userType,
    required this.income,
    required this.goal,
    this.onboardingPreference,
    this.userId,
  });

  final String userType;
  final String income;
  final String goal;
  final String? onboardingPreference;
  final String? userId;

  Map<String, dynamic> toJson() => {
    'user_type': userType,
    'income': income,
    'goal': goal,
    if (onboardingPreference != null && onboardingPreference!.trim().isNotEmpty)
      'onboarding_preference': onboardingPreference!.trim(),
  };

  @override
  List<Object?> get props => [
    userType,
    income,
    goal,
    onboardingPreference,
    userId,
  ];
}

/// Parsed `/personalized_home` response (all strings from Gemini).
class HomeInsightsData extends Equatable {
  const HomeInsightsData({
    required this.greeting,
    required this.recommendations,
    required this.nextAction,
    required this.tip,
  });

  final String greeting;
  final List<String> recommendations;
  final String nextAction;
  final String tip;

  factory HomeInsightsData.fromJson(Map<String, dynamic> json) {
    final recs = json['recommendations'];
    final list = recs is List
        ? recs.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    return HomeInsightsData(
      greeting: (json['greeting'] ?? '').toString(),
      recommendations: list,
      nextAction: (json['next_action'] ?? '').toString(),
      tip: (json['tip'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [greeting, recommendations, nextAction, tip];
}
