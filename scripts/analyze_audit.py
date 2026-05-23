
import csv

def analyze():
    waste = []
    risks = []
    audit_file = "/home/dnorio/production-site/resource_audit.csv"
    
    try:
        with open(audit_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ns = row['Namespace']
                pod = row['Pod']
                container = row['Container']
                cpu_req = int(row['CPU_Req_m'])
                cpu_lim = int(row['CPU_Lim_m'])
                cpu_use = int(row['CPU_Usage_m'])
                
                # Waste Analysis
                if cpu_req > 0:
                    if cpu_use < (cpu_req * 0.5) and cpu_req > 10: # Only care if req > 10m
                        waste.append(f"{ns}/{pod}/{container}: Req={cpu_req}m Use={cpu_use}m (Waste: {cpu_req - cpu_use}m)")
                
                # Risk Analysis
                if cpu_lim == 0:
                    risks.append(f"{ns}/{pod}/{container}: No CPU Limit")

    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    print("## 🗑️ Waste Identification (Over-provisioned)")
    if waste:
        for w in waste: print(f"- {w}")
    else:
        print("No significant waste found.")

    print("\n## ⚠️ Risk Identification (Unbounded)")
    if risks:
        for r in risks: print(f"- {r}")
    else:
        print("No unbounded containers found.")

if __name__ == "__main__":
    analyze()
