#!/usr/bin/env bash
# =============================================================================
# Script: manage_users.sh (NIS Server)
# =============================================================================
# Script de gestion des utilisateurs pour le serveur NIS (docker nis-server).
# Execute via: docker exec nis-server bash /manage_users.sh [operation] [args]
#
# Operations supportees:
#   1.  add_user <username>        - Ajouter un utilisateur (NIS)
#   2.  delete_user <username>     - Supprimer un utilisateur (NIS)
#   3.  add_multiple <u1 u2 u3>   - Ajouter plusieurs utilisateurs (NIS)
#   4.  delete_multiple <u1 u2>   - Supprimer plusieurs utilisateurs (NIS)
#   5.  list_users                - Lister les utilisateurs NIS
#   6.  verify_user <username>    - Verifier un utilisateur (NIS)
#   7.  regenerate_maps           - Regenerer les maps NIS
#
# Utilisation interactive:
#   docker exec -it nis-server bash /manage_users.sh
#
# Utilisation scriptee:
#   docker exec nis-server bash /manage_users.sh add_user valen
#   docker exec nis-server bash /manage_users.sh list_users
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

NIS_DOMAIN="${NIS_DOMAIN:-localdomain}"
NIS_MAP_DIR="/var/yp"
NFS_HOME_ROOT="/srv/nfs/home"

# Comptes proteges (systeme)
DANGEROUS_USERS=(
    root nobody daemon bin sys sync games man lp mail news uucp proxy
    www-data backup list irc _apt systemd-network systemd-resolve
)

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

print_error() {
    echo "Erreur: $*" >&2
}

print_info() {
    echo "Info: $*"
}

is_dangerous_user() {
    local username="$1"
    local dangerous
    for dangerous in "${DANGEROUS_USERS[@]}"; do
        if [[ "$username" == "$dangerous" ]]; then
            return 0
        fi
    done
    return 1
}

is_valid_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

user_exists_nis() {
    local username="$1"
    ypcat passwd 2>/dev/null | cut -d: -f1 | grep -Fxq "$username"
}

user_exists_local() {
    local username="$1"
    getent passwd "$username" >/dev/null 2>&1
}

confirm() {
    local question="$1"
    local answer
    read -r -p "${question} [o/N]: " answer
    [[ "$answer" == "o" || "$answer" == "O" || "$answer" == "oui" || "$answer" == "OUI" ]]
}

# =============================================================================
# OPERATION 1: Ajouter un utilisateur (NIS)
# =============================================================================
# Creer un compte dans NIS:
#   1. useradd - creer dans /etc/passwd
#   2. passwd - definir mot de passe
#   3. make -C /var/yp - propager dans la map NIS
# =============================================================================

add_user() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur a ajouter (NIS): " username
    fi

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    if is_dangerous_user "$username"; then
        print_error "compte protege refuse: $username"
        return 1
    fi

    if user_exists_local "$username"; then
        print_error "utilisateur deja existant: $username"
        return 1
    fi

    print_info "creation de l'utilisateur: $username"
    if ! useradd -m -d "${NFS_HOME_ROOT}/${username}" "$username"; then
        print_error "echec useradd pour $username"
        return 1
    fi

    echo "Definition du mot de passe pour $username"
    if ! passwd "$username"; then
        print_error "echec passwd pour $username"
        userdel "$username" 2>/dev/null
        return 1
    fi

    print_info "regeneration des maps NIS..."
    if make -C "$NIS_MAP_DIR"; then
        print_info "maps NIS regenerees. Utilisateur $username propage."
    else
        print_error "echec regeneration maps NIS."
        return 1
    fi

    echo
    print_info "verification cote client:"
    echo "  docker exec nis-client getent passwd $username"
    echo "  docker exec nis-client ypcat passwd | grep $username"
}

# =============================================================================
# OPERATION 2: Supprimer un utilisateur (NIS)
# =============================================================================
# Supprimer un compte de NIS:
#   1. userdel - supprimer de /etc/passwd
#   2. make -C /var/yp - mettre a jour la map NIS
# =============================================================================

delete_user() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur a supprimer (NIS): " username
    fi

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    if is_dangerous_user "$username"; then
        print_error "suppression refusee pour compte protege: $username"
        return 1
    fi

    if ! user_exists_local "$username"; then
        print_error "utilisateur introuvable: $username"
        return 1
    fi

    if ! confirm "Confirmer suppression de ${username} (NIS) ?"; then
        print_info "suppression annulee."
        return 1
    fi

    print_info "suppression de l'utilisateur: $username"
    if ! userdel "$username"; then
        print_error "echec userdel pour $username"
        return 1
    fi

    print_info "regeneration des maps NIS..."
    if make -C "$NIS_MAP_DIR"; then
        print_info "maps NIS regenerees. Utilisateur $username supprime de NIS."
    else
        print_error "echec regeneration maps NIS."
        return 1
    fi

    echo
    print_info "pour supprimer le home NFS, executer:"
    echo "  docker exec nfs-server bash /manage_home.sh delete_home $username"
}

# =============================================================================
# OPERATION 3: Ajouter plusieurs utilisateurs (NIS - batch)
# =============================================================================

add_multiple_users() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms a ajouter separes par des espaces (NIS): " -a users

    for username in "${users[@]}"; do
        echo
        echo "=== Ajout de $username ==="
        if add_user "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume ajout NIS: ${success} succes, ${failure} echec(s)."
}

# =============================================================================
# OPERATION 4: Supprimer plusieurs utilisateurs (NIS - batch)
# =============================================================================

delete_multiple_users() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms a supprimer separes par des espaces (NIS): " -a users

    for username in "${users[@]}"; do
        echo
        echo "=== Suppression de $username ==="
        if delete_user "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume suppression NIS: ${success} succes, ${failure} echec(s)."
}

# =============================================================================
# OPERATION 5: Lister les utilisateurs NIS
# =============================================================================

list_nis_users() {
    echo
    echo "=== Utilisateurs NIS (domain: ${NIS_DOMAIN}) ==="
    echo "Format: username:UID:home_directory"
    echo

    local tmp_file
    tmp_file="$(mktemp)" || {
        print_error "creation fichier temporaire impossible."
        return 1
    }

    if ypcat passwd >"$tmp_file" 2>/dev/null; then
        echo "--- Map NIS passwd ---"
        cut -d: -f1,3,6 "$tmp_file"
        echo
    else
        print_error "ypcat passwd indisponible."
        echo "--- Alternative: /etc/passwd (UID >= 1000) ---"
        awk -F: -v min_uid=1000 '$3 >= min_uid { print $1 ":" $3 ":" $6 }' /etc/passwd
        echo
    fi

    rm -f "$tmp_file"
}

# =============================================================================
# OPERATION 6: Verifier un utilisateur (NIS)
# =============================================================================

verify_user() {
    local username
    read -r -p "Nom utilisateur a verifier (NIS): " username

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    echo
    echo "=== Verification de $username ==="

    # Verification locale (via NSS)
    echo
    echo "--- Verification locale (getent) ---"
    if getent passwd "$username"; then
        print_info "utilisateur trouve via getent (local/NSS)."
    else
        print_error "utilisateur absent via getent."
    fi

    # Verification NIS directe
    echo
    echo "--- Verification NIS (ypcat) ---"
    if user_exists_nis "$username"; then
        ypcat passwd 2>/dev/null | grep -E "^${username}:"
        print_info "utilisateur trouve dans la map NIS."
    else
        print_error "utilisateur absent dans la map NIS."
    fi

    # Commands de verification sur le client
    echo
    echo "=== Commandes de verification cote client ==="
    echo "  docker exec nis-client getent passwd $username"
    echo "  docker exec nis-client ypcat passwd | grep $username"
    echo "  docker exec nis-client su - $username"
}

# =============================================================================
# OPERATION 7: Regenerer les maps NIS
# =============================================================================

regenerate_nis_maps() {
    echo
    echo "=== Regeneration des maps NIS ==="

    if [[ ! -d "$NIS_MAP_DIR" ]]; then
        print_error "dossier NIS absent: $NIS_MAP_DIR"
        return 1
    fi

    print_info "execution: make -C ${NIS_MAP_DIR}"
    if make -C "$NIS_MAP_DIR"; then
        print_info "maps NIS regenerees avec succes."
        echo
        echo "Maps generees:"
        ls -la "$NIS_MAP_DIR"/*.db 2>/dev/null || true
    else
        print_error "echec regeneration des maps NIS."
        return 1
    fi
}

# =============================================================================
# MENU INTERACTIF
# =============================================================================

show_menu() {
    echo
    echo "============================================="
    echo "  Gestion utilisateurs NIS (nis-server)"
    echo "  Domain: ${NIS_DOMAIN}"
    echo "============================================="
    echo "  1.  Ajouter un utilisateur"
    echo "  2.  Supprimer un utilisateur"
    echo "  3.  Ajouter plusieurs utilisateurs"
    echo "  4.  Supprimer plusieurs utilisateurs"
    echo "  5.  Lister les utilisateurs NIS"
    echo "  6.  Verifier un utilisateur"
    echo "  7.  Regenerer les maps NIS"
    echo "  8.  Quitter"
    echo "============================================="
}

# =============================================================================
# POINT D'ENTREE
# =============================================================================

main() {
    local choice="${1:-}"

    # Verifier les prerequis
    if ! is_root; then
        print_error "ce script doit etre execute en root."
        exit 1
    fi

    for cmd in useradd userdel passwd make ypcat getent; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_error "commande manquante: $cmd"
            exit 1
        fi
    done

    # Si argument fourni, executer directement
    if [[ -n "$choice" ]]; then
        case "$choice" in
            1|add_user)
                add_user "${2:-}"
                ;;
            2|delete_user)
                delete_user "${2:-}"
                ;;
            3|add_multiple)
                add_multiple_users
                ;;
            4|delete_multiple)
                delete_multiple_users
                ;;
            5|list_users)
                list_nis_users
                ;;
            6|verify_user)
                verify_user
                ;;
            7|regenerate_maps)
                regenerate_nis_maps
                ;;
            8|quit|exit)
                exit 0
                ;;
            *)
                print_error "operation invalide: $choice"
                echo "Operations: 1|add_user, 2|delete_user, 3|add_multiple, 4|delete_multiple, 5|list_users, 6|verify_user, 7|regenerate_maps, 8|quit"
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
            1|add_user) add_user ;;
            2|delete_user) delete_user ;;
            3|add_multiple) add_multiple_users ;;
            4|delete_multiple) delete_multiple_users ;;
            5|list_users) list_nis_users ;;
            6|verify_user) verify_user ;;
            7|regenerate_maps) regenerate_nis_maps ;;
            8|quit|exit) exit 0 ;;
            *) print_error "Choix invalide: $choice" ;;
        esac
    done
}

main "$@"