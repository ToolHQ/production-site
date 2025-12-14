#!/usr/bin/env bash
# i18n Translation System for K8s Ops TUI
# Supports English (en) and Portuguese BR (pt_BR)

set -eo pipefail

# Current language (set by caller)
I18N_LANG="${I18N_LANG:-en}"

# Translation lookup function
# Usage: t "message_key"
t() {
    local key="$1"
    local lang="${I18N_LANG}"
    
    # Translation database
    case "$lang" in
        pt_BR)
            case "$key" in
                # Main Menu
                "menu_header") echo "Cluster" ;;
                "menu_k9s") echo "1. Dashboard Avançado (k9s) 🚀" ;;
                "menu_port_forward") echo "2. Acesso & Encaminhamento de Portas (Túneis SSH) 🚇" ;;
                "menu_service_config") echo "3. Configuração de Serviços (Minio/Nexus) ⚙️" ;;
                "menu_credentials") echo "4. Ver Credenciais 🔐" ;;
                "menu_components") echo "5. Gerenciamento de Componentes (Deploy/Atualizar) 📦" ;;
                "menu_dashboard") echo "6. Abrir Dashboard Kubernetes (Navegador) 🌐" ;;
                "menu_namespace") echo "7. Mudar Namespace (Atual: %s)" ;;
                "menu_pod") echo "8. Selecionar Pod" ;;
                "menu_all_pods") echo "9. Mostrar Todos os Pods" ;;
                "menu_nodes") echo "10. Status dos Nós" ;;
                "menu_update") echo "11. Atualização Segura de Nó (OS/Kernel) 🔄" ;;
                "menu_maintenance") echo "12. Manutenção do Cluster (Setup/Reparo/Restaurar) 🛠️" ;;
                "menu_preferences") echo "13. Preferências ⚙️" ;;
                "menu_security") echo "14. Segurança & TLS (Certificados/Políticas) 🔒" ;;
                "menu_backup") echo "15. Backup & Recuperação de Desastres 💾" ;;
                "menu_volumes") echo "16. Gerenciar Volumes (Resize/Snapshots) 💿" ;;
                "menu_disk_optimizer") echo "17. Otimizador de Disco em Nós (Limpeza de Imagens) 💽" ;;
                "menu_node_fixer") echo "18. Node Fixer (Dependências Longhorn: dm_crypt/multipath) 🔧" ;;
                "menu_exit") echo "0. Sair" ;;
                
                # Preferences Menu
                "prefs_menu_title") echo "Preferências" ;;
                "prefs_change_lang") echo "1. Mudar Idioma 🌍" ;;
                "prefs_reorder_menu") echo "2. Reordenar Menu 📋" ;;
                
                # Ingress Menu
                "ingress_menu_title") echo "3. Ingress & DNS Helper 🌐" ;;
                "ingress_start_tunnel") echo "1. Iniciar Túnel Ingress (HTTP:80 / HTTPS:443) 🚀" ;;
                "ingress_show_dns") echo "2. Atualizar /etc/hosts (Auto) 📝" ;;
                "ingress_detecting") echo "Detectando Ingress Controller..." ;;
                "ingress_not_found") echo "❌ Ingress Controller não encontrado!" ;;
                "ingress_tunnel_running") echo "✅ Túnel Ingress rodando!" ;;
                "ingress_hosts_title") echo "=== Domínios Ingress Detectados ===" ;;
                "ingress_hosts_instructions") echo "Adicione as seguintes linhas ao seu /etc/hosts local:" ;;
                "prefs_auto_ports") echo "3. Configurar Encaminhamento Automático de Portas 🚀" ;;
                "prefs_back") echo "0. Voltar" ;;
                
                # Language Selection
                "lang_select_title") echo "Selecionar Idioma" ;;
                "lang_english") echo "1. English" ;;
                "lang_portuguese") echo "2. Português (Brasil)" ;;
                "lang_changed") echo "✓ Idioma alterado para" ;;
                
                # Port Status
                "port_status_active") echo "Túneis Ativos" ;;
                "port_status_none") echo "Nenhum túnel ativo" ;;
                
                # Auto Port Forwarding
                "auto_ports_title") echo "Configurar Encaminhamento Automático de Portas" ;;
                "auto_ports_add") echo "1. Adicionar Porta" ;;
                "auto_ports_remove") echo "2. Remover Porta" ;;
                "auto_ports_list") echo "3. Listar Portas Configuradas" ;;
                "auto_ports_current") echo "Portas configuradas atualmente" ;;
                "auto_ports_none") echo "Nenhuma porta configurada para encaminhamento automático" ;;
                "auto_ports_added") echo "✓ Porta adicionada à lista de encaminhamento automático" ;;
                "auto_ports_removed") echo "✓ Porta removida da lista de encaminhamento automático" ;;
                "auto_ports_starting") echo "Iniciando encaminhamentos automáticos de porta..." ;;
                "auto_ports_success") echo "✓ Encaminhamento estabelecido" ;;
                "auto_ports_failed") echo "✗ Falha ao estabelecer encaminhamento" ;;
                
                # Common
                "back") echo "Voltar" ;;
                "exit") echo "Sair" ;;
                "cancel") echo "Cancelar" ;;
                "yes") echo "Sim" ;;
                "no") echo "Não" ;;
                "press_enter") echo "Pressione Enter para continuar..." ;;
                "select") echo "Selecionar" ;;
                
                # Cluster Maintenance Menu
                "maint_full_setup") echo "1. Configuração/Reparo Completo do Cluster (setup_k8s_cluster.sh) 🏗️" ;;
                "maint_full_heal") echo "2. Restauração Completa do Cluster (Opção Nuclear) ☢️" ;;
                "maint_iptables") echo "3. Corrigir IPTables (Abrir Portas) 🔥" ;;
                "maint_dns") echo "4. Corrigir DNS (CoreDNS/Cilium) 🧪" ;;
                "maint_network") echo "5. Corrigir Rede do Host (OS/Resolv.conf) 🛠️" ;;
                
                # Component Management Menu
                "comp_deploy") echo "1. Deploy/Atualizar Componentes (Interativo) 📦" ;;
                "comp_longhorn") echo "2. Reinstalar Longhorn (Armazenamento) 💾" ;;
                
                # Access Menu
                "access_start_tunnel") echo "1. Iniciar Novo Túnel 🚀" ;;
                "access_manage_tunnels") echo "2. Gerenciar Túneis Ativos 📋" ;;
                
                # Security Menu
                "menu_security") echo "14. Segurança & TLS (Certificados/Políticas) 🔒" ;;
                "sec_menu_title") echo "Gerenciamento de Segurança & TLS" ;;
                "sec_check_certs") echo "1. Verificar Status dos Certificados 📜" ;;
                "sec_view_policies") echo "2. Ver Políticas de Rede 🛡️" ;;
                "sec_force_renew") echo "3. Forçar Renovação de Certificados 🔄" ;;
                "sec_export_ca") echo "4. Exportar CA Raiz (Para Importar no Navegador) 📥" ;;
                "sec_install_ca") echo "5. Instalar CA Raiz Automaticamente (Windows/WSL) 🪄" ;;
                
                # Backup Menu
                "menu_backup") echo "15. Backup & Recuperação de Desastres 💾" ;;
                "menu_volumes") echo "16. Gerenciar Volumes (Resize/Snapshots) 💿" ;;
                "bkp_menu_title") echo "Backup & Recuperação de Desastres" ;;
                "bkp_etcd_now") echo "1. Executar Backup do etcd AGORA ⚡" ;;
                "bkp_etcd_list") echo "2. Listar Backups do etcd 📜" ;;
                "bkp_longhorn_ui") echo "3. Abrir UI do Longhorn (Gerenciar Snapshots) 🌐" ;;
                
                # Service Config Menu
                "svc_minio_init") echo "1. Inicializar Minio (Bucket + Chaves de Acesso) 🪣" ;;
                "svc_nexus_init") echo "2. Inicializar Nexus (Blob Store + Repositório Docker) 📦" ;;
                "svc_nexus_reset") echo "3. Resetar Nexus (Limpar Dados & Reiniciar) 🔄" ;;
                "svc_auto_init") echo "4. Auto-Inicializar Tudo (Minio → Nexus) 🚀" ;;
                
                *) echo "$key" ;;  # Fallback to key if not found
            esac
            ;;
        *)  # Default: English
            case "$key" in
                # Main Menu
                "menu_header") echo "Cluster" ;;
                "menu_k9s") echo "1. Advanced Dashboard (k9s) 🚀" ;;
                "menu_port_forward") echo "2. Access & Port Forwarding (SSH Tunnels) 🚇" ;;
                "menu_service_config") echo "3. Service Configuration (Minio/Nexus) ⚙️" ;;
                "menu_credentials") echo "4. View Credentials 🔐" ;;
                "menu_components") echo "5. Component Management (Deploy/Update) 📦" ;;
                "menu_dashboard") echo "6. Open Kubernetes Dashboard (Browser) 🌐" ;;
                "menu_namespace") echo "7. Change Namespace (Current: %s)" ;;
                "menu_pod") echo "8. Select Pod" ;;
                "menu_all_pods") echo "9. Show All Pods" ;;
                "menu_nodes") echo "10. Node Status" ;;
                "menu_update") echo "11. Safe Node Update (OS/Kernel) 🔄" ;;
                "menu_maintenance") echo "12. Cluster Maintenance (Setup/Repair/Heal) 🛠️" ;;
                "menu_preferences") echo "13. Preferences ⚙️" ;;
                "menu_security") echo "14. Security & TLS (Certificates/Policies) 🔒" ;;
                "menu_backup") echo "15. Backup & Disaster Recovery 💾" ;;
                "menu_volumes") echo "16. Manage Volumes (Resize/Snapshots) 💿" ;;
                "menu_disk_optimizer") echo "17. Node Disk Optimizer (Image Prune) 💽" ;;
                "menu_node_fixer") echo "18. Node Fixer (Longhorn Reqs: dm_crypt/multipath) 🔧" ;;
                "menu_exit") echo "0. Exit" ;;
                
                # Preferences Menu
                "prefs_menu_title") echo "Preferences" ;;
                "prefs_change_lang") echo "1. Change Language 🌍" ;;
                "prefs_reorder_menu") echo "2. Reorder Menu Items 📋" ;;

                # Ingress Menu
                "ingress_menu_title") echo "3. Ingress & DNS Helper 🌐" ;;
                "ingress_start_tunnel") echo "1. Start Ingress Tunnel (HTTP:80 / HTTPS:443) 🚀" ;;
                "ingress_show_dns") echo "2. Update /etc/hosts (Auto) 📝" ;;
                "ingress_detecting") echo "Detecting Ingress Controller..." ;;
                "ingress_not_found") echo "❌ Ingress Controller not found!" ;;
                "ingress_tunnel_running") echo "✅ Ingress Tunnel running!" ;;
                "ingress_hosts_title") echo "=== Detected Ingress Hosts ===" ;;
                "ingress_hosts_instructions") echo "Add the following lines to your local /etc/hosts:" ;;
                "prefs_auto_ports") echo "3. Configure Auto Port Forwarding 🚀" ;;
                "prefs_back") echo "0. Back" ;;
                
                # Language Selection
                "lang_select_title") echo "Select Language" ;;
                "lang_english") echo "1. English" ;;
                "lang_portuguese") echo "2. Português (Brasil)" ;;
                "lang_changed") echo "✓ Language changed to" ;;
                
                # Port Status
                "port_status_active") echo "Active Tunnels" ;;
                "port_status_none") echo "No active tunnels" ;;
                
                # Auto Port Forwarding
                "auto_ports_title") echo "Configure Auto Port Forwarding" ;;
                "auto_ports_add") echo "1. Add Port" ;;
                "auto_ports_remove") echo "2. Remove Port" ;;
                "auto_ports_list") echo "3. List Configured Ports" ;;
                "auto_ports_current") echo "Currently configured ports" ;;
                "auto_ports_none") echo "No ports configured for auto forwarding" ;;
                "auto_ports_added") echo "✓ Port added to auto forwarding list" ;;
                "auto_ports_removed") echo "✓ Port removed from auto forwarding list" ;;
                "auto_ports_starting") echo "Starting automatic port forwards..." ;;
                "auto_ports_success") echo "✓ Forwarding established" ;;
                "auto_ports_failed") echo "✗ Failed to establish forwarding" ;;
                
                # Common
                "back") echo "Back" ;;
                "exit") echo "Exit" ;;
                "cancel") echo "Cancel" ;;
                "yes") echo "Yes" ;;
                "no") echo "No" ;;
                "press_enter") echo "Press Enter to continue..." ;;
                "select") echo "Select" ;;
                
                # Cluster Maintenance Menu
                "maint_full_setup") echo "1. Full Cluster Setup/Repair (setup_k8s_cluster.sh) 🏗️" ;;
                "maint_full_heal") echo "2. Full Cluster Heal (Nuclear Option) ☢️" ;;
                "maint_iptables") echo "3. Fix IPTables (Open Ports) 🔥" ;;
                "maint_dns") echo "4. Fix DNS (CoreDNS/Cilium) 🧪" ;;
                "maint_network") echo "5. Fix Host Network (OS/Resolv.conf) 🛠️" ;;
                
                # Component Management Menu
                "comp_deploy") echo "1. Deploy/Update Components (Interactive) 📦" ;;
                "comp_longhorn") echo "2. Reinstall Longhorn (Storage) 💾" ;;
                
                # Access Menu
                "access_start_tunnel") echo "1. Start New Tunnel 🚀" ;;
                "access_manage_tunnels") echo "2. Manage Active Tunnels 📋" ;;
                
                # Security Menu
                "menu_security") echo "14. Security & TLS (Certificates/Policies) 🔒" ;;
                "sec_menu_title") echo "Security & TLS Management" ;;
                "sec_check_certs") echo "1. Check Certificate Status 📜" ;;
                "sec_view_policies") echo "2. View Network Policies 🛡️" ;;
                "sec_force_renew") echo "3. Force Certificate Renewal 🔄" ;;
                "sec_export_ca") echo "4. Export Root CA (For Browser Import) 📥" ;;
                "sec_install_ca") echo "5. Auto-Install Root CA (Windows/WSL) 🪄" ;;
                
                # Backup Menu
                "menu_backup") echo "15. Backup & Disaster Recovery 💾" ;;
                "menu_volumes") echo "16. Manage Volumes (Resize/Snapshots) 💿" ;;
                "bkp_menu_title") echo "Backup & Disaster Recovery" ;;
                "bkp_etcd_now") echo "1. Trigger etcd Backup NOW ⚡" ;;
                "bkp_etcd_list") echo "2. List etcd Backups 📜" ;;
                "bkp_longhorn_ui") echo "3. Open Longhorn UI (Manage Snapshots) 🌐" ;;
                
                # Service Config Menu
                "svc_minio_init") echo "1. Initialize Minio (Bucket + Access Keys) 🪣" ;;
                "svc_nexus_init") echo "2. Initialize Nexus (Blob Store + Docker Repo) 📦" ;;
                "svc_nexus_reset") echo "3. Reset Nexus (Wipe Data & Restart) 🔄" ;;
                "svc_auto_init") echo "4. Auto-Initialize All (Minio → Nexus) 🚀" ;;
                
                *) echo "$key" ;;  # Fallback to key if not found
            esac
            ;;
    esac
}

# Export function if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f t
fi
