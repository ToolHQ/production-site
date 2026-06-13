import subprocess
import json
import sys

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        # sys.stderr.write(f"Cmd failed: {cmd}\n")
        return ""

def get_cpu_millis(cpu_str):
    if not cpu_str: return 0
    if cpu_str.endswith('m'):
        return int(cpu_str[:-1])
    try:
        return int(float(cpu_str) * 1000)
    except (ValueError, TypeError):
        return 0

def main():
    # 1. Get Usage Map (GLOBAL)
    # Output: NAMESPACE POD NAME CPU MEMORY
    print("Gathering metrics...", file=sys.stderr)
    usage_map = {} # (ns, pod) -> string
    top_output = run_cmd("kubectl top pods -A --no-headers")
    for line in top_output.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            usage_map[(parts[0], parts[1])] = parts[2]

    # 2. Get Nodes
    nodes = run_cmd("kubectl get nodes -o jsonpath='{.items[*].metadata.name}'").strip().split()
    
    for node in nodes:
        print(f"\n### Node: {node}")
        
        # 3. Get Pods covering this node
        pods_json_str = run_cmd(f"kubectl get pods -A --field-selector spec.nodeName={node} -o json")
        try:
            pods_data = json.loads(pods_json_str)
        except (json.JSONDecodeError, ValueError):
            print("  (Error parsing JSON)")
            continue

        rows = []
        for item in pods_data.get('items', []):
            metadata = item.get('metadata', {})
            name = metadata.get('name')
            ns = metadata.get('namespace')
            
            # Sum Requests
            req_cpu = 0
            for c in item.get('spec', {}).get('containers', []):
                resources = c.get('resources', {})
                req = resources.get('requests', {})
                req_cpu += get_cpu_millis(req.get('cpu', '0'))
                
            # Use cached usage
            used_cpu_str = usage_map.get((ns, name), "0m")
            used_cpu = get_cpu_millis(used_cpu_str)
            
            rows.append({
                'ns': ns,
                'pod': name,
                'req': req_cpu,
                'used': used_cpu,
                'used_str': used_cpu_str
            })

        rows.sort(key=lambda x: x['req'], reverse=True)

        print(f"| {'Namespace':<15} | {'Pod Name':<45} | {'CPU Req':<10} | {'CPU Used':<10} |")
        print(f"|{'-'*17}|{'-'*47}|{'-'*12}|{'-'*12}|")
        
        total_req = 0
        total_used = 0
        
        for r in rows:
            if r['req'] == 0 and r['used'] == 0: continue
            print(f"| {r['ns']:<15} | {r['pod']:<45} | {str(r['req'])+'m':<10} | {r['used_str']:<10} |")
            total_req += r['req']
            total_used += r['used']
            
        print(f"|{'-'*17}|{'-'*47}|{'-'*12}|{'-'*12}|")
        print(f"| {'TOTAL':<15} | {'(All Pods)':<45} | {str(total_req)+'m':<10} | {str(total_used)+'m':<10} |")
        print("\n")

if __name__ == "__main__":
    main()
