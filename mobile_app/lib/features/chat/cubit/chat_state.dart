import 'package:equatable/equatable.dart';

import '../models/chat_model.dart';

enum ChatStatus { initial, loading, success, error }

typedef JsonMap = Map<String, dynamic>;

class ChatState extends Equatable {
  const ChatState({
    required this.status,
    required this.messages,
    required this.userContext,
    this.errorMessage,
    this.isTyping = false,
  });

  final ChatStatus status;
  final List<ChatMessage> messages;
  final JsonMap userContext;
  final String? errorMessage;
  final bool isTyping;

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
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      userContext: userContext ?? this.userContext,
      errorMessage: errorMessage,
      isTyping: isTyping ?? this.isTyping,
    );
  }

  @override
  List<Object?> get props => [status, messages, userContext, errorMessage, isTyping];
}
