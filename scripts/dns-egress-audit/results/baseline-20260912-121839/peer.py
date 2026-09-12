import socket
import struct
import threading

A_RDATA = bytes([203, 0, 113, 1])  # TEST-NET-3, never routable


def parse(q):
    if len(q) < 12:
        return None
    i, labels = 12, []
    while i < len(q):
        n = q[i]
        i += 1
        if n == 0:
            break
        labels.append(q[i:i + n].decode("ascii", "replace"))
        i += n
    if i + 4 > len(q):
        return None
    qtype, _qclass = struct.unpack("!HH", q[i:i + 4])
    return ".".join(labels), qtype, q[12:i + 4]


def respond(q):
    parsed = parse(q)
    if parsed is None:
        return None, None
    name, qtype, question = parsed
    answers, ancount = b"", 0
    if qtype == 1:
        answers = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 60, 4) + A_RDATA
        ancount = 1
    elif qtype == 16:
        txt = b"dns-peer"
        rdata = bytes([len(txt)]) + txt
        answers = b"\xc0\x0c" + struct.pack("!HHIH", 16, 1, 60, len(rdata)) + rdata
        ancount = 1
    resp = q[:2] + struct.pack("!HHHHH", 0x8180, 1, ancount, 0, 0) + question + answers
    return name, resp


def udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", 53))
    print("listening udp/53", flush=True)
    while True:
        q, peer = s.recvfrom(4096)
        name, resp = respond(q)
        print(f"udp {peer[0]} {name}", flush=True)
        if resp:
            s.sendto(resp, peer)


def tcp():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 53))
    s.listen(16)
    print("listening tcp/53", flush=True)
    while True:
        c, peer = s.accept()
        try:
            hdr = c.recv(2)
            if len(hdr) == 2:
                n = struct.unpack("!H", hdr)[0]
                q = b""
                while len(q) < n:
                    chunk = c.recv(n - len(q))
                    if not chunk:
                        break
                    q += chunk
                name, resp = respond(q)
                print(f"tcp {peer[0]} {name}", flush=True)
                if resp:
                    c.sendall(struct.pack("!H", len(resp)) + resp)
        finally:
            c.close()


threading.Thread(target=udp, daemon=True).start()
tcp()
