import urllib.request
import urllib.error
import json

def send_payload(url, payload):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "DiscordBot (boot-notifier, 1.0)"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"  전송 완료: HTTP {r.status}")
    except urllib.error.HTTPError as e:
        print(f"  전송 실패: HTTP {e.code} - {e.read().decode()}")
    except Exception as e:
        print(f"  전송 실패: {e}")

def send_to_all(channels, make_payload_fn, *args):
    for channel in channels:
        payload = make_payload_fn(channel, *args)
        send_payload(channel["url"], payload)
