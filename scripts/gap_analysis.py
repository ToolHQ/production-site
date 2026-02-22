
import subprocess
import sys

def check_coverage():
    print("# Inventory Gap Analysis")
    
    # 1. Get List of all namespaced resources
    try:
        api_resources = subprocess.check_output(
            ["kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name"], 
            text=True
        ).splitlines()
    except Exception as e:
        print(f"Error getting api-resources: {e}")
        return

    # 2. Check each resource type count
    print("\n## Resource Type Coverage")
    print("| Resource Type | Count (Live) | Status |")
    print("|---|---|---|")
    
    missing_types = []
    
    for r in api_resources:
        if "metrics" in r or "events" in r: continue # Skip ephemeral
        
        try:
            count = subprocess.check_output(
                ["kubectl", "get", r, "-A", "--no-headers"], 
                stderr=subprocess.DEVNULL,
                text=True
            ).count('\n')
            
            if count > 0:
                print(f"| {r} | {count} | ✅ Detected |")
            else:
                # print(f"| {r} | 0 | - |")
                pass

        except:
            pass

if __name__ == "__main__":
    check_coverage()
