import 'package:equatable/equatable.dart';

import '../models/chat_model.dart';
import '../models/profile_and_home_models.dart';

enum ChatStatus { initial, loading, success, error }

enum HomeInsightsStatus { initial, loading, success, error }

typedef JsonMap = Map<String, dynamic>;

class ChatState extends Equatable {
  const ChatState({
    required this.status,
    required this.messages,
    required this.userContext,
    this.errorMessage,
    this.isTyping = false,
    this.userProfile,
    this.homeInsights,
    this.homeInsightsStatus = HomeInsightsStatus.initial,
    this.homeErrorMessage,
  });

  final ChatStatus status;
  final List<ChatMessage> messages;
  final JsonMap userContext;
  final String? errorMessage;
  final bool isTyping;

  final UserOnboardingProfile? userProfile;
  final HomeInsightsData? homeInsights;
  final HomeInsightsStatus homeInsightsStatus;
  final String? homeErrorMessage;

  factory ChatState.initial() => const ChatState(
    status: ChatStatus.initial,
    messages: [],
    userContext: {},
  );

  ChatState copyWith({
    ChatStatus? status,
    List<ChatMessage>? messages,
    JsonMap? userContext,
    String? errorMessage,
    bool? isTyping,
    UserOnboardingProfile? userProfile,
    HomeInsightsData? homeInsights,
    HomeInsightsStatus? homeInsightsStatus,
    String? homeErrorMessage,
    bool clearHomeError = false,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      userContext: userContext ?? this.userContext,
      errorMessage: errorMessage,
      isTyping: isTyping ?? this.isTyping,
      userProfile: userProfile ?? this.userProfile,
      homeInsights: homeInsights ?? this.homeInsights,
      homeInsightsStatus: homeInsightsStatus ?? this.homeInsightsStatus,
      homeErrorMessage: clearHomeError
          ? null
          : (homeErrorMessage ?? this.homeErrorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    messages,
    userContext,
    errorMessage,
    isTyping,
    userProfile,
    homeInsights,
    homeInsightsStatus,
    homeErrorMessage,
  ];
}
