# Raw single-connection download speed, for comparison with Ollama pulls.
curl.exe -sS -L -o NUL -w "cloudflare: %{size_download} bytes at %{speed_download} B/s`n" "https://speed.cloudflare.com/__down?bytes=500000000"
