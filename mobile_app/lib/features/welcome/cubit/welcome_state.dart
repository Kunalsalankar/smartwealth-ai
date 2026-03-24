import 'package:equatable/equatable.dart';

enum WelcomeStatus { initial, loading, success, error }

class WelcomeState extends Equatable {
  const WelcomeState({
    required this.status,
    required this.messages,
    required this.userContext,
    required this.completed,
    required this.turn,
    required this.products,
    required this.onboardingPath,
    this.errorMessage,
    this.isTyping = false,
  });

  final WelcomeStatus status;
  final List<WelcomeMessage> messages;
  final Map<String, dynamic> userContext;
  final bool completed;
  final int turn;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> onboardingPath;
  final String? errorMessage;
  final bool isTyping;

  factory WelcomeState.initial() => const WelcomeState(
    status: WelcomeStatus.initial,
    messages: [],
    userContext: {'flow': 'welcome'},
    completed: false,
    turn: 0,
    products: [],
    onboardingPath: [],
  );

  WelcomeState copyWith({
    WelcomeStatus? status,
    List<WelcomeMessage>? messages,
    Map<String, dynamic>? userContext,
    bool? completed,
    int? turn,
    List<Map<String, dynamic>>? products,
    List<Map<String, dynamic>>? onboardingPath,
    String? errorMessage,
    bool? isTyping,
  }) {
    return WelcomeState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      userContext: userContext ?? this.userContext,
      completed: completed ?? this.completed,
      turn: turn ?? this.turn,
      products: products ?? this.products,
      onboardingPath: onboardingPath ?? this.onboardingPath,
      errorMessage: errorMessage,
      isTyping: isTyping ?? this.isTyping,
    );
  }

  @override
  List<Object?> get props => [
    status,
    messages,
    userContext,
    completed,
    turn,
    products,
    onboardingPath,
    errorMessage,
    isTyping,
  ];
}

class WelcomeMessage extends Equatable {
  const WelcomeMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  List<Object?> get props => [text, isUser];
}
