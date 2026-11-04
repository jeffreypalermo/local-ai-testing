Run my local-AI coding tests from this computer against the Ollama server on my network, then report the results. The models run on the server; the coding agents, builds and tests run here.

## Context
- Test repo: https://github.com/jeffreypalermo/local-ai-testing. Its README describes the tests and has the server's own results to compare against.
- Ollama server: `http://192.168.1.66:11434`. Don't change anything on the server.
- I already have pi configured on this computer for that server. **Leave my pi and opencode configs alone.** The test scripts install their own pinned copies (pi 1.5.0 and opencode 1.19.5) under `%LOCALAPPDATA%\llm-eval` with a separate config folder.
- The scripts are Windows PowerShell 5.1. If this computer isn't Windows, stop and tell me rather than porting them.

## 1. Prerequisites (install only what's missing, with winget)
- Git (`Git.Git`)
- Node.js 20 or newer (`OpenJS.NodeJS.LTS`)
- .NET 10 SDK (`Microsoft.DotNet.SDK.10`)
- Python 3.11 or newer (`Python.Python.3.13`), with `python` on PATH

Tell me before accepting any license or admin prompt you weren't expecting.

## 2. Get the repo and the test harnesses
- Clone the repo to a short path, `C:\src\local-ai-testing`. Deep paths break MSBuild.
- Check the server: `Invoke-RestMethod http://192.168.1.66:11434/api/tags` should list the models. If it can't connect, stop and tell me.
- In the repo, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install-harnesses.ps1`. It should report `pi: True` and an opencode path with version 1.19.5.

## 3. Smoke test (about 3 minutes)
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\remote-eval.ps1 -Models gpt-oss:120b -Tasks py-bugfix -SkipTtft
```
The summary should show `1/1` for both pi and opencode. If it doesn't, read `results-<computer name>\agent-gpt-oss_120b.log` and the agent logs under `%LOCALAPPDATA%\llm-eval\agent\`, and tell me what failed before going further.

## 4. Full run (roughly 2½–4 hours)
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\remote-eval.ps1
```
- It tests 5 models (Nemotron 3.5 Super, Qwen 3.8 27B, gpt-oss-120b, Qwen 3.8 Flash-Next and Nemotron 3.5 Lightning). Each model gets the 4 coding tasks in pi and in opencode (15 minutes max per task), then a time-to-first-token test at 4K, 32K and 128K-token prompts.
- Run it in the background, or somewhere it won't be killed when your own session's command timeout hits. Check on it periodically through `results-<computer name>\run.log`. Don't poll faster than every few minutes.
- It's restartable: if it stops, run the same command again and finished work is skipped.
- The server loads one model at a time, so anyone else using it during the run slows the timings. If `run.log` shows a task far slower than its server-side time in the README, mention it.
- Don't add `-Context` (the long-context test). It takes hours per model and measures only the server, which was already tested.

## 5. Report back
- Show `results-<computer name>\summary.txt`, and compare each model with the README's results table: tasks passed within 15 minutes per harness, and time to first token.
- Explain any differences. Time to first token includes the network round trip here, so expect it to be slightly higher.
- List any task that failed, with the failing check from the `detail` column of `agent-results.csv`.
- Don't commit or push anything. Ask me first if you think the results should go into the repo.
