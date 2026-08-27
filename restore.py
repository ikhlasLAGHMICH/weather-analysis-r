import json
import sys

log_file = r"C:\Users\daril\.gemini\antigravity-ide\brain\3d53c72a-721a-43c5-965c-db05b4cb9703\.system_generated\logs\transcript_full.jsonl"

for line in open(log_file, "r", encoding="utf-8"):
    try:
        obj = json.loads(line)
        if obj.get("step_index") == 654:
            out = obj.get("content", "")
            if "Output:" in out:
                code_content = out.split("Output:", 1)[1].strip()
                if code_content.startswith("<truncated 1 lines>"):
                    code_content = code_content.replace("<truncated 1 lines>\n", "")
                with open(r"f:\Projets\weather-analysis-r\shiny\app.R", "w", encoding="utf-8") as f:
                    f.write(code_content)
                print("RESTORED!")
    except Exception as e:
        pass
