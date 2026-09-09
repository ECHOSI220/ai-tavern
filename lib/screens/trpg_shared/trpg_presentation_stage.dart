import 'dart:io';

import 'package:flutter/material.dart';
import '../../app/skins/theme_tokens.dart';
import '../../app/skins/theme_manager.dart';

import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../services/trpg/trpg_presentation_service.dart';

class TRPGPresentationStage extends StatelessWidget {
  const TRPGPresentationStage({
    required this.session,
    required this.service,
    required this.onReplayVoice,
    required this.onSkip,
    this.compact = false,
    super.key,
  });

  final TRPGSession session;
  final TRPGPresentationService service;
  final ValueChanged<TRPGMessage> onReplayVoice;
  final VoidCallback onSkip;
  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final state = service.state;
      final latest = session.chatHistory.lastOrNull;
      final height = compact ? 168.0 : 340.0;
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .55),
          ),
          boxShadow: [
            BoxShadow(
              color: ThemeTokens.of(context).shadow.withValues(alpha: .24),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Background(path: state.background, state: state),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black12,
                      Colors.transparent,
                      Colors.black38,
                    ],
                    stops: [0, .45, 1],
                  ),
                ),
              ),
              ...state.visibleCharacters.map(
                (character) => _Portrait(
                  character: character,
                  npc: _npc(session, character.npcId),
                ),
              ),
              if (state.combatActive)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _Badge(
                    icon: Icons.gavel,
                    text: '战斗 · Round ${state.combatRound}',
                    color: Theme.of(context).colorScheme.errorContainer,
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (state.bgmId != null)
                      _Badge(icon: Icons.music_note, text: state.bgmId!),
                    if (state.ambientId != null)
                      _Badge(icon: Icons.air, text: state.ambientId!),
                  ],
                ),
              ),
              if (latest != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _DialogueBox(
                    message: latest,
                    speaker: _speaker(session, latest),
                    compact: compact,
                    onReplay: () => onReplayVoice(latest),
                    onSkip: onSkip,
                  ),
                ),
              if (service.active != null) _EventOverlay(event: service.active!),
            ],
          ),
        ),
      );
    },
  );

  static TRPGNPCProfile? _npc(TRPGSession session, String id) {
    final raw = session.immersionState.campaignSnapshot['npcs'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((value) {
          return TRPGNPCProfile.fromJson(value.cast<String, Object?>());
        })
        .where((value) => value.npcId == id)
        .firstOrNull;
  }

  static String _speaker(TRPGSession session, TRPGMessage message) {
    if (message.presentation.speakerType == PresentationSpeakerType.narrator ||
        message.messageType == TRPGMessageType.gmMessage) {
      return '旁白';
    }
    if (message.npcId != null) {
      return _npc(session, message.npcId!)?.name ?? 'NPC';
    }
    if (message.messageType == TRPGMessageType.npcPlayerMessage) {
      return session.players
              .where((player) => player.playerId == message.playerId)
              .firstOrNull
              ?.displayName ??
          'AI玩家';
    }
    return switch (message.messageType) {
      TRPGMessageType.playerMessage => '玩家',
      TRPGMessageType.diceMessage => '骰子',
      TRPGMessageType.systemMessage => '系统',
      _ => 'NPC',
    };
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.path, required this.state});
  final String? path;
  final CurrentPresentationState state;

  @override
  Widget build(BuildContext context) {
    final image = _image(path);
    return AnimatedSwitcher(
      duration: Duration(
        milliseconds:
            state.quality == PresentationQuality.simple ||
                ThemeScope.maybeOf(context)?.settings.reduceMotion == true ||
                MediaQuery.disableAnimationsOf(context)
            ? 0
            : 550,
      ),
      transitionBuilder: (child, animation) => switch (state.transitionStyle) {
        SceneTransitionStyle.slide => SlideTransition(
          position: Tween(
            begin: const Offset(.08, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        _ => FadeTransition(opacity: animation, child: child),
      },
      child: image == null
          ? Container(
              key: ValueKey(state.backgroundId),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    ThemeTokens.of(context).backgroundPrimary,
                    ThemeTokens.of(context).surfaceElevated,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  state.backgroundId ?? '当前场景',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: ThemeTokens.of(context).textSecondary,
                  ),
                ),
              ),
            )
          : Image(
              key: ValueKey(path),
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: ThemeTokens.of(context).backgroundPrimary),
            ),
    );
  }

  ImageProvider? _image(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('assets/')) {
      return AssetImage(value);
    }
    if (File(value).existsSync()) return FileImage(File(value));
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme ? NetworkImage(value) : null;
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.character, required this.npc});
  final VisibleCharacterState character;
  final TRPGNPCProfile? npc;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (character.position) {
      PortraitPosition.left => Alignment.bottomLeft,
      PortraitPosition.center => Alignment.bottomCenter,
      PortraitPosition.right => Alignment.bottomRight,
    };
    final path =
        npc?.portraitVariants[character.expression.name] ??
        character.portrait ??
        npc?.portrait ??
        npc?.avatar;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 82),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: path == null || path.isEmpty
              ? CircleAvatar(
                  key: ValueKey(
                    '${character.npcId}_${character.expression.name}',
                  ),
                  radius: 52,
                  child: Text(npc?.name.characters.firstOrNull ?? '?'),
                )
              : Image(
                  key: ValueKey('${path}_${character.expression.name}'),
                  image: path.startsWith('assets/')
                      ? AssetImage(path)
                      : FileImage(File(path)) as ImageProvider,
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
      ),
    );
  }
}

class _DialogueBox extends StatelessWidget {
  const _DialogueBox({
    required this.message,
    required this.speaker,
    required this.compact,
    required this.onReplay,
    required this.onSkip,
  });
  final TRPGMessage message;
  final String speaker;
  final bool compact;
  final VoidCallback onReplay, onSkip;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(9),
    padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 6, compact ? 9 : 11),
    decoration: BoxDecoration(
      color: ThemeTokens.of(context).surfacePrimary,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ThemeTokens.of(context).borderSecondary),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                speaker,
                style: TextStyle(
                  color: ThemeTokens.of(context).accentPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                message.content,
                maxLines: compact ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: compact ? 13 : null,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onReplay,
          tooltip: '重新朗读',
          color: ThemeTokens.of(context).textSecondary,
          icon: const Icon(Icons.volume_up_outlined),
        ),
        IconButton(
          onPressed: onSkip,
          tooltip: '跳过演出/语音',
          color: ThemeTokens.of(context).textSecondary,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    ),
  );
}

class _EventOverlay extends StatelessWidget {
  const _EventOverlay({required this.event});
  final PresentationEvent event;

  @override
  Widget build(BuildContext context) {
    final data = switch (event.type) {
      PresentationEventType.diceAnimation => (
        Icons.casino,
        '掷骰',
        '${event.payload['result'] ?? '…'}',
      ),
      PresentationEventType.skillCheckAnimation => (
        Icons.fact_check,
        '${event.payload['skill'] ?? '技能'}检定',
        '${event.payload['total'] ?? event.payload['result'] ?? '…'}',
      ),
      PresentationEventType.damageAnimation => (
        Icons.heart_broken,
        '受到伤害',
        '${event.payload['amount'] ?? ''}',
      ),
      PresentationEventType.healAnimation => (
        Icons.favorite,
        '恢复生命',
        '+${event.payload['amount'] ?? ''}',
      ),
      PresentationEventType.itemGainAnimation => (
        Icons.inventory_2,
        '获得物品',
        '${event.payload['name'] ?? event.payload['itemId'] ?? ''}',
      ),
      PresentationEventType.questUpdateAnimation => (
        Icons.assignment_turned_in,
        '任务更新',
        '${event.payload['title'] ?? event.payload['questId'] ?? ''}',
      ),
      PresentationEventType.combatStart => (Icons.gavel, '战斗开始', '做好准备'),
      PresentationEventType.combatEnd => (Icons.flag, '战斗结束', ''),
      _ => (Icons.auto_awesome, '', ''),
    };
    if (data.$2.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Card(
        color: ThemeTokens.of(context).surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.$1,
                size: 44,
                color: ThemeTokens.of(context).accentPrimary,
              ),
              const SizedBox(height: 8),
              Text(
                data.$2,
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: 18,
                ),
              ),
              if (data.$3.isNotEmpty)
                Text(
                  data.$3,
                  style: TextStyle(
                    color: ThemeTokens.of(context).accentPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color ?? ThemeTokens.of(context).surfaceElevated,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: ThemeTokens.of(context).textPrimary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: ThemeTokens.of(context).textPrimary,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
