#!/usr/bin/env bash
# =============================================================================
# Script: manage_home.sh (NFS Server)
# =============================================================================
# Script de gestion des home directories NFS pour le serveur NFS (docker nfs-server).
# Execute via: docker exec nfs-server bash /manage_home.sh [operation] [args]
#
# Operations supportees:
#   1.  create_home <username>     - Creer le home NFS pour un utilisateur
#   2.  delete_home <username>     - Supprimer le home NFS d'un utilisateur
#   3.  create_multiple <u1 u2>   - Creer homes NFS pour plusieurs utilisateurs
#   4.  delete_multiple <u1 u2>   - Supprimer homes NFS pour plusieurs utilisateurs
#   5.  list_homes                - Lister les home directories NFS
#   6.  verify_home <username>    - Verifier un home NFS
#   7.  refresh_exports           - Refresh les exports NFS
#
# Utilisation interactive:
#   docker exec -it nfs-server bash /manage_home.sh
#
# Utilisation scriptee:
#   docker exec nfs-server bash /manage_home.sh create_home valen
#   docker exec nfs-server bash /manage_home.sh list_homes
# =============================================================================
#
# NOTE: Ce script gere UNIQUEMENT les home directories NFS.
# La creation/suppression des comptes NIS se fait via:
#   docker exec nis-server bash /manage_users.sh
#
# Workflow complet pour ajouter un utilisateur:
#   1. docker exec nis-server bash /manage_users.sh add_user valen
#   2. docker exec nfs-server bash /manage_home.sh create_home valen
#
# Workflow complet pour supprimer un utilisateur:
#   1. docker exec nfs-server bash /manage_home.sh delete_home valen
#   2. docker exec nis-server bash /manage_users.sh delete_user valen
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

NFS_HOME_ROOT="/srv/nfs/home"
EXPORTS_FILE="/etc/exports"

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

print_error() {
    echo "Erreur: $*" >&2
}

print_info() {
    echo "Info: $*"
}

is_valid_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

confirm() {
    local question="$1"
    local answer
    read -r -p "${question} [o/N]: " answer
    [[ "$answer" == "o" || "$answer" == "O" || "$answer" == "oui" || "$answer" == "OUI" ]]
}

# =============================================================================
# OPERATION 1: Creer le home NFS pour un utilisateur
# =============================================================================
# Creer le home directory NFS:
#   1. Creer /srv/nfs/home/<username>
#   2. Definir ownership: <username>:<username>
#   3. Definir permissions: 700 (rwx------)
# =============================================================================

create_home() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur pour le home NFS: " username
    fi

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    local home_dir="${NFS_HOME_ROOT}/${username}"

    if [[ -d "$home_dir" ]]; then
        print_error "home NFS existe deja: $home_dir"
        return 1
    fi

    print_info "creation du home NFS: $home_dir"

    # Creer la racine NFS si inexistant
    if [[ ! -d "$NFS_HOME_ROOT" ]]; then
        mkdir -p "$NFS_HOME_ROOT"
        print_info "creation de la racine NFS: $NFS_HOME_ROOT"
    fi

    # Creer le home directory
    mkdir -p "$home_dir" || {
        print_error "echec creation du home: $home_dir"
        return 1
    }

    # Definir les permissions
    chmod 700 "$home_dir" || {
        print_error "echec chmod sur $home_dir"
        return 1
    }

    # Definir le propriétaire
    # Essaye d'abord avec groupe, fallback sans groupe
    chown "$username:$username" "$home_dir" 2>/dev/null || \
    chown "$username" "$home_dir" 2>/dev/null || {
        print_error "echec chown sur $home_dir (utilisateur peut ne pas exister dans ce container)"
        print_info "home cree mais ownership non defini. Executez sur nis-server:"
        echo "  docker exec nis-server useradd -m -d ${home_dir} $username"
    }

    # Creer les fichiers de base dans le home
    mkdir -p "$home_dir"/{Desktop,Documents,Downloads} 2>/dev/null || true

    echo
    print_info "home NFS cree: $home_dir"
    echo "  Permissions: $(stat -c '%a' "$home_dir" 2>/dev/null || echo 'inconnu')"
    echo "  Owner:       $(stat -c '%U:%G' "$home_dir" 2>/dev/null || echo 'inconnu')"
    echo
    print_info "pour associer ce home a un compte NIS, executer:"
    echo "  docker exec nis-server bash /manage_users.sh add_user $username"
}

# =============================================================================
# OPERATION 2: Supprimer le home NFS d'un utilisateur
# =============================================================================

delete_home() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur dont supprimer le home NFS: " username
    fi

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    local home_dir="${NFS_HOME_ROOT}/${username}"

    if [[ ! -d "$home_dir" ]]; then
        print_error "home NFS inexistant: $home_dir"
        return 1
    fi

    if ! confirm "Confirmer suppression du home NFS ${home_dir} ?"; then
        print_info "suppression annulee."
        return 1
    fi

    print_info "suppression du home NFS: $home_dir"
    rm -rf -- "$home_dir" || {
        print_error "echec suppression du home: $home_dir"
        return 1
    }

    print_info "home NFS supprime: $home_dir"

    echo
    print_info "pour supprimer le compte NIS, executer:"
    echo "  docker exec nis-server bash /manage_users.sh delete_user $username"
}

# =============================================================================
# OPERATION 3: Creer homes NFS pour plusieurs utilisateurs (batch)
# =============================================================================

create_multiple_homes() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms pour homes NFS separes par des espaces: " -a users

    for username in "${users[@]}"; do
        echo
        echo "=== Creation home NFS pour $username ==="
        if create_home "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume creation homes NFS: ${success} succes, ${failure} echec(s)."
}

# =============================================================================
# OPERATION 4: Supprimer homes NFS pour plusieurs utilisateurs (batch)
# =============================================================================

delete_multiple_homes() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms dont supprimer homes NFS separes par des espaces: " -a users

    for username in "${users[@]}"; do
        echo
        echo "=== Suppression home NFS pour $username ==="
        if delete_home "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume suppression homes NFS: ${success} succes, ${failure} echec(s)."
}

# =============================================================================
# OPERATION 5: Lister les home directories NFS
# =============================================================================

list_homes() {
    echo
    echo "=== Home directories NFS ==="
    echo "Racine: ${NFS_HOME_ROOT}"
    echo

    if [[ ! -d "$NFS_HOME_ROOT" ]]; then
        print_error "racine NFS inexistant: $NFS_HOME_ROOT"
        return 1
    fi

    echo "Format: username:permissions:owner:size"
    echo "---"

    local entry
    for entry in "$NFS_HOME_ROOT"/*/; do
        if [[ -d "$entry" ]]; then
            local dirname
            dirname="$(basename "$entry")"
            local perms
            perms="$(stat -c '%a' "$entry" 2>/dev/null || echo '?')"
            local owner
            owner="$(stat -c '%U:%G' "$entry" 2>/dev/null || echo '?')"
            local size
            size="$(du -sh "$entry" 2>/dev/null | cut -f1 || echo '?')"
            echo "${dirname}:${perms}:${owner}:${size}"
        fi
    done

    echo "---"
    local count
    count="$(find "$NFS_HOME_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    echo "Total: ${count} home(s)"
}

# =============================================================================
# OPERATION 6: Verifier un home NFS
# =============================================================================

verify_home() {
    local username
    read -r -p "Nom utilisateur a verifier (home NFS): " username

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    local home_dir="${NFS_HOME_ROOT}/${username}"

    echo
    echo "=== Verification home NFS pour $username ==="

    echo
    echo "--- Existence ---"
    if [[ -d "$home_dir" ]]; then
        print_info "home NFS existe: $home_dir"
        echo "  Permissions: $(stat -c '%a' "$home_dir")"
        echo "  Owner:       $(stat -c '%U:%G' "$home_dir")"
        echo "  Contents:    $(ls -A "$home_dir" 2>/dev/null | tr '\n' ' ')"
    else
        print_error "home NFS inexistant: $home_dir"
    fi

    echo
    echo "--- NFS Export ---"
    if exportfs -v 2>/dev/null | grep -q "$NFS_HOME_ROOT"; then
        print_info "$NFS_HOME_ROOT est exporte via NFS"
        exportfs -v 2>/dev/null | grep "$NFS_HOME_ROOT"
    else
        print_error "$NFS_HOME_ROOT n'est pas exporte"
    fi

    echo
    echo "--- Commands de verification cote client ---"
    echo "  docker exec nis-client df -h /home"
    echo "  docker exec nis-client ls -la /home/$username"
}

# =============================================================================
# OPERATION 7: Refresh les exports NFS
# =============================================================================

refresh_exports() {
    echo
    echo "=== Refresh des exports NFS ==="

    print_info "re-lecture de /etc/exports"

    if [[ -f "$EXPORTS_FILE" ]]; then
        echo
        echo "Contenu de /etc/exports:"
        cat "$EXPORTS_FILE"
        echo
    else
        print_error "/etc/exports inexistant"
    fi

    print_info "execution: exportfs -r"
    if exportfs -r 2>/dev/null; then
        print_info "exports NFS refreshes avec succes."
    else
        print_error "echec refresh des exports NFS."
        return 1
    fi

    echo
    echo "Exports actifs:"
    exportfs -v 2>/dev/null || true
}

# =============================================================================
# MENU INTERACTIF
# =============================================================================

show_menu() {
    echo
    echo "============================================="
    echo "  Gestion homes NFS (nfs-server)"
    echo "  Racine: ${NFS_HOME_ROOT}"
    echo "============================================="
    echo "  1.  Creer un home NFS"
    echo "  2.  Supprimer un home NFS"
    echo "  3.  Creer plusieurs homes NFS"
    echo "  4.  Supprimer plusieurs homes NFS"
    echo "  5.  Lister les homes NFS"
    echo "  6.  Verifier un home NFS"
    echo "  7.  Refresh les exports NFS"
    echo "  8.  Quitter"
    echo "============================================="
}

# =============================================================================
# POINT D'ENTREE
# =============================================================================

main() {
    local choice="${1:-}"

    # Si argument fourni, executer directement
    if [[ -n "$choice" ]]; then
        case "$choice" in
            1|create_home)
                create_home "${2:-}"
                ;;
            2|delete_home)
                delete_home "${2:-}"
                ;;
            3|create_multiple)
                create_multiple_homes
                ;;
            4|delete_multiple)
                delete_multiple_homes
                ;;
            5|list_homes)
                list_homes
                ;;
            6|verify_home)
                verify_home
                ;;
            7|refresh_exports)
                refresh_exports
                ;;
            8|quit|exit)
                exit 0
                ;;
            *)
                print_error "operation invalide: $choice"
                echo "Operations: 1|create_home, 2|delete_home, 3|create_multiple, 4|delete_multiple, 5|list_homes, 6|verify_home, 7|refresh_exports, 8|quit"
                exit 1
                ;;
        esac
        return
    fi

    # Mode interactif
    while true; do
        show_menu
        read -r -p "Choix: " choice

        case "$choice" in
            1|create_home) create_home ;;
            2|delete_home) delete_home ;;
            3|create_multiple) create_multiple_homes ;;
            4|delete_multiple) delete_multiple_homes ;;
            5|list_homes) list_homes ;;
            6|verify_home) verify_home ;;
            7|refresh_exports) refresh_exports ;;
            8|quit|exit) exit 0 ;;
            *) print_error "Choix invalide: $choice" ;;
        esac
    done
}

main "$@"