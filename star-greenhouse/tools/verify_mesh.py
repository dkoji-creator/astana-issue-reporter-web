"""Скачивает загруженную модель и проверяет её: имена MeshPart, размеры, позиции. python3 tools/verify_mesh.py <assetId>"""
import json, struct, subprocess, sys, lz4.block

aid = sys.argv[1]
loc = json.loads(subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{aid}"], capture_output=True, text=True).stdout)["location"]
data = subprocess.run(["curl", "-sS", "--compressed", loc], capture_output=True).stdout
d = data
pos = 32
insts, props = {}, {}
while pos < len(d):
    name = d[pos:pos + 4]
    comp, unc, _ = struct.unpack("<III", d[pos + 4:pos + 16])
    pos += 16
    raw = lz4.block.decompress(d[pos:pos + comp], uncompressed_size=unc) if comp else d[pos:pos + unc]
    pos += comp if comp else unc
    if name == b"INST":
        cid, = struct.unpack("<I", raw[:4])
        nl, = struct.unpack("<I", raw[4:8])
        cname = raw[8:8 + nl].decode()
        cnt, = struct.unpack("<I", raw[9 + nl:13 + nl])
        insts[cid] = (cname, cnt)
    if name == b"PROP":
        cid, = struct.unpack("<I", raw[:4])
        nl, = struct.unpack("<I", raw[4:8])
        props[(cid, raw[8:8 + nl].decode())] = raw[9 + nl:]
    if name == b"END\0":
        break


def strings(b, n):
    out, p = [], 0
    for _ in range(n):
        l, = struct.unpack("<I", b[p:p + 4])
        out.append(b[p + 4:p + 4 + l].decode())
        p += 4 + l
    return out


def unf(b, n):
    out = []
    for i in range(n):
        v = (b[i] << 24) | (b[n + i] << 16) | (b[2 * n + i] << 8) | b[3 * n + i]
        v = ((v >> 1) | ((v & 1) << 31)) & 0xFFFFFFFF
        out.append(struct.unpack("<f", struct.pack("<I", v))[0])
    return out


mp = [c for c, (n, _) in insts.items() if n == "MeshPart"][0]
cnt = insts[mp][1]
names = strings(props[(mp, "Name")], cnt)
sizes = props[(mp, "size")]
xs, ys, zs = unf(sizes[:4 * cnt], cnt), unf(sizes[4 * cnt:8 * cnt], cnt), unf(sizes[8 * cnt:12 * cnt], cnt)
print("MeshParts:", cnt, "classes:", {n: c for n, c in insts.values()})
for i in (0, 1, 2, cnt - 1):
    print(names[i], round(xs[i], 2), round(ys[i], 2), round(zs[i], 2))
ok = [n for n in names if "__" in n]
print("с правильными именами:", len(ok), "из", cnt)
print("есть SurfaceAppearance:", any(n == "SurfaceAppearance" for n, _ in insts.values()))
