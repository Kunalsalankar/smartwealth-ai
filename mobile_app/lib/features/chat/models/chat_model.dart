import 'package:equatable/equatable.dart';

enum ChatSender { user, ai }

typedef JsonMap = Map<String, dynamic>;

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.profile,
    this.need,
    this.recommendations,
    this.nextAction,
  });

  final ChatSender sender;
  final String text;

  final JsonMap? profile;
  final String? need;
  final List<JsonMap>? recommendations;
  final String? nextAction;

  @override
  List<Object?> get props => [sender, text, profile, need, recommendations, nextAction];
}
