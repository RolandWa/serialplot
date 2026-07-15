"""
udp_sender.py — Test script for serialplot UDP receive (issue #33)

Sends simulated sensor data as UDP packets to a local port.
Each packet is a newline-terminated ASCII line in Arduino label format:
    label1:value1,label2:value2,...

Usage:
    python udp_sender.py [--host HOST] [--port PORT] [--rate HZ] [--mode MODE]

    --host   Destination IP   (default: 127.0.0.1)
    --port   Destination port (default: 3000)
    --rate   Packets per second (default: 10)
    --mode   Data mode: sine | random | counter (default: sine)

Example:
    python udp_sender.py --port 3000 --rate 20 --mode sine

In serialplot:
    1. Open the "UDP" tab
    2. Set Bind Address to 0.0.0.0 (or 127.0.0.1) and Port to 3000
    3. Click Bind
    4. Switch to the "Data Format" tab and select ASCII
    5. Channel names should auto-detect as: temp, humidity, pressure
"""

import argparse
import math
import random
import socket
import time


def sine_values(t: float):
    temp     = 20.0 + 5.0  * math.sin(2 * math.pi * t / 5.0)
    humidity = 60.0 + 10.0 * math.sin(2 * math.pi * t / 8.0 + 1.0)
    pressure = 1013.0 + 3.0 * math.sin(2 * math.pi * t / 12.0 + 2.0)
    return temp, humidity, pressure


def random_values(_t: float):
    temp     = random.uniform(15.0, 35.0)
    humidity = random.uniform(40.0, 90.0)
    pressure = random.uniform(1005.0, 1025.0)
    return temp, humidity, pressure


def counter_values(t: float):
    n = int(t * 10)
    return float(n % 100), float(n % 50), float(n % 200)


MODES = {
    "sine":    sine_values,
    "random":  random_values,
    "counter": counter_values,
}


def main():
    parser = argparse.ArgumentParser(description="serialplot UDP test sender")
    parser.add_argument("--host", default="127.0.0.1", help="Destination IP")
    parser.add_argument("--port", type=int, default=3000, help="Destination port")
    parser.add_argument("--rate", type=float, default=10.0, help="Packets per second")
    parser.add_argument("--mode", choices=MODES.keys(), default="sine", help="Data mode")
    args = parser.parse_args()

    interval = 1.0 / args.rate
    fn = MODES[args.mode]

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    print(f"Sending UDP packets to {args.host}:{args.port} at {args.rate} Hz  (mode={args.mode})")
    print("Press Ctrl+C to stop.\n")

    start = time.monotonic()
    count = 0

    try:
        while True:
            t = time.monotonic() - start
            temp, humidity, pressure = fn(t)

            line = f"temp:{temp:.2f},humidity:{humidity:.1f},pressure:{pressure:.1f}\n"
            sock.sendto(line.encode(), (args.host, args.port))

            count += 1
            if count % int(args.rate) == 0:
                print(f"  t={t:.1f}s  {line.strip()}")

            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\nSent {count} packets in {time.monotonic() - start:.1f}s")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
