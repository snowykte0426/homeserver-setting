import socket
import datetime
import os
import json
import time
import urllib.request

from config import load_config, load_channels
from sender import send_to_all
from messages import boot, ip_change

STATE_PATH = os.path.join(os.path.dirname(__file__), "last_ips.json")

def get_external_ip():
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=10) as r:
            return r.read().decode().strip()
    except Exception:
        return "N/A"

def get_internal_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "N/A"

def load_last_ips():
    if os.path.exists(STATE_PATH):
        try:
            with open(STATE_PATH) as f:
                return json.load(f)
        except Exception:
            pass
    return None

def save_last_ips(external_ip, internal_ip):
    with open(STATE_PATH, "w") as f:
        json.dump({"external": external_ip, "internal": internal_ip}, f)

def run():
    config = load_config()
    channels = load_channels(config)
    if not channels:
        print("DISCORD_WEBHOOK_URL_1이 설정되지 않았습니다. config.env를 확인해주세요.")
        return

    interval = int(config.get("IP_CHECK_INTERVAL", "300"))

    external_ip = get_external_ip()
    internal_ip = get_internal_ip()
    now = datetime.datetime.now()

    print(f"부팅 알림 전송 중... (외부: {external_ip}, 내부: {internal_ip})")
    send_to_all(channels, boot.make_payload, external_ip, internal_ip, now)
    save_last_ips(external_ip, internal_ip)

    print(f"IP 감시 시작 (체크 주기: {interval}초)")
    while True:
        time.sleep(interval)

        new_external = get_external_ip()
        new_internal = get_internal_ip()

        if new_external == "N/A" or new_internal == "N/A":
            print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] IP 조회 실패, 이번 체크 건너뜀")
            continue

        last = load_last_ips()
        old_external = last["external"] if last else external_ip
        old_internal = last["internal"] if last else internal_ip

        if old_external == "N/A" or old_internal == "N/A":
            save_last_ips(new_external, new_internal)
            continue

        if new_external != old_external or new_internal != old_internal:
            now = datetime.datetime.now()
            print(f"IP 변경 감지! 외부: {old_external} -> {new_external}, 내부: {old_internal} -> {new_internal}")
            send_to_all(channels, ip_change.make_payload,
                        old_external, new_external, old_internal, new_internal, now)
            save_last_ips(new_external, new_internal)
        else:
            print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] IP 변경 없음 (외부: {new_external})")

if __name__ == "__main__":
    while True:
        try:
            run()
        except Exception as e:
            print(f"오류 발생, 30초 후 재시작: {e}")
            time.sleep(30)
