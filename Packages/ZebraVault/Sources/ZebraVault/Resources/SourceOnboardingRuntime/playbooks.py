def parse_playbook_markdown(path, fallback):
    result = {
        "id": "",
        "version": "",
        "sourceID": "",
        "initialStepID": "",
        "steps": [],
        "sections": {},
    }
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return dict(fallback)
    body = text
    if text.startswith("---"):
        marker = text.find("\n---", 3)
        if marker >= 0:
            frontmatter = text[3:marker].strip().splitlines()
            body = text[marker + 4:]
            current_list = None
            for raw in frontmatter:
                if not raw.strip():
                    continue
                if raw.startswith("  - ") and current_list == "steps":
                    result["steps"].append(raw[4:].strip())
                    continue
                current_list = None
                if ":" not in raw:
                    continue
                key, value = raw.split(":", 1)
                key = key.strip()
                value = value.strip()
                if key == "steps":
                    current_list = "steps"
                elif key in result and isinstance(result[key], str):
                    result[key] = value
    current_step = None
    buffer = []
    for line in body.splitlines():
        if line.startswith("## Step: "):
            if current_step:
                result["sections"][current_step] = "\n".join(buffer).strip()
            current_step = line[len("## Step: "):].strip()
            buffer = []
        elif current_step:
            buffer.append(line)
    if current_step:
        result["sections"][current_step] = "\n".join(buffer).strip()
    for key in ("id", "version", "sourceID", "initialStepID"):
        if not result.get(key):
            result[key] = fallback[key]
    if not result.get("steps"):
        result["steps"] = list(fallback["steps"])
    return result
