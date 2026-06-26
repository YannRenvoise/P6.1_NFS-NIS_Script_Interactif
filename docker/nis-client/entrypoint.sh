#!/usr/bin/env bash
set -o nounset
set -o pipefail

# =============================================================================
# NIS Client Entry Point
# =============================================================================
# Demarre ypbind (client NIS), monte le NFS home directory, et maintient
# le container actif.
# =============================================================================

NIS_DOMAIN="${NIS_DOMAIN:-localdomain}"

echo "Info: configuration NIS client - domain: ${NIS_DOMAIN}"

# 1. Definir le domain NIS
echo "${NIS_DOMAIN}" > /etc/default/nssdomainname 2>/dev/null || true

# 2. Demarrer le portmapper (necessary for NIS client)
/usr/sbin/rpcbind -w 2>/dev/null || /sbin/rpcbind -w 2>/dev/null || true
echo "Info: rpcbind demarre"

# 3. Demarrer ypbind (client NIS - se connecte au serveur NIS)
/usr/sbin/ypbind 2>/dev/null || true
echo "Info: ypbind demarre (connexion au serveur NIS)"

# 4. Attendre que ypbind se connecte (max 10 secondes)
echo "Info: attente connexion ypbind..."
for i in $(seq 1 10); do
    if ypcat passwd >/dev/null 2>&1; then
        echo "Info: connexion NIS etablie apres ${i}s"
        break
    fi
    sleep 1
done

# 5. Monter le NFS home directory depuis nfs-server
echo "Info: montage NFS home depuis nfs-server..."
mount -t nfs nfs-server:/srv/nfs/home /home 2>/dev/null || \
mount -t nfs 172.20.0.3:/srv/nfs/home /home 2>/dev/null || true

if [[ -d /home ]]; then
    print_info "NFS home monte: /home"
else
    print_error "echec montage NFS home"
    echo "Info: /home inexistant (NFS non monte)"
fi

# 6. Verifier la configuration NIS
echo
echo "=== Configuration NIS client ==="
echo "Domain: $(cat /etc/default/nisdomainname 2>/dev/null || echo 'inconnu')"
echo "yp.conf:"
cat /etc/yp/yp.conf 2>/dev/null || true
echo
echo "nsswitch.conf (passwd/group):"
grep -E '^(passwd|group):' /etc/nsswitch.conf 2>/dev/null || true
echo

# 7. Verifier la connexion NIS
echo "=== Verification NIS ==="
if ypcat passwd >/dev/null 2>&1; then
    print_info "connexion NIS OK"
    echo "Utilisateurs NIS (aperçu):"
    ypcat passwd 2>/dev/null | cut -d: -f1,3,6 | head -20
else
    print_error "connexion NIS echouee (ypcat indisponible)"
fi

# 8. Verifier le montage NFS
echo
echo "=== Verification NFS ==="
if mount | grep -q "/home"; then
    print_info "/home monte via NFS"
    df -h /home 2>/dev/null || true
else
    print_error "/home non monte"
fi

# 9. Maintenir le container actif
tail -f /dev/null