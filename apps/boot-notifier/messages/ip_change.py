import datetime

def make_payload(channel, old_external, new_external, old_internal, new_internal, now):
    label = channel.get("label", "")
    title = f"[{label}] IP 변경 감지" if label else "IP 변경 감지"
    fields = []
    if old_external != new_external:
        fields.append({
            "name": "외부 IP 변경",
            "value": f"`{old_external}` -> `{new_external}`",
            "inline": False,
        })
    if old_internal != new_internal:
        fields.append({
            "name": "내부 IP 변경",
            "value": f"`{old_internal}` -> `{new_internal}`",
            "inline": False,
        })
    fields.append({
        "name": "감지 시각",
        "value": f"`{now.strftime('%Y-%m-%d %H:%M:%S')}`",
        "inline": False,
    })
    embed = {
        "title": title,
        "color": 15158332,
        "fields": fields,
        "timestamp": now.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    }
    footer = channel.get("footer", "")
    if footer:
        embed["footer"] = {"text": footer}
    return {"embeds": [embed]}
