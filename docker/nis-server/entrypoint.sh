#!/usr/bin/env bash
set -o nounset
set -o pipefail

# =============================================================================
# NIS Server Entry Point
# =============================================================================
# Demarre les services NIS (portmapper, ypserv, ypbind) et maintient
# le container actif.
# =============================================================================

NIS_DOMAIN="${NIS_DOMAIN:-localdomain}"

echo "Info: configuration NIS - domain: ${NIS_DOMAIN}"

# 1. Definir le domain NIS
echo "${NIS_DOMAIN}" > /etc/default/nisdomainname

# 2. Demarrer le portmapper (RPC bind)
/usr/sbin/rpcbind -w 2>/dev/null || /sbin/rpcbind -w 2>/dev/null
echo "Info: rpcbind demarre"

# 3. Configurer ypserv pour ecouter sur toutes les interfaces
echo "ypserv: ALL" > /etc/yp/yp.conf 2>/dev/null || true

# 4. Demarrer ypserv
/usr/sbin/ypserv 2>/dev/null
echo "Info: ypserv demarre"

# 5. Initialiser les maps NIS avec les utilisateurs locaux
if [[ -f /var/yp/Makefile ]]; then
    make -C /var/yp 2>/dev/null || true
    echo "Info: maps NIS initialisees"
else
    echo "Erreur: Makefile NIS absent"
fi

# 6. Demarrer ypbind (s'abonner au serveur NIS - auto-binding)
/usr/sbin/ypbind 2>/dev/null || true
echo "Info: ypbind demarre"

# 7. Verifier les services
echo
echo "Services NIS actifs:"
rpcinfo -p 2>/dev/null || true
echo

# 8. Maintenir le container actif
# Utiliser tail sur /dev/null pour garder le container vivant
# Le script manage_users.sh peut etre execute via: docker exec
tail -f /dev/null