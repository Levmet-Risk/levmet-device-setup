"""Read-only PostgreSQL probe through the local automatic IAM proxy.

Uses only the Python standard library bundled with gcloud. No passwords,
tokens, database rows, or credentials are written to logs. Refuses non-loopback
targets and unsupported authentication rather than requesting a password.
"""
import argparse
import json
import socket
import struct
import sys


def receive(stream, count):
    result = bytearray()
    while len(result) < count:
        data = stream.recv(count - len(result))
        if not data:
            raise RuntimeError("Proxy closed the connection before the query completed. Check the proxy log.")
        result.extend(data)
    return bytes(result)


def message(stream):
    kind = receive(stream, 1)
    size = struct.unpack("!I", receive(stream, 4))[0]
    if not 4 <= size <= 1024 * 1024:
        raise RuntimeError("Invalid PostgreSQL response length")
    return kind, receive(stream, size - 4)


def error_message(payload):
    fields = {}
    for field in payload.split(b"\0"):
        if field:
            fields[chr(field[0])] = field[1:].decode("utf-8", errors="replace")
    # PostgreSQL messages may contain the user's email; never contain ADC tokens.
    return "PostgreSQL " + fields.get("C", "error") + ": " + fields.get("M", "connection failed")


def probe(port, user, database):
    if "\0" in user + database:
        raise ValueError("Invalid connection parameter")
    with socket.create_connection(("127.0.0.1", port), timeout=20) as stream:
        stream.settimeout(25)
        parameters = ("user\0" + user + "\0database\0" + database +
                      "\0client_encoding\0UTF8\0application_name\0Levmet setup verification\0\0").encode()
        body = struct.pack("!I", 196608) + parameters
        stream.sendall(struct.pack("!I", len(body) + 4) + body)
        while True:
            kind, body = message(stream)
            if kind == b"E":
                raise RuntimeError(error_message(body))
            if kind == b"R":
                method = struct.unpack("!I", body[:4])[0]
                if method == 3:
                    stream.sendall(b"p" + struct.pack("!I", 5) + b"\0")
                elif method != 0:
                    raise RuntimeError("The connection did not accept automatic IAM authentication (method " + str(method) + ").")
            if kind == b"Z":
                break
        query = b"SELECT 1, current_user, current_database()\0"
        stream.sendall(b"Q" + struct.pack("!I", len(query) + 4) + query)
        rows = []
        while True:
            kind, body = message(stream)
            if kind == b"E":
                raise RuntimeError(error_message(body))
            if kind == b"D":
                count = struct.unpack("!H", body[:2])[0]
                offset, row = 2, []
                for _ in range(count):
                    length = struct.unpack("!i", body[offset:offset + 4])[0]
                    offset += 4
                    row.append(None if length == -1 else body[offset:offset + length].decode("utf-8"))
                    if length >= 0:
                        offset += length
                rows.append(row)
            if kind == b"Z":
                break
        stream.sendall(b"X" + struct.pack("!I", 4))
    if rows != [["1", user, database]]:
        raise RuntimeError("Query reached a different database or IAM user than the config specifies.")
    return {"ok": True, "query": "SELECT 1, current_user, current_database()", "identityMatched": True, "databaseMatched": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", required=True)
    args = parser.parse_args()
    try:
        with open(args.settings, encoding="utf-8-sig") as source:
            settings = json.load(source)
        print(json.dumps(probe(settings["localPort"], settings["email"], settings["database"])))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
