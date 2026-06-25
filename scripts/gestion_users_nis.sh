#!/usr/bin/env bash

set -o nounset
set -o pipefail

NFS_HOME_ROOT="/srv/nfs/home"
NIS_MAP_DIR="/var/yp"

readonly NFS_HOME_ROOT
readonly NIS_MAP_DIR

DANGEROUS_USERS=(
    root nobody daemon bin sys sync games man lp mail news uucp proxy
    www-data backup list irc _apt systemd-network systemd-resolve
)

REQUIRED_COMMANDS=(useradd userdel passwd make ypcat getent)

print_error() {
    echo "Erreur: $*" >&2
}

print_info() {
    echo "Info: $*"
}

pause() {
    read -r -p "Appuyer sur Entree pour continuer..."
}

is_root() {
    [[ "${EUID}" -eq 0 ]]
}

require_root() {
    if ! is_root; then
        print_error "ce script doit etre lance en root."
        exit 1
    fi
}

check_required_commands() {
    local missing=0
    local command_name

    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "commande manquante: $command_name"
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi
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

user_exists_local() {
    local username="$1"

    getent passwd "$username" >/dev/null 2>&1
}

user_exists_nis() {
    local username="$1"

    ypcat passwd 2>/dev/null | cut -d: -f1 | grep -Fxq "$username"
}

prepare_nfs_home() {
    local username="$1"
    local home_dir="${NFS_HOME_ROOT}/${username}"

    if [[ ! -d "$NFS_HOME_ROOT" ]]; then
        print_info "creation du dossier racine NFS: $NFS_HOME_ROOT"
        mkdir -p "$NFS_HOME_ROOT" || return 1
    fi

    if [[ ! -d "$home_dir" ]]; then
        print_info "creation du home NFS: $home_dir"
        mkdir -p "$home_dir" || return 1
    fi

    chown "$username:$username" "$home_dir" 2>/dev/null || chown "$username" "$home_dir"
    chmod 700 "$home_dir"
}

ensure_nfs_home_root() {
    if [[ ! -d "$NFS_HOME_ROOT" ]]; then
        print_info "creation du dossier racine NFS: $NFS_HOME_ROOT"
        mkdir -p "$NFS_HOME_ROOT"
    fi
}

regenerate_nis_maps() {
    echo
    print_info "regeneration des maps NIS..."

    if [[ ! -d "$NIS_MAP_DIR" ]]; then
        print_error "dossier NIS absent: $NIS_MAP_DIR"
        return 1
    fi

    if make -C "$NIS_MAP_DIR"; then
        print_info "maps NIS regenerees."
        return 0
    fi

    print_error "echec regeneration maps NIS."
    return 1
}

show_client_checks() {
    local username="$1"

    echo
    echo "Commandes de verification cote client:"
    echo "  ypcat passwd | grep ${username}"
    echo "  getent passwd ${username}"
    echo "  su - ${username}"
}

add_user() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur a ajouter: " username
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

    if ! ensure_nfs_home_root; then
        print_error "creation racine NFS impossible: $NFS_HOME_ROOT"
        return 1
    fi

    if ! useradd -m -d "${NFS_HOME_ROOT}/${username}" "$username"; then
        print_error "creation utilisateur impossible: $username"
        return 1
    fi

    if ! prepare_nfs_home "$username"; then
        print_error "preparation home NFS impossible pour $username"
        return 1
    fi

    echo "Definition du mot de passe pour $username"
    if ! passwd "$username"; then
        print_error "mot de passe non defini pour $username"
        return 1
    fi

    regenerate_nis_maps
    show_client_checks "$username"
}

confirm() {
    local question="$1"
    local answer

    read -r -p "${question} [o/N]: " answer
    [[ "$answer" == "o" || "$answer" == "O" || "$answer" == "oui" || "$answer" == "OUI" ]]
}

delete_home_if_requested() {
    local username="$1"
    local home_dir="${NFS_HOME_ROOT}/${username}"

    if [[ -d "$home_dir" ]] && confirm "Supprimer le home NFS ${home_dir} ?"; then
        rm -rf -- "$home_dir"
        print_info "home NFS supprime: $home_dir"
    fi
}

delete_user() {
    local username="${1:-}"

    if [[ -z "$username" ]]; then
        read -r -p "Nom utilisateur a supprimer: " username
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

    if ! confirm "Confirmer suppression de ${username} ?"; then
        print_info "suppression annulee."
        return 1
    fi

    if ! userdel "$username"; then
        print_error "suppression utilisateur impossible: $username"
        return 1
    fi

    delete_home_if_requested "$username"
    regenerate_nis_maps
}

add_multiple_users() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms a ajouter separes par des espaces: " -a users

    for username in "${users[@]}"; do
        echo
        echo "Ajout de $username"
        if add_user "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume ajout: ${success} succes, ${failure} echec(s)."
}

delete_multiple_users() {
    local users
    local username
    local success=0
    local failure=0

    read -r -p "Noms a supprimer separes par des espaces: " -a users

    for username in "${users[@]}"; do
        echo
        echo "Suppression de $username"
        if delete_user "$username"; then
            ((success++))
        else
            ((failure++))
        fi
    done

    echo
    echo "Resume suppression: ${success} succes, ${failure} echec(s)."
}

list_nis_users() {
    local tmp_file

    tmp_file="$(mktemp)" || {
        print_error "creation fichier temporaire impossible."
        return 1
    }

    if ypcat passwd >"$tmp_file" 2>/dev/null; then
        cut -d: -f1,3,6 "$tmp_file"
        rm -f "$tmp_file"
        return 0
    fi

    rm -f "$tmp_file"
    print_error "ypcat passwd indisponible."
    echo "Alternative cote serveur:"
    awk -F: -v min_uid=1000 '$3 >= min_uid { print $1 ":" $3 ":" $6 }' /etc/passwd
}

verify_user() {
    local username

    read -r -p "Nom utilisateur a verifier: " username

    if ! is_valid_username "$username"; then
        print_error "nom utilisateur invalide: $username"
        return 1
    fi

    echo
    echo "Verification locale / getent:"
    if getent passwd "$username"; then
        print_info "utilisateur trouve localement ou via NSS."
    else
        print_error "utilisateur absent via getent."
    fi

    echo
    echo "Verification NIS:"
    if user_exists_nis "$username"; then
        ypcat passwd 2>/dev/null | grep -E "^${username}:"
        print_info "utilisateur trouve dans NIS."
    else
        print_error "utilisateur absent dans NIS ou ypcat indisponible."
    fi
}

show_menu() {
    clear
    echo "Gestion utilisateurs NFS/NIS"
    echo "1. Ajouter un utilisateur"
    echo "2. Supprimer un utilisateur"
    echo "3. Ajouter plusieurs utilisateurs"
    echo "4. Supprimer plusieurs utilisateurs"
    echo "5. Lister les utilisateurs NIS"
    echo "6. Verifier un utilisateur"
    echo "7. Regenerer les maps NIS"
    echo "8. Quitter"
    echo
}

main() {
    local choice

    require_root
    check_required_commands

    while true; do
        show_menu
        read -r -p "Choix: " choice

        case "$choice" in
            1) add_user; pause ;;
            2) delete_user; pause ;;
            3) add_multiple_users; pause ;;
            4) delete_multiple_users; pause ;;
            5) list_nis_users; pause ;;
            6) verify_user; pause ;;
            7) regenerate_nis_maps; pause ;;
            8) exit 0 ;;
            *) echo "Choix invalide"; pause ;;
        esac
    done
}

main "$@"
