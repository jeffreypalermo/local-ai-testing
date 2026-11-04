Set up the pi and opencode coding agents on this computer, or update them if they're already set up, so they use the Ollama server running on another machine on my local network. Don't change anything on that server.

If pi or opencode already has an `ollama` provider pointing at this server, replace its model list with exactly the models below, using the context sizes below. Remove any model that isn't in the table, in particular `metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL`, the 3-bit Flash-Next build, which `qwen3.8-flash-next:q4_k_m` replaces. If either tool's default is a removed model, set it to `nemotron-3.5-super:120b-a12b`.

## Server
- Ollama at `http://192.168.1.66:11434` (hostname `RTXHP`). OpenAI-compatible API at `http://192.168.1.66:11434/v1`. No API key needed; where a key is required, use `ollama`.
- Check that you can reach it first: `curl http://192.168.1.66:11434/api/tags` should list the models below. If it can't connect, stop and tell me rather than trying workarounds.
- The server loads one model at a time. Switching models takes 30–90 s, and Nemotron Super at its full context can take a couple of minutes to load, so allow long timeouts on the first request.

## Models (use these exact IDs and context sizes)
Each context window is the largest that model handled fully on the server's GPU in testing. The server serves each model at that size automatically, so don't set a larger one.

| Model ID | Context window | Notes |
|---|---|---|
| `nemotron-3.5-super:120b-a12b` | 1048576 | **Default.** Perfect on the coding tests, 1M context |
| `qwen3.8:27b` | 262144 | Perfect on the coding tests; fastest to finish tasks |
| `qwen3.8-flash-next:q4_k_m` | 262144 | Perfect on the coding tests |
| `gpt-oss:120b` | 131072 | Fastest to respond; weaker in opencode |
| `nemotron-3.5-lightning` | 1048576 | Fastest on huge prompts; less reliable |
| `frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs` | 1048576 | Slow; available if needed |
| `gemma4:31b-it-q8_0` | 262144 | Slow; available if needed |

Use 16384 as the max output tokens for every model. All models accept text only and support tool calling.

## 1. Install the tools (skip any that are already installed)
- Node.js 20 or newer.
- pi: `npm install -g @earendil-works/pi-coding-agent` (command: `pi`).
- opencode: `npm install -g opencode-ai` (command: `opencode`).

## 2. Configure pi
Back up any existing file before you change it, and merge into existing settings instead of overwriting unrelated ones.
- `~/.pi/agent/models.json`: add a provider `ollama` with `"baseUrl": "http://192.168.1.66:11434/v1"`, `"api": "openai-completions"` and `"apiKey": "ollama"`. Give it one entry per model above: `{ "id": "<model ID>", "contextWindow": <context>, "maxTokens": 16384, "input": ["text"] }`.
- `~/.pi/agent/settings.json`: set `"defaultProvider": "ollama"` and `"defaultModel": "nemotron-3.5-super:120b-a12b"`. On Windows, also set `"defaultTools": ["read", "powershell", "edit", "write"]`, because pi's bash tool needs Bash.
- On Windows, `~` means `%USERPROFILE%`.

## 3. Configure opencode
Edit the global config, `~/.config/opencode/opencode.json` (or `opencode.jsonc` if that's the one that exists). Back it up first and keep the settings that are already there.
- Set `"model": "ollama/nemotron-3.5-super:120b-a12b"`.
- Add this provider:
  ```json
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (RTXHP)",
      "options": { "baseURL": "http://192.168.1.66:11434/v1" },
      "models": {
        "<model ID>": { "name": "<model ID>", "tool_call": true, "limit": { "context": <context>, "output": 16384 } }
      }
    }
  }
  ```
  Add one `models` entry per model in the table.

## 4. Verify
In an empty temporary folder:
- `pi -p "Create hello.py that prints hi, run it, and tell me the output."`: it should create and run the file using the default model.
- `opencode run "Reply with exactly: OPENCODE_OK"`: the first run can take several minutes while opencode installs its provider package; later runs take seconds. Use a 10-minute timeout.
- `pi --list-models` (or pi's model picker) and `opencode models` should both show exactly the 7 `ollama` models in the table, with the context sizes above, and no 3-bit Flash-Next.

Then report what you installed, which files you changed (with their backup paths), and the verification output.
