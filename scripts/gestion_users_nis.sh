#!/usr/bin/env bash

set -u

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

pause() {
    read -r -p "Appuyer sur Entree pour continuer..."
}

main() {
    local choice

    while true; do
        show_menu
        read -r -p "Choix: " choice

        case "$choice" in
            1) echo "Ajout utilisateur"; pause ;;
            2) echo "Suppression utilisateur"; pause ;;
            3) echo "Ajout multiple"; pause ;;
            4) echo "Suppression multiple"; pause ;;
            5) echo "Liste utilisateurs NIS"; pause ;;
            6) echo "Verification utilisateur"; pause ;;
            7) echo "Regeneration maps NIS"; pause ;;
            8) exit 0 ;;
            *) echo "Choix invalide"; pause ;;
        esac
    done
}

main "$@"
