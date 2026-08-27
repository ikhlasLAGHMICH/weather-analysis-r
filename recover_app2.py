import json
import sys
import re

log_file = r"C:\Users\daril\.gemini\antigravity-ide\brain\3d53c72a-721a-43c5-965c-db05b4cb9703\.system_generated\logs\transcript_full.jsonl"
file_lines = {}

pattern = re.compile(r"^(\d+):\s(.*)$")

with open(log_file, "r", encoding="utf-8") as f:
    for line in f:
        try:
            obj = json.loads(line)
            content = obj.get("content", "")
            if "The following code has been modified to include a line number" in content and "shiny/app.R" in content:
                # Parse the lines
                lines = content.split("\n")
                for l in lines:
                    match = pattern.match(l)
                    if match:
                        num = int(match.group(1))
                        text = match.group(2)
                        file_lines[num] = text
        except Exception as e:
            pass

print(f"Recovered {len(file_lines)} lines!")

if len(file_lines) > 0:
    max_line = max(file_lines.keys())
    with open(r"f:\Projets\weather-analysis-r\shiny\app.R", "w", encoding="utf-8") as out:
        for i in range(1, max_line + 1):
            out.write(file_lines.get(i, "") + "\n")
    print(f"Saved to app.R up to line {max_line}!")
