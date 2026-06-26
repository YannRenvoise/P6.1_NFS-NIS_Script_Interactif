# Documentation: gestion_users_nis.sh

## Overview

Script interactif de gestion des utilisateurs dans un environnement NFS/NIS. Permet de créer, supprimer, lister et vérifier des comptes utilisateurs avec des home directories sur NFS et une authentification via NIS.

## Requirements

- Execution en root (EUID == 0)
- Commandes: useradd, userdel, passwd, make, ypcat, getent
- Service NIS actif (ypserv)
- NFS mount sur /srv/nfs/home

## Configuration

```bash
NFS_HOME_ROOT="/srv/nfs/home"  # Racine des home directories NFS
NIS_MAP_DIR="/var/yp"           # Repertoire des maps NIS
```

## Comptes Proteges (DANGEROUS_USERS)

26 comptes systeme proteges qui ne peuvent pas etre modifies:
root, nobody, daemon, bin, sys, sync, games, man, lp, mail, news, uucp, proxy, www-data, backup, list, irc, _apt, systemd-network, systemd-resolve

## Validation des Noms

Regex: `^[a-z_][a-z0-9_-]*[$]?$`
- Premier caractere: lettre minuscule ou underscore
- Caracteres suivants: lettres minuscules, chiffres, underscore, tiret
- Caractere final optionnel: dollar (pour comptes NIS)

## Menu Interactif

1. Ajouter un utilisateur
2. Supprimer un utilisateur
3. Ajouter plusieurs utilisateurs
4. Supprimer plusieurs utilisateurs
5. Lister les utilisateurs NIS
6. Verifier un utilisateur
7. Regenerer les maps NIS
8. Quitter

## Fonctions

### Utilitaires

- `print_error()` - Affiche erreur sur stderr
- `print_info()` - Affiche info sur stdout
- `pause()` - Pause interactive
- `is_root()` - Verifie privileges root
- `require_root()` - Exige root, quitte sinon
- `check_required_commands()` - Verifie commandes externes
- `is_dangerous_user()` - Verifie compte protege
- `is_valid_username()` - Valide nom utilisateur
- `user_exists_local()` - Verifie existence locale
- `user_exists_nis()` - Verifie existence NIS
- `confirm()` - Question oui/non
- `prepare_nfs_home()` - Creer home NFS
- `ensure_nfs_home_root()` - Creer racine NFS
- `regenerate_nis_maps()` - Regenerer maps NIS
- `show_client_checks()` - Afficher commandes verification client

### Principales

- `add_user()` - Creer utilisateur avec home NFS et propagation NIS
- `delete_user()` - Supprimer utilisateur et optionnellement home NFS
- `add_multiple_users()` - Creer plusieurs utilisateurs en batch
- `delete_multiple_users()` - Supprimer plusieurs utilisateurs en batch
- `list_nis_users()` - Lister utilisateurs NIS
- `verify_user()` - Verifier utilisateur (local + NIS)
- `show_menu()` - Afficher menu interactif
- `main()` - Point d'entree, boucle menu