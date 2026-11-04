# pi prompts for running the tests from another computer

pi on the remote computer uses the same Ollama server that the tests use, and that server holds one model at a time. So pi only **starts** the run in its own window and then stops. If pi kept checking on the run, every check would swap its own model back in and skew the timings. Paste prompt 1 to start the run. Paste prompt 2 when the run window says `done`, which takes roughly 2½–4 hours.

## Prompt 1: set up and start the run

```
Set up and start my local-AI coding tests on this Windows computer. Run each command below with the powershell tool, one step at a time, and stop to tell me if any step fails. Don't change my pi or opencode configs, and don't install anything without asking me.

1. Check prerequisites: git --version; node --version; dotnet --list-sdks; python --version
   I need git, Node 20 or newer, a .NET 10.x SDK, and Python 3.11 or newer. If any is missing or too old, stop and tell me which ones.

2. Get the repo:
   if (Test-Path C:\src\local-ai-testing) { git -C C:\src\local-ai-testing pull } else { git clone https://github.com/jeffreypalermo/local-ai-testing.git C:\src\local-ai-testing }

3. Check the server: (Invoke-RestMethod http://192.168.1.66:11434/api/tags).models.name
   It should list nemotron-3.5-super:120b-a12b, qwen3.8:27b, gpt-oss:120b, metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL and nemotron-3.5-lightning.

4. Install the test copies of pi and opencode. They go in their own folder and don't touch my setup:
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\src\local-ai-testing\install-harnesses.ps1
   It must print "pi: True" and an opencode path ending in opencode.exe with version 1.19.5.

5. Start the full run in its own window, then stop:
   Start-Process powershell -WorkingDirectory C:\src\local-ai-testing -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','C:\src\local-ai-testing\remote-eval.ps1'

After step 5, don't run anything else and don't check on the run; it shares the model server with you. Tell me it started and that results will be in C:\src\local-ai-testing\results-<this computer's name, lowercase>\.
```

## Prompt 2: report the results (after the run window says `done`)

```
My local-AI coding test run has finished. Read these files with the read tool:
- C:\src\local-ai-testing\README.md (the "Results" table has the server's own results)
- The summary.txt and agent-results.csv files in the results-* folder under C:\src\local-ai-testing

Then report:
1. A table per model: tasks passed within 15 minutes in pi and in opencode, total minutes, and time to first token at 4K, 32K and 128K.
2. How each model compares with the README's results table. Time to first token here includes the network round trip, so expect it to be a little higher.
3. Every failed or timed-out task, with the failing check from the detail column of agent-results.csv.
Don't run any commands and don't change any files.
```
