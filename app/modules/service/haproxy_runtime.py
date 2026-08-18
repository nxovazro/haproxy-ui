"""Minimal HAProxy Runtime API client without a netcat/shell dependency."""

import socket


_MAX_RESPONSE_SIZE = 2 * 1024 * 1024


def execute_runtime_command(
    server: str,
    port: int,
    command: str,
    *,
    timeout: float = 5,
    response_limit: int = _MAX_RESPONSE_SIZE,
) -> str:
    """Send exactly one command to an HAProxy TCP Runtime API endpoint."""
    port = int(port)
    if not server:
        raise ValueError('HAProxy Runtime API server cannot be empty')
    if port < 1 or port > 65535:
        raise ValueError('HAProxy Runtime API port must be between 1 and 65535')
    if not command or any(character in command for character in ('\x00', '\n', '\r')):
        raise ValueError('HAProxy Runtime API command must be one non-empty line')
    if response_limit < 1:
        raise ValueError('HAProxy Runtime API response limit must be positive')

    response = bytearray()
    with socket.create_connection((server, port), timeout=timeout) as connection:
        connection.settimeout(timeout)
        connection.sendall(f'{command}\n'.encode('utf-8'))
        connection.shutdown(socket.SHUT_WR)

        while True:
            chunk = connection.recv(min(65536, response_limit + 1 - len(response)))
            if not chunk:
                break
            response.extend(chunk)
            if len(response) > response_limit:
                raise RuntimeError('HAProxy Runtime API response is too large')

    return response.decode('utf-8', errors='backslashreplace')
