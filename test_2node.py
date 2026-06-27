#!/usr/bin/env python3
"""2-node inference test: odinSrv (API) + HPSalon (worker)."""
import asyncio, sys, time, json, os
from pathlib import Path

VENV = Path.home() / "Src/exo-cuda/.venv/bin"
EXO = str(VENV / "exo")
HPSALON = "cyrille@hpsalon.local"
HP_EXO = "~/Src/exo-cuda/.venv/bin/exo"

async def wait_for_port(host, port, timeout=45):
    start = time.time()
    proc = None
    while time.time() - start < timeout:
        p = await asyncio.create_subprocess_exec(
            "ss", "-tlnp", stdout=asyncio.subprocess.PIPE)
        out, _ = await p.communicate()
        if f":{port}" in out.decode():
            return True
        await asyncio.sleep(1)
    return False

async def curl(url, data, timeout=180):
    cmd = ["curl", "-s", "-w", "\n%{http_code}", "-X", "POST", url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        lines = out.decode().strip().rsplit("\n", 1)
        code = lines[-1]
        body = lines[0] if len(lines) > 1 else ""
        return code, body
    except asyncio.TimeoutError:
        proc.kill()
        return "timeout", ""

async def start_process(cmd, tag):
    proc = await asyncio.create_subprocess_shell(
        cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    async def reader():
        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            print(f"[{tag}] {line.decode().rstrip()}", flush=True)
            if proc.returncode is not None:
                break
    asyncio.create_task(reader())
    return proc

async def main():
    # 1. Start odinSrv (API, no wait-for-peers)
    print("=== Starting odinSrv (API) ===", flush=True)
    odin = await start_process(
        f"cd {Path.home()/'Src/exo-cuda'} && {EXO} --inference-engine tinygrad --chatgpt-api-port 8001 --disable-tui",
        "odinSrv")

    if not await wait_for_port("localhost", 8001):
        print("FAIL: API port not ready on odinSrv", flush=True)
        odin.kill()
        return 1
    print("API ready!", flush=True)

    # 2. Start HPSalon (worker, no API)
    print("=== Starting HPSalon (worker) ===", flush=True)
    hp = await start_process(
        f"ssh {HPSALON} '{HP_EXO} --inference-engine tinygrad --disable-tui'",
        "HPSalon")

    # Wait for discovery + model load
    await asyncio.sleep(15)

    # 3. Send test query
    print("\n=== Sending curl request ===", flush=True)
    code, body = await curl("http://localhost:8001/v1/chat/completions", {
        "model": "unsloth/Llama-3.2-1B-Instruct",
        "messages": [{"role": "user", "content": "hello"}],
        "max_tokens": 10, "temperature": 0
    })
    print(f"HTTP {code}", flush=True)
    if body:
        try:
            j = json.loads(body)
            print(json.dumps(j, indent=2)[:500], flush=True)
        except json.JSONDecodeError:
            print(body[:2000], flush=True)

    # Cleanup
    print("\n=== Cleanup ===", flush=True)
    for p, name in [(odin, "odinSrv"), (hp, "HPSalon")]:
        p.kill()
        await p.wait()
        print(f"{name} stopped", flush=True)
    print("Done!", flush=True)

if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
