import os

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.env")

def load_config():
    config = {}
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, val = line.split("=", 1)
                    config[key.strip()] = val.strip().strip('"').strip("'")
    return config

def load_channels(config):
    channels = []
    i = 1
    while True:
        url = config.get(f"DISCORD_WEBHOOK_URL_{i}", "").strip()
        if not url:
            break
        channels.append({
            "url": url,
            "label": config.get(f"DISCORD_WEBHOOK_LABEL_{i}", "").strip(),
            "footer": config.get(f"DISCORD_WEBHOOK_FOOTER_{i}", "").strip(),
        })
        i += 1
    if not channels:
        url = os.environ.get("DISCORD_WEBHOOK_URL", "")
        if url:
            channels.append({"url": url, "label": "", "footer": ""})
    return channels
