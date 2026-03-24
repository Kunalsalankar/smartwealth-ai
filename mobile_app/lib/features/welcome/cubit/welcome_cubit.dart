import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../chat/services/api_service.dart';
import 'welcome_state.dart';

class WelcomeCubit extends Cubit<WelcomeState> {
  WelcomeCubit({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(WelcomeState.initial());

  final ApiService _apiService;

  Future<void> startConversation() async {
    if (state.messages.isNotEmpty) return;
    await sendMessage(
      'Hi, I am new here. Help me get started with investing in simple terms.',
      isSynthetic: true,
    );
  }

  Future<void> sendMessage(String text, {bool isSynthetic = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final updatedMessages = List<WelcomeMessage>.from(state.messages);
    const starterText =
        'Welcome to ET! I will keep this simple and quick. To begin, what is your monthly income range and are you new to investing?';
    if (!isSynthetic) {
      updatedMessages.add(WelcomeMessage(text: trimmed, isUser: true));
    } else if (updatedMessages.isEmpty) {
      // Ensure the user sees a welcome prompt immediately on app open.
      updatedMessages.add(
        const WelcomeMessage(text: starterText, isUser: false),
      );
    }

    emit(
      state.copyWith(
        status: WelcomeStatus.loading,
        messages: updatedMessages,
        errorMessage: null,
        isTyping: true,
      ),
    );

    try {
      final resp = await _apiService.chat(
        message: trimmed,
        userContext: state.userContext,
      );

      final assistantMessage = (resp['assistant_message'] ?? '')
          .toString()
          .trim();
      final welcome = resp['welcome'];
      final profile = resp['profile'];

      final newUserContext = Map<String, dynamic>.from(state.userContext);
      if (profile is Map<String, dynamic>) {
        final userId = profile['user_id'];
        if (userId is String && userId.isNotEmpty) {
          newUserContext['user_id'] = userId;
        }
      }

      bool completed = state.completed;
      int turn = state.turn;
      List<JsonMap> products = state.products;
      List<JsonMap> onboardingPath = state.onboardingPath;

      if (welcome is Map<String, dynamic>) {
        final valueTurn = welcome['turn'];
        final valueCompleted = welcome['completed'];
        final valueProducts = welcome['products'];
        final valuePath = welcome['onboarding_path'];

        if (valueTurn is int) {
          turn = valueTurn;
        }
        if (valueCompleted is bool) {
          completed = valueCompleted;
        }
        if (valueProducts is List) {
          products = valueProducts.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
        }
        if (valuePath is List) {
          onboardingPath = valuePath.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
        }
      }

      final aiText = assistantMessage.isEmpty
          ? 'I can help you build a simple investing start. Tell me your monthly income and main goal.'
          : assistantMessage;

      final finalMessages = List<WelcomeMessage>.from(updatedMessages);
      if (isSynthetic && finalMessages.isNotEmpty) {
        finalMessages.removeLast();
      }
      finalMessages.add(WelcomeMessage(text: aiText, isUser: false));

      emit(
        state.copyWith(
          status: WelcomeStatus.success,
          messages: finalMessages,
          userContext: newUserContext,
          completed: completed,
          turn: turn,
          products: products,
          onboardingPath: onboardingPath,
          isTyping: false,
        ),
      );
    } catch (e) {
      if (e is TimeoutException) {
        final timeoutMessages = List<WelcomeMessage>.from(updatedMessages)
          ..add(
            const WelcomeMessage(
              text:
                  'I am taking longer than expected to connect. Please share your monthly income range and main goal (saving or investing), and I will continue your onboarding.',
              isUser: false,
            ),
          );
        emit(
          state.copyWith(
            status: WelcomeStatus.success,
            messages: timeoutMessages,
            isTyping: false,
          ),
        );
        return;
      }

      if (isSynthetic && state.messages.isEmpty) {
        emit(
          state.copyWith(
            status: WelcomeStatus.success,
            messages: const [WelcomeMessage(text: starterText, isUser: false)],
            isTyping: false,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: WelcomeStatus.error,
          errorMessage: e.toString(),
          isTyping: false,
        ),
      );
    }
  }
}
