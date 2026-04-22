#!/usr/bin/env python3
import asyncio
import os
import signal
import subprocess
import sys


NODE_CONTAINER = os.environ.get("NODE_CONTAINER", "reunion-worker2")
PORT_MAP = (
    (4317, 30317),
    (30300, 30300),
    (9090, 30900),
    (9093, 30903),
)


def get_node_ip() -> str:
    result = subprocess.run(
        [
            "docker",
            "inspect",
            NODE_CONTAINER,
            "--format",
            "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    node_ip = result.stdout.strip()
    if not node_ip:
        raise RuntimeError(f"no IP found for {NODE_CONTAINER}")
    return node_ip


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


async def handle_client(
    local_port: int,
    remote_host: str,
    remote_port: int,
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
) -> None:
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(remote_host, remote_port)
    except Exception as exc:
        print(f"forward {local_port}->{remote_host}:{remote_port} failed: {exc}", file=sys.stderr)
        client_writer.close()
        await client_writer.wait_closed()
        return

    await asyncio.gather(
        pipe(client_reader, upstream_writer),
        pipe(upstream_reader, client_writer),
    )


async def main() -> None:
    node_ip = get_node_ip()
    servers = []

    for local_port, remote_port in PORT_MAP:
        server = await asyncio.start_server(
            lambda r, w, lp=local_port, rp=remote_port: handle_client(lp, node_ip, rp, r, w),
            host="0.0.0.0",
            port=local_port,
        )
        servers.append(server)
        print(f"listening on 0.0.0.0:{local_port} -> {node_ip}:{remote_port}")

    stop_event = asyncio.Event()

    def request_stop() -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, request_stop)

    await stop_event.wait()

    for server in servers:
        server.close()
        await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
