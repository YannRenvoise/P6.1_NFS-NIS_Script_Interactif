#!/usr/bin/env bash
set -o nounset
set -o pipefail

# =============================================================================
# NFS Server Entry Point
# =============================================================================
# Demarre les services NFS et maintient le container actif.
# Exporte /srv/nfs/home avec exportfs.
# =============================================================================

echo "Info: configuration NFS"

# 1. Exporter le repertoire /srv/nfs/home
# -r: recursif
# -s: sync
# -no_root_squash: ne pas mapper root->nobody (utile pour NIS)
# -no_subtree_check: desactiver la verification subtree
exportfs -r -o sync,no_root_squash,no_subtree_check /srv/nfs/home 2>/dev/null || \
    exportfs -r 2>/dev/null || true
echo "Info: /srv/nfs/home exporte"

# 2. Demarrer le portmapper
/usr/sbin/rpcbind -w 2>/dev/null || /sbin/rpcbind -w 2>/dev/null
echo "Info: rpcbind demarre"

# 3. Demarrer le service NFS
/usr/sbin/service nfs-kernel-server start 2>/dev/null || \
    /usr/sbin/rpc.mountd 2>/dev/null || true
echo "Info: NFS server demarre"

# 4. Demarrer le NFS daemon
/usr/sbin/rpc.nfsd 2>/dev/null || true
echo "Info: rpc.nfsd demarre"

# 5. Verifier les exports
echo
echo "Exports NFS actifs:"
exportfs -v 2>/dev/null || true
echo

# 6. Verifier les services RPC
echo "Services RPC actifs:"
rpcinfo -p 2>/dev/null || true
echo

# 7. Maintenir le container actif
tail -f /dev/null