"""Simulates the fill-level sensors of six trash bins (smart extension, Stage 2 Part D).

A real sensor (ultrasonic distance sensor + ESP32 + LoRa module) measures the distance from
the lid to the rubbish once an hour and sends a few bytes over LoRaWAN; the network server
forwards them to our API as JSON. Here this script plays the sensors:

    python3 simulate_sensor.py                    # 8 rounds, one every 2 seconds, local server
    python3 simulate_sensor.py --rounds 3 --url https://USERNAME.pythonanywhere.com --key SECRET

Bins fill up by 5-20 % per round; at 90 % the server opens a Trash report on the map; one
round after a bin reaches 95 % "the truck comes" and it drops to 5 %, which resolves the report.
"""
import argparse
import json
import random
import time
import urllib.error
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:8000")
parser.add_argument("--key", default="local-test-key")
parser.add_argument("--rounds", type=int, default=8)
parser.add_argument("--delay", type=float, default=2)
parser.add_argument("--seed", type=int, default=7)
args = parser.parse_args()

rnd = random.Random(args.seed)
bins = {f"B-0{i}": {"fill": rnd.randint(30, 80), "battery": rnd.randint(70, 100)} for i in range(1, 7)}


def send(bin_id, state):
    body = json.dumps({"bin_id": bin_id, "fill_level": state["fill"], "battery": state["battery"],
                       "temperature": round(rnd.uniform(-5, 8), 1)}).encode()
    request = urllib.request.Request(args.url + "/api/sensor/reading", data=body, method="POST",
                                     headers={"Content-Type": "application/json", "X-Sensor-Key": args.key})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read())["action"]
    except urllib.error.HTTPError as error:
        return f"HTTP {error.code} {json.loads(error.read())['error']}"


for round_no in range(1, args.rounds + 1):
    print(f"round {round_no}")
    for bin_id, state in bins.items():
        if state["fill"] >= 95:
            state["fill"] = 5                       # the truck came after the alert: bin emptied
        else:
            state["fill"] = min(100, state["fill"] + rnd.randint(5, 20))
        state["battery"] = max(0, state["battery"] - rnd.randint(0, 1))
        print(f"  {bin_id}: {state['fill']:3d}% full, battery {state['battery']}% -> {send(bin_id, state)}")
    if round_no < args.rounds:
        time.sleep(args.delay)
