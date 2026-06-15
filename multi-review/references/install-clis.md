# Установка внешних CLI

Скиллу нужен **хотя бы один** из трёх внешних AI-CLI: `codex`, `gemini` или
`claude`. Чем больше установлено — тем выше покрытие ревью. Если у пользователя
нет ни одного, предложи установить любой из них по инструкции ниже.

> Для способов через **npm** нужен [Node.js 18+](https://nodejs.org/).
> Команды установки и авторизации часто меняются — при сомнении сверяйся с
> официальной документацией (ссылки в конце каждого раздела).

## Проверка, что уже установлено

```bash
which codex  2>/dev/null && echo "codex: есть"  || echo "codex: нет"
which gemini 2>/dev/null && echo "gemini: есть" || echo "gemini: нет"
which claude 2>/dev/null && echo "claude: есть" || echo "claude: нет"
```

## Codex CLI (OpenAI)

Установка (любой способ):

```bash
# Официальный установщик (macOS / Linux):
curl -fsSL https://chatgpt.com/codex/install.sh | sh

# npm:
npm install -g @openai/codex

# Homebrew:
brew install codex
```

Авторизация: запусти `codex` — при первом запуске предложат войти через
аккаунт ChatGPT или ввести API-ключ.

Документация: <https://developers.openai.com/codex/>

## Gemini CLI (Google)

```bash
# npm:
npm install -g @google/gemini-cli

# Разовый запуск без установки:
npx https://github.com/google-gemini/gemini-cli
```

Авторизация: запусти `gemini` и войди в аккаунт Google (есть бесплатный тариф),
либо задай ключ через переменную `GEMINI_API_KEY`.

Документация: <https://geminicli.com/docs/>

## Claude Code CLI (Anthropic)

```bash
# Нативный установщик (macOS / Linux / WSL):
curl -fsSL https://claude.ai/install.sh | bash

# Windows PowerShell:
irm https://claude.ai/install.ps1 | iex

# npm:
npm install -g @anthropic-ai/claude-code

# Homebrew:
brew install --cask claude-code
```

Авторизация: запусти `claude` и войди через браузер. Требуется подписка Claude
(Pro / Max / Team / Enterprise) или доступ через API-провайдера; бесплатный
тариф Claude.ai доступа к Claude Code не даёт.

Документация: <https://code.claude.com/docs/>

## После установки

Проверь, что бинарь виден в PATH (`which <cli>`), и что он авторизован (запусти
CLI один раз). Затем скилл `multi-review` подхватит доступные CLI автоматически —
см. `references/cli-commands.md`.
