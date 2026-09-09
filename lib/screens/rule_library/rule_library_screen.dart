import 'package:flutter/material.dart';

import '../../app/skins/skin_icon.dart';
import '../../models/rule_reference.dart';
import '../../services/trpg/rule_compendium.dart';

class RuleLibraryScreen extends StatefulWidget {
  const RuleLibraryScreen({
    this.initialSystem = RuleReferenceSystem.dnd5e,
    super.key,
  });

  final RuleReferenceSystem initialSystem;

  @override
  State<RuleLibraryScreen> createState() => _RuleLibraryScreenState();
}

class _RuleLibraryScreenState extends State<RuleLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  String? _category;

  RuleReferenceSystem get _system => RuleReferenceSystem.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: RuleReferenceSystem.values.length,
      initialIndex: widget.initialSystem.index,
      vsync: this,
    )..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_handleTabChange)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabs.indexIsChanging) return;
    setState(() => _category = null);
  }

  @override
  Widget build(BuildContext context) {
    final system = _system;
    final categories = RuleCompendium.categoriesFor(system);
    final entries = RuleCompendium.search(
      system: system,
      query: _search.text,
      category: _category,
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('跑团规则资料库'),
            Text('检定、建卡与主持速查', style: TextStyle(fontSize: 12)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'D&D 5E'),
            Tab(text: 'COC 7版'),
            Tab(text: '快速开团'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: .72,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SkinIcon(
                          _systemIcon(system),
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              system.label,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              system.description,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${RuleCompendium.search(system: system).length} 条核心速查',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                key: const ValueKey('rule-library-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索规则、技能、检定或关键词',
                  prefixIcon: const SkinIcon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const SkinIcon(Icons.close),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                key: const ValueKey('rule-library-categories'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final category in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? _EmptySearch(query: _search.text)
                  : ListView.separated(
                      key: const ValueKey('rule-library-results'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _RuleEntryCard(
                        entry: entries[index],
                        initiallyExpanded: entries.length == 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _systemIcon(RuleReferenceSystem system) => switch (system) {
    RuleReferenceSystem.dnd5e => Icons.shield_outlined,
    RuleReferenceSystem.coc7 => Icons.visibility_outlined,
    RuleReferenceSystem.quickStart => Icons.rocket_launch_outlined,
  };
}

class _RuleEntryCard extends StatelessWidget {
  const _RuleEntryCard({required this.entry, required this.initiallyExpanded});

  final RuleReferenceEntry entry;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('rule-entry-${entry.id}'),
        initiallyExpanded: initiallyExpanded,
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: .72),
          child: SkinIcon(
            _categoryIcon(entry.category),
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(entry.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${entry.category} · ${entry.summary}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          for (final point in entry.points)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
          if (entry.example case final example?) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: .55,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
              child: Text('示例：$example'),
            ),
          ],
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
    '核心检定' => Icons.casino_outlined,
    '角色创建' => Icons.person_add_alt_outlined,
    '战斗' => Icons.sports_martial_arts_outlined,
    '法术' => Icons.auto_fix_high_outlined,
    '冒险' => Icons.map_outlined,
    '调查' => Icons.search_outlined,
    '理智' => Icons.psychology_outlined,
    '追逐' => Icons.directions_run_outlined,
    '开团准备' => Icons.fact_check_outlined,
    '开场' => Icons.theater_comedy_outlined,
    '主持流程' => Icons.account_tree_outlined,
    '玩家输入' => Icons.edit_note_outlined,
    '稳定性' => Icons.health_and_safety_outlined,
    _ => Icons.menu_book_outlined,
  };
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkinIcon(
            Icons.search_off_outlined,
            size: 54,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('没有找到“$query”', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('换一个关键词，或者选择“全部”分类再试试。'),
        ],
      ),
    ),
  );
}
