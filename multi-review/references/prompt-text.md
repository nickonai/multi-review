# Заметки по промпту режима текста

`scripts/build-text-review-pack.sh` сам генерирует
`/tmp/multi-review/prompt.md`. Не подставляй шаблон вручную и не добавляй
склеенный полный артефакт к промптам Codex или Claude.

Сгенерированный промпт — файл-нативный. Он включает:

- абсолютные пути к файлам
- тип контента: `article`, `spec`, `plan`, `prompt`, `legal`, `marketing`
  или `generic`
- фокус ревью, специфичный для типа контента
- правила read-only ревью
- схему отчётности

Codex должен получать только `prompt.md` через `codex exec --cd`.
Claude должен получать только `prompt.md` через `claude --add-dir`.
Gemini может получить `prompt.md` плюс ограниченный `artifact-excerpt.txt`,
потому что он может ненадёжно читать локальные файлы в некоторых окружениях.

Точные команды — в `references/cli-commands.md`.
