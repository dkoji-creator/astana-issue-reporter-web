"""Минимальный экспорт .glb (glTF 2.0): набор именованных мешей без текстур."""
import json, struct
import numpy as np


def write_glb(path, meshes):
    """meshes: список dict(name, v (N,3) float, n (N,3) float, i (M,3) int, color=(r,g,b,a))"""
    bin_data = bytearray()
    views, accessors, gl_meshes, nodes, materials = [], [], [], [], []

    def add_view(arr, target):
        while len(bin_data) % 4:
            bin_data.append(0)
        off = len(bin_data)
        bin_data.extend(arr.tobytes())
        views.append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": target})
        return len(views) - 1

    for k, m in enumerate(meshes):
        v = np.asarray(m["v"], dtype=np.float32)
        n = np.asarray(m["n"], dtype=np.float32)
        idx = np.asarray(m["i"], dtype=np.uint32).reshape(-1)
        vi = add_view(v, 34962)
        accessors.append({"bufferView": vi, "componentType": 5126, "count": len(v), "type": "VEC3",
                          "min": v.min(0).tolist(), "max": v.max(0).tolist()})
        ni = add_view(n, 34962)
        accessors.append({"bufferView": ni, "componentType": 5126, "count": len(n), "type": "VEC3"})
        ii = add_view(idx, 34963)
        accessors.append({"bufferView": ii, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        c = m.get("color", (1, 1, 1, 1))
        materials.append({"name": m["name"], "pbrMetallicRoughness": {"baseColorFactor": list(c), "metallicFactor": 0.0, "roughnessFactor": 0.8}})
        gl_meshes.append({"name": m["name"], "primitives": [{"attributes": {"POSITION": len(accessors) - 3, "NORMAL": len(accessors) - 2},
                                                              "indices": len(accessors) - 1, "material": k}]})
        nodes.append({"name": m["name"], "mesh": k})
    doc = {"asset": {"version": "2.0", "generator": "star-greenhouse"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": gl_meshes, "materials": materials, "accessors": accessors, "bufferViews": views,
           "buffers": [{"byteLength": len(bin_data)}]}
    js = json.dumps(doc, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(bin_data) % 4:
        bin_data.append(0)
    total = 12 + 8 + len(js) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)
