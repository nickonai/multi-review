# Команды CLI

Внешние AI-CLI, которые вызывает `multi-review`. Базовый путь — лёгкий:
ревьюеры получают сгенерированный промпт с локальными путями и сами инспектируют
файлы. Не вставляй полный diff или склеенный полный артефакт в промпты Codex или
Claude.

> **Без переменных окружения.** Скрипты не читают конфигурацию из env. Всё, что
> нужно, передаётся позиционными аргументами или флагами. Рабочая директория
> всегда `/tmp/multi-review`, таймаут на ревьюера всегда 900 секунд.

В примерах ниже путь к скиллу — `~/.claude/skills/multi-review`. Подставь тот
путь, куда скилл установлен у тебя (например `~/.agents/skills/multi-review` для
Codex/Gemini/Cursor).

## Проверка доступности

```bash
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
which codex 2>/dev/null && echo "codex: available" || echo "codex: not found"
which gemini 2>/dev/null && echo "gemini: available" || echo "gemini: not found"
which claude 2>/dev/null && echo "claude: available" || echo "claude: not found"
```

Если `which claude` не находит бинарь, проверь также
`$HOME/.local/bin/claude` прежде чем отмечать Claude как недоступный.

## Сборка пакета ревью

Оба билдера пишут готовый к использованию `/tmp/multi-review/prompt.md`.

### Режим кода

Запускается из корня git-репозитория. Базовый ref — опциональный аргумент
(по умолчанию `main`):

```bash
# сравнить с main (значение по умолчанию):
~/.claude/skills/multi-review/scripts/build-code-review-pack.sh

# сравнить с другой веткой:
~/.claude/skills/multi-review/scripts/build-code-review-pack.sh develop
```

Режим охвата (scope) определяется автоматически: `branch`,
`branch-with-uncommitted` или `working-tree`. Выходные файлы включают
`mode.txt`, `project_root.txt`, `context_root.txt`, `scope_mode.txt`,
`base.txt`, `changed_files.txt`, `agents_excerpts.md`, `diff_size.txt` и
`prompt.md`. Если охваченный diff большой (> 50 КБ), билдер также пишет
`diff-trimmed.txt` как опциональный вспомогательный вход для Gemini. Перед
выходом он удаляет временный полный diff.

### Режим текста

Первый аргумент — тип контента, дальше — один или несколько путей к файлам:

```bash
~/.claude/skills/multi-review/scripts/build-text-review-pack.sh spec \
  /abs/path/to/spec.md /abs/path/to/related-notes.md
```

Тип контента — одно из: `article`, `spec`, `plan`, `prompt`, `legal`,
`marketing`, `generic`. Выходные файлы включают `mode.txt`, `content_type.txt`,
`files.txt`, `context_root.txt`, `prompt.md`, `artifact_size.txt` и
`artifact-excerpt.txt`.

Текстовый билдер не создаёт склеенный полный артефакт. `artifact-excerpt.txt`
ограничен 220 строками на файл и существует только как вспомогательный материал
для CLI, которые могут ненадёжно читать локальные файлы.

## Форма запуска

Каждый ревьюер запускается отдельным вызовом
`scripts/run-external-reviewer.sh`. Никогда не объединяй ревьюеров в одну
shell-строку.

```
run-external-reviewer.sh <имя-ревьюера> --cwd <директория> [--stdin <файл>] -- <команда...>
```

- Claude Code: один вызов инструмента `Bash` на ревьюера с
  `run_in_background: true` и `timeout: 900000`.
- Codex / shell: один shell-вызов на ревьюера; если поддерживаются фоновые
  задачи — запускай их независимо и дождись всех.

Обёртка пишет `<reviewer>.out`, `<reviewer>.status` и `<reviewer>.meta` в
`/tmp/multi-review` и завершается успешно, чтобы один упавший ревьюер не отменил
весь запуск. Флаг `--cwd` задаёт локальный корень контекста, из которого
стартует CLI.

## Codex

Используй `codex exec --cd`, чтобы Codex мог нативно инспектировать репозиторий
или директорию документа. `--skip-git-repo-check` сохраняет работу
текстовых ревью вне git-репозитория.

```bash
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH" && \
CONTEXT_ROOT=$(cat /tmp/multi-review/context_root.txt) && \
~/.claude/skills/multi-review/scripts/run-external-reviewer.sh codex --cwd "$CONTEXT_ROOT" -- \
  codex exec --skip-git-repo-check --cd "$CONTEXT_ROOT" "$(cat /tmp/multi-review/prompt.md)"
```

## Claude

Используй `--add-dir`, чтобы дать доступ на чтение к корню контекста.

```bash
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH" && \
CONTEXT_ROOT=$(cat /tmp/multi-review/context_root.txt) && \
~/.claude/skills/multi-review/scripts/run-external-reviewer.sh claude --cwd "$CONTEXT_ROOT" -- \
  claude --add-dir "$CONTEXT_ROOT" -p "$(cat /tmp/multi-review/prompt.md)"
```

## Gemini

Запускай Gemini из того же корня контекста со сгенерированным промптом плюс
только небольшим вспомогательным блоком (через stdin). По умолчанию не отправляй
полный diff или полный артефакт.

Режим кода использует `diff-trimmed.txt`, когда он есть; иначе отправляет только
список изменённых файлов. Режим текста отправляет `artifact-excerpt.txt`.

```bash
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH" && \
CONTEXT_ROOT=$(cat /tmp/multi-review/context_root.txt) && \
MODE=$(cat /tmp/multi-review/mode.txt) && \
{
  cat /tmp/multi-review/prompt.md
  echo
  echo "--- SUPPLEMENTAL REVIEW MATERIAL ---"
  if [ "$MODE" = "code" ]; then
    if [ -f /tmp/multi-review/diff-trimmed.txt ]; then
      cat /tmp/multi-review/diff-trimmed.txt
    else
      echo "No trimmed diff was produced. Changed files:"
      cat /tmp/multi-review/changed_files.txt
    fi
  else
    cat /tmp/multi-review/artifact-excerpt.txt
  fi
} > /tmp/multi-review/gemini-input.md && \
~/.claude/skills/multi-review/scripts/run-external-reviewer.sh gemini --cwd "$CONTEXT_ROOT" --stdin /tmp/multi-review/gemini-input.md -- \
  gemini -p "Follow the instructions from stdin. Use the current working directory as the context root. Output findings only." --approval-mode plan -o text
```

## Обработка ошибок

| Ошибка | Действие |
| --- | --- |
| CLI не найден | Пропустить и записать: `[tool] not installed` |
| ошибка авторизации | Пропустить и записать: `[tool] authentication failed` |
| таймаут | Обёртка записывает `timeout`, затраченное время и частичный вывод |
| отсутствует stdin-файл | Обёртка записывает `stdin_missing`; пересобери входной файл и перезапусти |
| пустой вывод | Записать: `[tool] returned no findings` |
| ненулевой код выхода | Захватить сводку stderr и продолжить |

Сбои внешних ревьюеров не блокирующие. Если успешных ревьюеров ноль —
остановись и сообщи пользователю.

## Очистка

После финального отчёта:

```bash
rm -rf /tmp/multi-review/
```

Очистка — best-effort. Билдеры пересоздают директорию с нуля при следующем
запуске.
