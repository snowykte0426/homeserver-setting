import datetime

def make_payload(channel, external_ip, internal_ip, now):
    label = channel.get("label", "")
    title = f"[{label}] 서버 부팅 알림" if label else "서버 부팅 알림"
    embed = {
        "title": title,
        "color": 5793266,
        "fields": [
            {"name": "외부 IP", "value": f"`{external_ip}`", "inline": True},
            {"name": "내부 IP", "value": f"`{internal_ip}`", "inline": True},
            {"name": "부팅 시각", "value": f"`{now.strftime('%Y-%m-%d %H:%M:%S')}`", "inline": False},
        ],
        "timestamp": now.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    }
    footer = channel.get("footer", "")
    if footer:
        embed["footer"] = {"text": footer}
    return {"embeds": [embed]}
