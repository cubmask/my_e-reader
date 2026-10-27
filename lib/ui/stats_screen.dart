import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/reading_stats.dart';
import '../reader/reader_services.dart';

/// Today against the daily goal, the streak, the last two weeks and the
/// books finished this year.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.services, required this.books});

  final ReaderServices services;
  final List<Book> books;

  Future<void> _editGoal(BuildContext context, ReadingStats stats) async {
    var minutes = stats.goalMinutes.toDouble();
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Daily reading goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatMinutes(minutes)),
              Slider(
                min: 5,
                max: 180,
                divisions: 35,
                value: minutes,
                onChanged: (v) => setState(() => minutes = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, minutes.round()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) stats.setGoal(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final stats = services.stats;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: ListenableBuilder(
        listenable: stats,
        builder: (context, _) {
          final now = DateTime.now();
          final today = stats.secondsOn(dayKey(now)) / 60;
          final goal = stats.goalMinutes;
          final days = stats.lastDays(14);
          final week = stats.secondsBetween(
            DateTime(now.year, now.month, now.day - 6),
            now,
          );
          final year = stats.secondsBetween(DateTime(now.year), now);
          final byId = {for (final b in books) b.driveFileId: b};
          final finished =
              stats.finished.entries
                  .where((e) => e.value.year == now.year)
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
          final streak = stats.streak();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: (today / goal).clamp(0, 1),
                          strokeWidth: 10,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                        Center(
                          child: Text(
                            '${today.floor()}\nof $goal min',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          today >= goal
                              ? 'Goal reached today'
                              : '${formatMinutes(goal - today)} to go today',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          streak == 0
                              ? 'Read today to start a streak'
                              : '$streak-day streak',
                        ),
                        TextButton(
                          onPressed: () => _editGoal(context, stats),
                          child: const Text('Change goal'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text('Last two weeks', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _DayBars(seconds: days, goalMinutes: goal, today: now),
              const SizedBox(height: 24),
              Wrap(
                spacing: 32,
                runSpacing: 16,
                children: [
                  _Figure('This week', formatMinutes(week / 60)),
                  _Figure('This year', formatMinutes(year / 60)),
                  _Figure('Finished this year', '${finished.length}'),
                ],
              ),
              if (finished.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Finished', style: theme.textTheme.titleMedium),
                for (final e in finished)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                      byId[e.key] == null
                          ? 'A book no longer in the library'
                          : services.meta.titleOf(byId[e.key]!),
                    ),
                    subtitle: Text(
                      MaterialLocalizations.of(context)
                          .formatMediumDate(e.value),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineSmall),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// One bar per day, with the goal as a line.
class _DayBars extends StatelessWidget {
  const _DayBars({
    required this.seconds,
    required this.goalMinutes,
    required this.today,
  });

  final List<int> seconds;
  final int goalMinutes;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = [for (final s in seconds) s / 60];
    final top = [
      goalMinutes.toDouble(),
      ...minutes,
    ].reduce((a, b) => a > b ? a : b);
    const height = 120.0;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      height: height + 24,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: height - height * goalMinutes / top,
            child: Container(height: 1, color: scheme.outline),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, m) in minutes.indexed)
                Expanded(
                  child: Tooltip(
                    message: formatMinutes(m),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: (height * m / top).clamp(2, height),
                          decoration: BoxDecoration(
                            color: m >= goalMinutes
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          letters[DateTime(
                                today.year,
                                today.month,
                                today.day - (minutes.length - 1 - i),
                              ).weekday -
                              1],
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small line for Home: today's reading against the goal, and the streak.
class StatsChip extends StatelessWidget {
  const StatsChip({super.key, required this.services, required this.books});

  final ReaderServices services;
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final stats = services.stats;
    return ListenableBuilder(
      listenable: stats,
      builder: (context, _) {
        final today = (stats.secondsOn(dayKey(DateTime.now())) / 60).floor();
        final streak = stats.streak();
        return ActionChip(
          avatar: Icon(
            today >= stats.goalMinutes
                ? Icons.emoji_events_outlined
                : Icons.timer_outlined,
          ),
          label: Text(
            'Today $today of ${stats.goalMinutes} min'
            '${streak > 1 ? ' · $streak-day streak' : ''}',
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StatsScreen(services: services, books: books),
            ),
          ),
        );
      },
    );
  }
}
