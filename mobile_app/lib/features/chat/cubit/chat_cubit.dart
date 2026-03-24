import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/chat_model.dart';
import '../services/api_service.dart';
import 'chat_state.dart';

typedef JsonMap = Map<String, dynamic>;

class ChatCubit extends Cubit<ChatState> {
  ChatCubit({ApiService? apiService})
      : _apiService = apiService ?? ApiService(),
        super(ChatState.initial());

  final ApiService _apiService;

  void reset() {
    emit(ChatState.initial());
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(sender: ChatSender.user, text: trimmed));

    emit(state.copyWith(
      status: ChatStatus.loading,
      messages: updatedMessages,
      errorMessage: null,
      isTyping: true,
    ));

    try {
      final resp = await _apiService.chat(message: trimmed, userContext: state.userContext);

      final assistantMessage = resp['assistant_message'];
      final profile = resp['profile'];
      final need = resp['need'];
      final recommendations = resp['recommendations'];
      final nextAction = resp['next_action'];

      final newUserContext = Map<String, dynamic>.from(state.userContext);
      if (profile is Map<String, dynamic>) {
        final userId = profile['user_id'];
        if (userId is String && userId.isNotEmpty) {
          newUserContext['user_id'] = userId;
        }
      }

      final aiText = (assistantMessage is String && assistantMessage.trim().isNotEmpty)
          ? assistantMessage
          : _fallbackAiText(need: need, nextAction: nextAction);

      final aiMessage = ChatMessage(
        sender: ChatSender.ai,
        text: aiText,
        profile: profile is Map<String, dynamic> ? profile : null,
        need: need is String ? need : null,
        recommendations: recommendations is List
            ? recommendations.whereType<Map<String, dynamic>>().toList(growable: false)
            : null,
        nextAction: nextAction is String ? nextAction : null,
      );

      final finalMessages = List<ChatMessage>.from(updatedMessages)..add(aiMessage);

      emit(state.copyWith(
        status: ChatStatus.success,
        messages: finalMessages,
        userContext: newUserContext,
        errorMessage: null,
        isTyping: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
        isTyping: false,
      ));
    }
  }

  String _fallbackAiText({required Object? need, required Object? nextAction}) {
    final parts = <String>[];
    if (need is String && need.isNotEmpty) {
      parts.add('Need: $need');
    }
    if (nextAction is String && nextAction.isNotEmpty) {
      parts.add('Next: $nextAction');
    }
    return parts.isEmpty ? 'How can I help you with saving or investing?' : parts.join('\n');
  }
}
