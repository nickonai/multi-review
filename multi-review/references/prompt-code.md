# Заметки по промпту режима кода

`scripts/build-code-review-pack.sh` сам генерирует
`/tmp/multi-review/prompt.md`. Не подставляй шаблон вручную и не добавляй
полный diff к промптам Codex или Claude.

Сгенерированный промпт — репозиторий-нативный. Он включает:

- корень проекта
- режим охвата: `branch`, `branch-with-uncommitted` или `working-tree`
- базовый ref
- изменённые файлы
- применимые выдержки из `AGENTS.md` / `CLAUDE.md` / `GEMINI.md`
- правила read-only ревью
- схему отчётности

Codex должен получать только `prompt.md` через `codex exec --cd`.
Claude должен получать только `prompt.md` через `claude --add-dir`.
Gemini может получить `prompt.md` плюс `diff-trimmed.txt`, когда он есть;
иначе — список изменённых файлов как вспомогательный материал.

Точные команды — в `references/cli-commands.md`.
