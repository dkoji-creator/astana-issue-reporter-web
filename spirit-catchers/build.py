"""Builds SpiritCatchers.rbxlx from src/ without Rojo/Studio."""
from xml.sax.saxutils import escape
import os
D = os.path.dirname(os.path.abspath(__file__))
src = lambda n: open(os.path.join(D, "src", n), encoding="utf-8").read()
ref = iter(range(1, 999))
def script(cls, name, code):
    return (f'<Item class="{cls}" referent="RBX{next(ref)}"><Properties>'
            f'<string name="Name">{name}</string>'
            f'<ProtectedString name="Source"><![CDATA[{code}]]></ProtectedString>'
            f'</Properties></Item>')
def svc(cls, inner=""):
    return f'<Item class="{cls}" referent="RBX{next(ref)}"><Properties><string name="Name">{cls}</string></Properties>{inner}</Item>'
xml = ('<roblox version="4">'
  + svc("Workspace") + svc("Lighting")
  + svc("ReplicatedStorage", script("ModuleScript", "Models", src("Models.luau")))
  + svc("ServerScriptService", script("Script", "SpiritServer", src("Server.server.luau")))
  + svc("StarterPlayer", f'<Item class="StarterPlayerScripts" referent="RBX{next(ref)}"><Properties><string name="Name">StarterPlayerScripts</string></Properties>'
        + script("LocalScript", "SpiritClient", src("Client.client.luau")) + '</Item>')
  + '</roblox>')
open(os.path.join(D, "SpiritCatchers.rbxlx"), "w", encoding="utf-8").write(xml)
print("ok", len(xml))
