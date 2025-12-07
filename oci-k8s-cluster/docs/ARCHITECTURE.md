# OCI K8s Cluster Architecture

> [!NOTE]
> This document visualizes the "physical" and "logical" layout of the cluster. It bridges the gap between infrastructure (Nodes/Networking) and application delivery (Ingress/Services).

## 1. High-Level Topology
The cluster runs on Oracle Cloud Infrastructure (OCI) Free Tier, utilizing ARM64 Ampere instances. Connectivity is secured via a Bastion-like tunnel pattern.

```mermaid
graph TD
    User([User / Developer]) -->|SSH Tunnel :6443| API[K8s API Server]
    User -->|SSH Tunnel :443| Ingress[Ingress Controller]
    
    subgraph OCI_VCN [OCI VCN 10.0.0.0/16]
        subgraph Control_Plane ["Control Plane (Master)"]
            Master[oci-k8s-master<br/>10.0.1.100]
            API
            DB[Etcd]
        end
        
        subgraph Workers ["Worker Nodes (ARM64)"]
            Node1[oci-k8s-node-1<br/>10.0.1.221]
            Node2[oci-k8s-node-2<br/>10.0.1.50]
            Node3[oci-k8s-node-3<br/>10.0.1.85]
        end
        
        Master -->|Cilium VXLAN| Node1
        Master -->|Cilium VXLAN| Node2
        Master -->|Cilium VXLAN| Node3
    end
    
    classDef node fill:#326ce5,stroke:#fff,stroke-width:2px,color:#fff;
    classDef master fill:#eb3c27,stroke:#fff,stroke-width:2px,color:#fff;
    class Node1,Node2,Node3 node;
    class Master,API master;
```

## 2. Networking & Traffic Flow
Access to services is strictly controlled. There are no public LoadBalancers (cost saving). All traffic enters via Ingress (Nginx) which is exposed via **NodePort**, accessed through an **SSH Tunnel**.

```mermaid
sequenceDiagram
    participant U as User (Localhost)
    participant T as SSH Tunnel (Master)
    participant I as Nginx Ingress
    participant S as Service (ClusterIP)
    participant P as Pod
    
    U->>T: Request https://localhost:443 (Host: nexus.k8s)
    T->>I: Fwd to NodePort (3xxxx)
    I->>I: Match Host: nexus.k8s
    I->>S: Proxy to Service (nexus-service:8081)
    S->>P: Route to Pod Endpoint
    P-->>U: HTTP 200 OK
```

## 3. Storage Architecture
We use a hybrid storage approach to balance performance and reliability on restricted hardware.

| Provisioner | Type | Use Case | Characteristics |
| :--- | :--- | :--- | :--- |
| **Longhorn** | Block (Distributed) | **Postgres, Nexus** | High Availability, Snapshots, Replicas (Heavy CPU/RAM usage). |
| **Local-Path** | HostPath | **Minio** | Raw IOPS speed, Simple. Data pinned to specific node. |

```mermaid
graph LR
    subgraph Storage_Class_Longhorn
        PVC1[Postgres PVC] --> LH[Longhorn Engine]
        LH --> R1[Replica on Node 1]
        LH --> R2[Replica on Node 2]
    end
    
    subgraph Storage_Class_Local
        PVC2[Minio PVC] --> LP[Local Path Host Dir]
    end
```

## 4. Key Components
- **CNI**: Cilium (VXLAN Mode, No Hubblest/Encryption yet).
- **Ingress**: NGINX Ingress Controller.
- **TUI**: `k8s_ops_menu.sh` (The "Command Center" for all operations).
