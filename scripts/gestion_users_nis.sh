#!/usr/bin/env bash
# =============================================================================
# Script: gestion_users_nis.sh
# Version: 1.0
# Description: Script interactif de gestion des utilisateurs dans un environnement
#              NFS (Network File System) / NIS (Network Information Service).
#              Permet de créer, supprimer, lister et vérifier des comptes utilisateurs
#              avec des home directories sur NFS et une authentification via NIS.
#
# Requirements:
#   - Execution en root (EUID == 0)
#   - Commandes: useradd, userdel, passwd, make, ypcat, getent
#   - Service NIS actif (ypserv)
#   - NFS mount sur /srv/nfs/home
#
# Utilisation:
#   sudo bash scripts/gestion_users_nis.sh
#
# Menu interactif avec 8 options:
#   1. Ajouter un utilisateur
#   2. Supprimer un utilisateur
#   3. Ajouter plusieurs utilisateurs (batch)
#   4. Supprimer plusieurs utilisateurs (batch)
#   5. Lister les utilisateurs NIS
#   6. Verifier un utilisateur (local + NIS)
#   7. Regenerer les maps NIS
#   8. Quitter
#
# Validation des noms d'utilisateur:
#   Regex: ^[a-z_][a-z0-9_-]*[$]?$
#   - Doit commencer par une lettre minuscule ou underscore
#   - Peut contenir lettres minuscules, chiffres, underscore, tiret
#   - Peut se terminer par un dollar (pour les comptes NIS)
#
# Comptes proteges (DANGEROUS_USERS):
#   26 comptes systeme qui ne peuvent pas etre modifies pour prevenir
#   les accidents (root, daemon, bin, sync, etc.)
#
# Author: Yann Renvoise
# Project: P6.1_NFS-NIS_Script_Interactif
# Date: 2026
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION - Chemins et constantes
# =============================================================================

# Racine du repertoire home partage via NFS
# Tous les home directories utilisateurs seront crees sous /srv/nfs/home/<username>
NFS_HOME_ROOT="/srv/nfs/home"

# Repertoire contenant les maps NIS (yp database)
# make -C /var/yp recompilera les maps passwd, group, etc.
NIS_MAP_DIR="/var/yp"

readonly NFS_HOME_ROOT
readonly NIS_MAP_DIR

# =============================================================================
# COMPTES PROTEGES (DANGEROUS_USERS)
# =============================================================================
# Liste des comptes systeme proteges. Ces comptes NE peuvent PAS etre:
#   - crees (si ils existent deja)
#   - supprimes
#   - modifies
# Protection contre les operations accidentelles sur des comptes critiques.

DANGEROUS_USERS=(
    root            # Superutilisateur - acces total au systeme
    nobody          # Utilisateur "nobody" - UID 65534, pour les processes sans privilege
    daemon          # Compte daemon - UID 1, pour les services systeme
    bin             # Compte bin - UID 2, fichiers binaires systeme
    sys             # Compte sys - UID 3, fichiers systeme
    sync            # Compte sync - UID 5, commande sync (synchronisation disque)
    games           # Compte games - UID 6, jeux systeme
    man             # Compte man - UID 7, pages de documentation
    lp              # Compte lp - UID 8, subsysteme d'impression
    mail            # Compte mail - UID 9, fichiers mail
    news            # Compte news - UID 10, subsysteme news
    uucp            # Compte uucp - UID 11, protocol UUCP (Unix-to-Unix Copy)
    proxy           # Compte proxy - UID 13, proxy server
    www-data        # Compte web - UID 33, serveur web (Apache/Nginx)
    backup          # Compte backup - UID 34, outil de backup
    list            # Compte list - UID 38, mailing list manager
    irc             # Compte irc - UID 39, serveur IRC
    _apt            # Compte apt - UID 100, gestionnaire de paquets APT
    systemd-network # Compte systemd-network - gestion reseau systemd
    systemd-resolve # Compte systemd-resolve - resolution DNS systemd
)

# =============================================================================
# COMMANDES EXTERNES REQUISES
# =============================================================================
# Chaque commande doit etre disponible dans $PATH pour que le script fonctionne.
# check_required_commands() verifie leur presence au demarrage.

REQUIRED_COMMANDS=(
    useradd   # Creer un compte utilisateur (equivalent de adduser)
    userdel   # Supprimer un compte utilisateur
    passwd    # Definir/modifier le mot de passe d'un utilisateur
    make      # Compiler les maps NIS (via Makefile dans /var/yp)
    ypcat     # Afficher le contenu d'une map NIS (ypcat passwd)
    getent    # Interroger les bases de données NSS (getent passwd <user>)
)

# =============================================================================
# FONCTIONS UTILITAIRES - Affichage et interaction
# =============================================================================

# --- print_error() ---
# Description: Affiche un message d'erreur sur stderr (flux d'erreur standard)
# Parameters:
#   $1...$n: Message d'erreur (supporte plusieurs arguments)
# Output: stderr - "Erreur: <message>"
# Usage: print_error "message d'erreur"
print_error() {
    echo "Erreur: $*" >&2
}

# --- print_info() ---
# Description: Affiche un message d'information sur stdout (flux standard)
# Parameters:
#   $1...$n: Message d'information (supporte plusieurs arguments)
# Output: stdout - "Info: <message>"
# Usage: print_info "message d'information"
print_info() {
    echo "Info: $*"
}

# --- pause() ---
# Description: Pause interactive - attend que l'utilisateur appuie sur Entree
# Parameters: aucun
# Output: stdout - prompt "Appuyer sur Entee pour continuer..."
# Usage: apres chaque operation du menu pour laisser l'utilisateur lire le resultat
pause() {
    read -r -p "Appuyer sur Entee pour continuer..."
}

# =============================================================================
# FONCTIONS UTILITAIRES - Verification des privileges
# =============================================================================

# --- is_root() ---
# Description: Verifie si le script est execute par l'utilisateur root (UID 0)
# Parameters: aucun
# Return: 0 (success) si EUID == 0, 1 (failure) sinon
# Note: EUID est l'Effective User ID - l'UID real de l'process courant
# Usage: if is_root; then ... fi
is_root() {
    [[ "${EUID}" -eq 0 ]]
}

# --- require_root() ---
# Description: Exige que le script soit execute en root. Quitte si non-root.
# Parameters: aucun
# Output: stderr - "Erreur: ce script doit etre lance en root."
# Exit: 1 si l'utilisateur n'est pas root
# Usage: appelee au debut de main() comme prerequis
require_root() {
    if ! is_root; then
        print_error "ce script doit etre lance en root."
        exit 1
    fi
}

# --- check_required_commands() ---
# Description: Verifie que toutes les commandes requises sont disponibles dans $PATH
# Parameters: aucun
# Output: stderr - "Erreur: commande manquante: <nom>" pour chaque commande absente
# Return: 0 si toutes les commandes sont presentes, 1 sinon
# Exit: 1 si une ou plusieurs commandes manquent
# Note: utilise 'command -v' pour chercher la commande dans $PATH
# Usage: appelee au debut de main() comme prerequis
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

# --- is_dangerous_user() ---
# Description: Verifie si un nom d'utilisateur fait partie de la liste des comptes proteges
# Parameters:
#   $1: nom d'utilisateur a verifier
# Return: 0 (success) si l'utilisateur est dans DANGEROUS_USERS, 1 (failure) sinon
# Note: comparaison exacte (==) avec chaque element de la liste
# Usage: if is_dangerous_user "$username"; then ... fi
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

# --- is_valid_username() ---
# Description: Valide le format d'un nom d'utilisateur selon les standards Unix/NIS
# Parameters:
#   $1: nom d'utilisateur a valider
# Return: 0 (success) si le nom est valide, 1 (failure) sinon
# Regex: ^[a-z_][a-z0-9_-]*[$]?$
#   ^          - debut de la chaine
#   [a-z_]     - premier caractere: lettre minuscule OU underscore
#   [a-z0-9_-]* - caracteres suivants: lettres minuscules, chiffres, underscore, tiret
#   [$]?       - caractere final optionnel: dollar (pour comptes NIS)
#   $          - fin de la chaine
# Regles:
#   - Pas de lettres majuscules
#   - Pas de caracteres speciaux (sauf _ et -)
#   - Pas de chiffres en premier caractere
#   - Longueur: 1 a ∞ (mais limite par le systeme, typiquement 32 chars)
# Usage: if is_valid_username "$username"; then ... fi
is_valid_username() {
    local username="$1"

    [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

# --- user_exists_local() ---
# Description: Verifie si un utilisateur existe dans la base locale (via NSS)
# Parameters:
#   $1: nom d'utilisateur a verifier
# Return: 0 (success) si l'utilisateur existe, 1 (failure) sinon
# Note: utilise getent qui interroge NSS (Name Service Switch) - peut consulter
#       /etc/passwd, NIS, LDAP, etc. selon la configuration nsswitch.conf
# Usage: if user_exists_local "$username"; then ... fi
user_exists_local() {
    local username="$1"

    getent passwd "$username" >/dev/null 2>&1
}

# --- user_exists_nis() ---
# Description: Verifie si un utilisateur existe specifiquement dans la map NIS passwd
# Parameters:
#   $1: nom d'utilisateur a verifier
# Return: 0 (success) si l'utilisateur existe dans NIS, 1 (failure) sinon
# Note: utilise ypcat passwd pour extraire la map NIS, puis cut pour extraire
#       le champ 1 (nom), puis grep -Fxq pour recherche exacte (case-sensitive)
#       -F: pattern fixe (pas regex)
#       -x: correspondance ligne entiere
#       -q: quiet (pas de sortie)
# Usage: if user_exists_nis "$username"; then ... fi
user_exists_nis() {
    local username="$1"

    ypcat passwd 2>/dev/null | cut -d: -f1 | grep -Fxq "$username"
}

# =============================================================================
# FONCTIONS UTILITAIRES - Gestion du repertoire NFS home
# =============================================================================

# --- prepare_nfs_home() ---
# Description: Creer et configurer le home directory NFS pour un utilisateur
# Parameters:
#   $1: nom d'utilisateur
# Output: stdout - messages d'information sur la creation
# Return: 0 (success) si tout est cree et configure, 1 (failure) sinon
# Actions:
#   1. Creer /srv/nfs/home si inexistant
#   2. Creer /srv/nfs/home/<username> si inexistant
#   3. Definir le propriétaire: <username>:<username> (ou <username> si groupe absent)
#   4. Definir les permissions: 700 (rwx------) - seul l'utilisateur acces
# Note: chown essaie d'abord avec groupe, fallback sans groupe si erreur
# Usage: prepare_nfs_home "$username"
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

# --- ensure_nfs_home_root() ---
# Description: Verifie et cree le repertoire racine NFS si inexistant
# Parameters: aucun (utilise NFS_HOME_ROOT)
# Output: stdout - message d'information si creation
# Return: 0 (success) toujours (pas de verification d'erreur)
# Note: version simplifiee de prepare_nfs_home - cree uniquement la racine
# Usage: ensure_nfs_home_root
ensure_nfs_home_root() {
    if [[ ! -d "$NFS_HOME_ROOT" ]]; then
        print_info "creation du dossier racine NFS: $NFS_HOME_ROOT"
        mkdir -p "$NFS_HOME_ROOT"
    fi
}

# =============================================================================
# FONCTIONS UTILITAIRES - NIS (Network Information Service)
# =============================================================================

# --- regenerate_nis_maps() ---
# Description: Regenerer les maps NIS en executant 'make' dans /var/yp
# Parameters: aucun (utilise NIS_MAP_DIR)
# Output: stdout - messages d'information sur la regeneration
# Return: 0 (success) si make reussit, 1 (failure) sinon
# Actions:
#   1. Verifier que /var/yp existe
#   2. Executer 'make -C /var/yp' qui lit le Makefile NIS
#   3. Le Makefile recompilera les maps: passwd.db, group.db, shadow.db, etc.
# Note: make -C change le repertoire avant execution
#       La map passwd.db est la base de donnees utilisateurs NIS
# Usage: regenerate_nis_maps
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

# --- show_client_checks() ---
# Description: Affiche les commandes de verification a executer sur les clients NIS
# Parameters:
#   $1: nom d'utilisateur a verifier
# Output: stdout - liste des commandes de verification
# Commands affichees:
#   ypcat passwd | grep <user>  - verifier dans la map NIS directe
#   getent passwd <user>         - verifier via NSS (local + NIS)
#   su - <user>                  - tester la connexion real
# Note: ces commandes doivent etre executees sur un client NIS pour verifier
#       que l'utilisateur a bien ete propage dans l'infrastructure NIS
# Usage: show_client_checks "$username"
show_client_checks() {
    local username="$1"

    echo
    echo "Commandes de verification cote client:"
    echo "  ypcat passwd | grep ${username}"
    echo "  getent passwd ${username}"
    echo "  su - ${username}"
}

# =============================================================================
# FONCTIONS PRINCIPALES - Gestion des utilisateurs
# =============================================================================

# --- add_user() ---
# Description: Creer un nouvel utilisateur avec home NFS et propagation NIS
# Parameters:
#   $1: nom d'utilisateur (optionnel - sinon demande interactive)
# Workflow:
#   1. Lire le nom ( depuis $1 ou prompt interactif)
#   2. Valider le nom (is_valid_username)
#   3. Verifier protection (is_dangerous_user)
#   4. Verifier absence (user_exists_local)
#   5. Creer racine NFS (ensure_nfs_home_root)
#   6. Creer compte utilisateur (useradd -m -d <home>)
#   7. Configurer home NFS (prepare_nfs_home)
#   8. Definir mot de passe (passwd)
#   9. Regenerer maps NIS (regenerate_nis_maps)
#   10. Afficher commandes de verification client (show_client_checks)
# Flags useradd:
#   -m: creer le home directory si inexistant
#   -d: specifier le chemin du home directory
# Return: 0 (success) si tout reussit, 1 (failure) sinon
# Usage: add_user [username]
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

# --- confirm() ---
# Description: Affiche une question et attend une reponse oui/non
# Parameters:
#   $1: question a afficher
# Output: stdout - prompt "${question} [o/N]: "
# Return: 0 (success/oui) si reponse = o, O, oui, OUI
#         1 (failure/non) sinon
# Note: reponse insensible a la case pour 'o'/'O', sensible pour 'oui'/'OUI'
# Usage: if confirm "question"; then ... fi
confirm() {
    local question="$1"
    local answer

    read -r -p "${question} [o/N]: " answer
    [[ "$answer" == "o" || "$answer" == "O" || "$answer" == "oui" || "$answer" == "OUI" ]]
}

# --- delete_home_if_requested() ---
# Description: Supprime le home NFS de l'utilisateur si confirme
# Parameters:
#   $1: nom d'utilisateur
# Output: stdout - message d'information si suppression
# Return: aucun (ne retourne pas de code)
# Actions:
#   1. Verifier que le home directory existe
#   2. Demander confirmation a l'utilisateur
#   3. Supprimer avec rm -rf -- si confirme
# Note: rm -rf -- supprime recursivement sans interpretation des arguments
#       Le -- previent les arguments commençant par '-' d'etre interpretes comme flags
# Usage: delete_home_if_requested "$username"
delete_home_if_requested() {
    local username="$1"
    local home_dir="${NFS_HOME_ROOT}/${username}"

    if [[ -d "$home_dir" ]] && confirm "Supprimer le home NFS ${home_dir} ?"; then
        rm -rf -- "$home_dir"
        print_info "home NFS supprime: $home_dir"
    fi
}

# --- delete_user() ---
# Description: Supprimer un utilisateur et optionnellement son home NFS
# Parameters:
#   $1: nom d'utilisateur (optionnel - sinon demande interactive)
# Workflow:
#   1. Lire le nom ( depuis $1 ou prompt interactif)
#   2. Valider le nom (is_valid_username)
#   3. Verifier protection (is_dangerous_user)
#   4. Verifier existence (user_exists_local)
#   5. Demander confirmation (confirm)
#   6. Supprimer compte (userdel)
#   7. Optionnellement supprimer home NFS (delete_home_if_requested)
#   8. Regenerer maps NIS (regenerate_nis_maps)
# Return: 0 (success) si tout reussit, 1 (failure) sinon
# Usage: delete_user [username]
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

# --- add_multiple_users() ---
# Description: Creer plusieurs utilisateurs en batch (lecture d'une liste)
# Parameters: aucun (lit la liste depuis prompt interactif)
# Output: stdout - messages pour chaque utilisateur + resume final
# Workflow:
#   1. Lire les noms separes par espaces (-a users = array)
#   2. Boucle sur chaque nom et appe add_user()
#   3. Compter succes/echecs
#   4. Afficher resume
# Return: aucun (ne retourne pas de code)
# Usage: add_multiple_users
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

# --- delete_multiple_users() ---
# Description: Supprimer plusieurs utilisateurs en batch (lecture d'une liste)
# Parameters: aucun (lit la liste depuis prompt interactif)
# Output: stdout - messages pour chaque utilisateur + resume final
# Workflow:
#   1. Lire les noms separes par espaces (-a users = array)
#   2. Boucle sur chaque nom et appe delete_user()
#   3. Compter succes/echecs
#   4. Afficher resume
# Return: aucun (ne retourne pas de code)
# Usage: delete_multiple_users
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

# --- list_nis_users() ---
# Description: Lister tous les utilisateurs de la map NIS passwd
# Parameters: aucun
# Output: stdout - liste des utilisateurs avec UID et home directory
# Format: username:UID:home_directory (separateur :)
# Workflow:
#   1. Creer fichier temporaire (mktemp)
#   2. Extraire ypcat passwd dans le fichier temporaire
#   3. Extraire champs 1 (nom), 3 (UID), 6 (home) avec cut
#   4. Supprimer fichier temporaire
#   5. Fallback: si ypcat indisponible, afficher /etc/passwd avec UID >= 1000
# Note: UID >= 1000 = utilisateurs reguliers (systeme a UID < 1000)
# Return: 0 (success) si ypcat fonctionne, 1 (failure) sinon
# Usage: list_nis_users
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

# --- verify_user() ---
# Description: Verifier l'existence d'un utilisateur en local et dans NIS
# Parameters: aucun (lit le nom depuis prompt interactif)
# Output: stdout - resultats de verification locale + NIS
# Workflow:
#   1. Lire le nom d'utilisateur
#   2. Valider le nom (is_valid_username)
#   3. Verification locale via getent passwd
#   4. Verification NIS via user_exists_nis + ypcat passwd | grep
# Format getent passwd: username:password:UID:GID:GECOS:home:shell
# Note: getent consulte NSS (nsswitch.conf) - peut inclure LDAP, LDAP, etc.
# Return: 0 (success) si tout reussit, 1 (failure) sinon
# Usage: verify_user
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

# =============================================================================
# MENU INTERACTIF
# =============================================================================

# --- show_menu() ---
# Description: Affiche le menu interactif principal
# Parameters: aucun
# Output: stdout - menu avec 8 options numerotees
# Note: clear efface l'ecran avant affichage du menu
# Options:
#   1. add_user          - Creer un utilisateur individuel
#   2. delete_user       - Supprimer un utilisateur individuel
#   3. add_multiple_users - Creer plusieurs utilisateurs (batch)
#   4. delete_multiple_users - Supprimer plusieurs utilisateurs (batch)
#   5. list_nis_users    - Lister tous les utilisateurs NIS
#   6. verify_user       - Verifier un utilisateur (local + NIS)
#   7. regenerate_nis_maps - Regenerer les maps NIS
#   8. exit              - Quitter le script
# Usage: show_menu
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

# =============================================================================
# FONCTION PRINCIPALE - Point d'entree du script
# =============================================================================

# --- main() ---
# Description: Point d'entree du script - initialise et boucle sur le menu
# Parameters: aucun (ignore les arguments via "$@")
# Workflow:
#   1. require_root - verifie privileges root
#   2. check_required_commands - verifie commandes externes
#   3. Boucle infinie:
#      a. show_menu - afficher menu
#      b. read choice - lire choix utilisateur
#      c. case/switch - executer fonction correspondante
#      d. pause - attendre Entee
#   4. exit 0 sur choix 8
# Note: set -o nounset empeche les variables non initialisees
#       set -o pipefail empeche les erreurs masquee dans les pipes
# Usage: main "$@" (appe automatiquement a la fin du script)
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

# Point d'entree - appe la fonction main avec tous les arguments
main "$@"
