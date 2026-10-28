#!/usr/bin/env python3
# Minimal client for VMPal's per-VM MCP server (VMPalMachine --mcp <VM UUID>),
# which reads the VM's screen and types into it: what this guide uses to drive
# the Alpine installer's console before it has SSH. Images go to $MCP_OUT (.).
#   vmpal-mcp.py --mcp <VM UUID>                      list the tools
#   vmpal-mcp.py --mcp <VM UUID> -- vmpal_screenshot '{}'
#   vmpal-mcp.py --mcp <VM UUID> -- vmpal_act '{"actions":[{"action":"type","text":"root\n"}]}'
# The VM's UUID is the "id" in `bin/vmpal info <VM> --json`.
import json, subprocess, sys, base64, os, time
V = "/Applications/VMPal.app/Contents/Helpers/VMPalMachine.app/Contents/MacOS/VMPalMachine"
argv = sys.argv[1:]
sep = argv.index("--") if "--" in argv else len(argv)
server_args, calls = argv[:sep], argv[sep + 1:]
p = subprocess.Popen([V, *server_args], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
n = 0
def rpc(method, params=None, notify=False):
    global n
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None: msg["params"] = params
    if not notify:
        n += 1; msg["id"] = n
    p.stdin.write(json.dumps(msg) + "\n"); p.stdin.flush()
    if notify: return None
    while True:
        line = p.stdout.readline()
        if not line:
            raise SystemExit("server closed: " + p.stderr.read()[:2000])
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("id") == n: return r
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "omarchy-vmpal", "version": "1.0"}})
rpc("notifications/initialized", notify=True)
outdir = os.environ.get("MCP_OUT", ".")
if not calls:
    tools = rpc("tools/list")["result"]["tools"]
    for t in tools: print(t["name"], "|", t.get("description", "")[:150].replace("\n", " "))
for i in range(0, len(calls), 2):
    name, args = calls[i], json.loads(calls[i + 1])
    r = rpc("tools/call", {"name": name, "arguments": args})
    res = r.get("result") or r.get("error")
    for c in (res.get("content") or []) if isinstance(res, dict) else []:
        if c.get("type") == "image":
            f = os.path.join(outdir, "%s-%d.png" % (name, int(time.time() * 1000)))
            open(f, "wb").write(base64.b64decode(c["data"])); print("IMAGE", f)
        elif c.get("type") == "text":
            print(c["text"][:6000])
    if isinstance(res, dict) and "content" not in res: print(json.dumps(res)[:3000])
p.stdin.close(); p.terminate()
