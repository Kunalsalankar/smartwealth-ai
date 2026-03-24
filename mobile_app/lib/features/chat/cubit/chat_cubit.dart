import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/chat_model.dart';
import '../models/profile_and_home_models.dart';
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

  void setUserContext(JsonMap context) {
    emit(state.copyWith(userContext: Map<String, dynamic>.from(context)));
  }

  void setUserProfile(UserOnboardingProfile profile) {
    final ctx = Map<String, dynamic>.from(state.userContext);
    if (profile.userId != null && profile.userId!.isNotEmpty) {
      ctx['user_id'] = profile.userId;
    }
    if (profile.userType.toLowerCase().contains('salaried')) {
      ctx['user_type'] = 'salaried';
    } else if (profile.userType.toLowerCase().contains('savings')) {
      ctx['user_type'] = 'salaried';
    } else {
      ctx['user_type'] = 'salaried';
    }
    final digits = RegExp(r'[\d,]+').firstMatch(profile.income);
    if (digits != null) {
      final n = int.tryParse(digits.group(0)!.replaceAll(',', ''));
      if (n != null) {
        ctx['income'] = n;
      }
    }
    final g = profile.goal.toLowerCase();
    if (g.contains('sip') || g.contains('invest')) {
      ctx['goal'] = 'investing';
    } else if (g.contains('sav') || g.contains('emergency')) {
      ctx['goal'] = 'saving';
    } else if (g.contains('learn')) {
      ctx['goal'] = 'learning';
    }

    emit(
      state.copyWith(
        userProfile: profile,
        userContext: ctx,
        clearHomeError: true,
      ),
    );
  }

  Future<void> fetchPersonalizedHome() async {
    final profile = state.userProfile;
    if (profile == null) {
      emit(
        state.copyWith(
          homeInsightsStatus: HomeInsightsStatus.error,
          homeErrorMessage: 'Profile is missing.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        homeInsightsStatus: HomeInsightsStatus.loading,
        clearHomeError: true,
      ),
    );

    try {
      final body = profile.toJson();
      final resp = await _apiService.personalizedHome(body);
      final data = HomeInsightsData.fromJson(resp);
      if (data.greeting.isEmpty ||
          data.recommendations.length < 2 ||
          data.nextAction.isEmpty ||
          data.tip.isEmpty) {
        throw Exception('Incomplete AI response');
      }

      emit(
        state.copyWith(
          homeInsights: data,
          homeInsightsStatus: HomeInsightsStatus.success,
          clearHomeError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          homeInsightsStatus: HomeInsightsStatus.error,
          homeErrorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(sender: ChatSender.user, text: trimmed));

    emit(
      state.copyWith(
        status: ChatStatus.loading,
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

      final aiText =
          (assistantMessage is String && assistantMessage.trim().isNotEmpty)
          ? assistantMessage
          : _fallbackAiText(need: need, nextAction: nextAction);

      final aiMessage = ChatMessage(
        sender: ChatSender.ai,
        text: aiText,
        profile: profile is Map<String, dynamic> ? profile : null,
        need: need is String ? need : null,
        recommendations: recommendations is List
            ? recommendations.whereType<Map<String, dynamic>>().toList(
                growable: false,
              )
            : null,
        nextAction: nextAction is String ? nextAction : null,
      );

      final finalMessages = List<ChatMessage>.from(updatedMessages)
        ..add(aiMessage);

      emit(
        state.copyWith(
          status: ChatStatus.success,
          messages: finalMessages,
          userContext: newUserContext,
          errorMessage: null,
          isTyping: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ChatStatus.error,
          errorMessage: e.toString(),
          isTyping: false,
        ),
      );
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
    return parts.isEmpty
        ? 'How can I help you with saving or investing?'
        : parts.join('\n');
  }
}
