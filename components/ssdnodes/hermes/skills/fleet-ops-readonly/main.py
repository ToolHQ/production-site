import sys
import json
import urllib.request
import os

def run():
    # Read MCP / JSON-RPC request from stdin
    try:
        input_data = sys.stdin.read()
        if not input_data:
            return
        req = json.loads(input_data)
    except Exception:
        sys.exit(1)

    # We only support GET requests to /ops/*
    endpoint = req.get("endpoint", "")
    if not endpoint.startswith("/ops/"):
        print(json.dumps({"error": "Only /ops/* endpoints are allowed in read-only mode."}))
        sys.exit(1)
        
    token = os.environ.get("FLEET_OPS_GATEWAY_TOKEN", "")
    
    url = f"http://127.0.0.1:18443{endpoint}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json"
    }
    
    try:
        req_obj = urllib.request.Request(url, headers=headers, method="GET")
        with urllib.request.urlopen(req_obj, timeout=15) as response:
            data = response.read().decode('utf-8')
            print(json.dumps({"status": response.status, "data": json.loads(data)}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    run()
