# Local AI coding-model testing

Which local models are worth using for agentic coding (with the [pi](https://pi.dev) and [opencode](https://opencode.ai) harnesses) on a single Ollama box. The evaluation ran on 2026-11-03 and 2026-11-04.

## Setup

- **Hardware:** RTX Spark N1X laptop (Windows 11 ARM64), unified memory with 109.7 GiB available to the GPU after a 2026-11-03 firmware update. The machine runs only Ollama.
- **Server:** Ollama 0.40.14 with `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0` and `OLLAMA_MAX_LOADED_MODELS=1`.
- **Harnesses:** pi 1.5.0 and opencode 1.19.5, pointed at Ollama's OpenAI-compatible `/v1` endpoint. All tests ran fully offline.

## Tests

1. **Coding gate** ([agent-eval.ps1](agent-eval.ps1), tasks built by [make-agent-tasks.ps1](make-agent-tasks.ps1)). The agent works in a real repo until the tests pass. Grading restores the original tests and runs them, so editing the tests doesn't help. A task only counts if it passes within **15 minutes**.
   - `cs-bugfix`: two bugs in a C# billing library (8 checks)
   - `cs-feature`: implement an RFC 4180 CSV parser in C# (11 checks)
   - `py-bugfix`: four bugs in a Python paginator (6 tests)
   - `py-feature`: an O(1) TTL + LRU cache in Python, with a performance test (7 tests)
2. **Context** ([bench.ps1](bench.ps1)). A needle-in-a-haystack test at 96% of the context window. It passes only if the model finds the needle, the prompt wasn't truncated, and the model ran 100% on the GPU. Steps: 1M, 768K, 500K, 262K, 128K and 64K, capped at each model's native limit.
3. **Time to first token** ([ttft.ps1](ttft.ps1)). Streamed requests with about 4K, 32K and 128K-token prompts. The model is loaded first, and each prompt starts with unique text so the prompt cache can't help.

[narrow.ps1](narrow.ps1) runs all three: the pi gate first, then a context test and opencode for models that pass, then the timing test.

## Results

| Model | pi | opencode | Max context (on GPU) | First token at 4K / 32K / 128K | Generation speed | Size loaded |
|---|---|---|---|---|---|---|
| **nemotron-3.5-super:120b-a12b** | **4/4** | **4/4** | **1M** | 8.6 s / 65 s / 272 s | 37 tok/s | 85.8 GB |
| **qwen3.8:27b** | **4/4** | **4/4** | 262K | 6.6 s / 56 s / 321 s | 24 tok/s | 18.6 GB |
| metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL | 4/4 | 4/4 | 262K | 5.5 s / 51 s / 212 s | 31 tok/s | 58.6 GB |
| gpt-oss:120b | 4/4 | 3/4 | 128K | 2.2 s / 23 s / not run* | 37 tok/s | 60.2 GB |
| nemotron-3.5-lightning | 2/4, then 3/4 on retest | 2/4, then 4/4 on a second run | 1M | 1.3 s / 15 s / 73 s | 96 tok/s | 26.6 GB |
| frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs | 3/4 | not run | 1M | not run | 23 tok/s | 86.6 GB |
| gemma4:31b-it-q8_0 | 3/4 | not run | 262K | not run | 8 tok/s | 33.5 GB |

\*A 128K prompt plus the answer doesn't fit in gpt-oss's 128K limit. Its long-context test read prompts at about 840 tok/s at 128K, which suggests a first token in roughly 150 s.

Generation speed is for a short prompt; it drops as the context fills. Raw data: [agent-results.csv](agent-results.csv), [agent-results-lightning-retest.csv](agent-results-lightning-retest.csv), `ctx-*.csv` and [ttft-results.csv](ttft-results.csv).

**Dropped:**
- **qwen3-coder-next:q8_0** and **devstral-2:123b**: 2/4 in pi.
- **qwen3-coder:30b**: kept sending tool calls as raw text.
- **nemotron-3-nano**: a weaker coder than Lightning at the same context.
- **gemma4:31b bf16**: too slow to finish tasks in time, so it was replaced by q8.
- **qwen2.5-14b-1m**: dropped before testing as outdated.

**Out of reach on 110 GB:** Kimi K2 (210 GB or more). DeepSeek V4 and Qwen 3.8 Flash-Next fit only as 2–3-bit community builds.

## Recommendations

- **Best overall, any context: Qwen 3.8 27B.** 8/8, the fastest task times among the models that passed everything, and the smallest footprint. It's slow to start answering on big prompts.
- **Best when you need a big context: Nemotron 3.5 Super.** 8/8 at 1M tokens, fully on the GPU. This is the default in the daily setup.
- **Snappiest: gpt-oss-120b.** The quickest to respond, but it missed one bug in opencode.
- **Fastest on huge prompts: Nemotron 3.5 Lightning.** By far the fastest at reading prompts and generating, but it sometimes gets stuck on the CSV parser task.

All of these rest on 8 runs per model, so a difference of a minute or two in task time is within run-to-run variation.

## Daily setup

- [setup-daily.ps1](setup-daily.ps1) sets Ollama's default context to 1M, which Ollama caps at each model's own limit.
  - It runs the Ollama app's server, which has "Expose to network" on.
  - It writes pi and opencode configs with 7 models, defaulting to Nemotron Super.
- [remote-setup-prompt.md](remote-setup-prompt.md) is a prompt for setting up pi and opencode on another computer to use this server over the LAN.
- [remote-csv-task-setup.md](remote-csv-task-setup.md) is a prompt for recreating the CSV-parser task on another computer, so you can run it by hand.

## Files

- **Main scripts:** [narrow.ps1](narrow.ps1) is the pipeline. [agent-eval.ps1](agent-eval.ps1), [bench.ps1](bench.ps1) and [ttft.ps1](ttft.ps1) are the three tests.
- **Task sources:** [agent-tasks/](agent-tasks/) holds each task's `repo/` (starting state), `grade/` (canonical tests) and `task.txt` (the prompt).
- **Earlier or one-off scripts:** run-all.ps1, start.ps1, pull-all.ps1, install-harnesses.ps1, coding-eval.ps1 (the first single-prompt eval, since replaced), and small helpers such as after-narrow.ps1, gptoss-*.ps1 and smoke-*.ps1.
- **Logs and outputs:** run-all.log, agent-*.log, ctx-*.log, ttft.log and ollama-serve.log, plus the `*.txt` reports from the setup scripts.

The scripts assume Windows PowerShell 5.1 and put their working folders under `%LOCALAPPDATA%\llm-eval`. Short paths there avoid MSBuild's path-length limit.
