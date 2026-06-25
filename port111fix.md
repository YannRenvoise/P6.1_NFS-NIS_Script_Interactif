# Contournement `rpcbind` / `ypbind` sous WSL

## Probleme observe

Sur le client Debian WSL, le service `rpcbind` peut apparaitre inactif avec `systemctl` :

```text
rpcbind.service - RPC bind portmap service
Active: inactive (dead)
TriggeredBy: rpcbind.socket
```

Dans certains cas, `rpcbind.socket` echoue car le port RPC `111` est deja occupe :

```text
Failed to create listening socket (0.0.0.0:111): Address already in use
```

Le probleme vient du fonctionnement de WSL avec `systemd` et les sockets RPC. `rpcbind` peut fonctionner en pratique, mais ne pas etre correctement considere actif par `systemd`.

## Impact sur NIS

Le service `ypbind` depend normalement de `rpcbind.service` :

```ini
Requires=rpcbind.service
After=network-online.target rpcbind.service
```

Sous WSL, cette dependance peut bloquer `ypbind`, meme si `rpcbind` est lance manuellement et repond avec `rpcinfo`.

## Solution utilisee

L'objectif est de lancer `rpcbind` manuellement, puis de demarrer une version adaptee de `ypbind` sans dependance stricte a `rpcbind.service`.

### 1. Copier le service `ypbind`

Sur le client :

```bash
sudo cp /usr/lib/systemd/system/ypbind.service /etc/systemd/system/ypbind-wsl.service
sudo nano /etc/systemd/system/ypbind-wsl.service
```

### 2. Modifier les dependances

Dans `/etc/systemd/system/ypbind-wsl.service`, remplacer :

```ini
Description=NIS Binding Service
Requires=rpcbind.service
After=network-online.target rpcbind.service
```

par :

```ini
Description=NIS Binding Service WSL
After=network-online.target
```

La ligne importante a supprimer est :

```ini
Requires=rpcbind.service
```

Il faut aussi retirer `rpcbind.service` de la ligne `After=`.

### 3. Recharger `systemd`

```bash
sudo systemctl daemon-reload
```

### 4. Lancer `rpcbind` manuellement

```bash
sudo pkill rpcbind
sudo rm -f /run/rpcbind.sock
sudo rpcbind -w
```

Verifier que `rpcbind` repond :

```bash
rpcinfo -p localhost
```

Une sortie correcte doit contenir le portmapper sur le port `111` :

```text
100000    4   tcp    111  portmapper
100000    4   udp    111  portmapper
```

### 5. Lancer `ypbind-wsl`

```bash
sudo systemctl start ypbind-wsl
sudo systemctl status ypbind-wsl
```

Le service doit etre actif :

```text
Active: active (running)
```

## Tests NIS

Verifier le domaine NIS :

```bash
domainname
cat /etc/defaultdomain
```

Resultat attendu :

```text
iut
```

Verifier la configuration client :

```bash
cat /etc/yp.conf
```

Exemple :

```text
domain iut server nfs-server
```

ou avec l'adresse IP du serveur :

```text
domain iut server 172.x.x.x
```

Tester les maps NIS :

```bash
ypcat passwd
ypcat passwd | grep demo
getent passwd demo
```

## Tests NFS

Le montage NFS peut fonctionner meme si NIS ne fonctionne pas completement.

Exemple cote client :

```bash
ls -l /mnt/FromNFS
```

Si un utilisateur est supprime cote serveur avec le script, son repertoire peut disparaitre du montage NFS cote client. Cela prouve que la partie NFS fonctionne.

Exemple observe :

```text
drwx------ 2 2005 2005 4096 Jun 25 18:52 demo
drwx------ 2 2003 2003 4096 Jun 25 14:44 testauto
```

Les nombres `2003`, `2005`, etc. indiquent que le client voit les UID/GID mais ne les resout pas en noms. Cela arrive quand NFS fonctionne mais que NIS/NSS ne resout pas les utilisateurs.

## Difference importante entre NFS et NIS

- NFS partage les fichiers et repertoires.
- NIS partage les informations utilisateurs et groupes.

Donc :

- si `/mnt/FromNFS` affiche les dossiers, NFS fonctionne ;
- si les proprietaires apparaissent en nombres (`2003`, `2005`), NIS ou `nsswitch.conf` ne resout pas encore les noms ;
- si `getent passwd demo` fonctionne, NIS est bien utilise par le client.

## Points a expliquer a l'oral


NFS fonctionne aussi : les homes apparaissent/disparaissent dans /mnt/FromNFS.

Le projet demande un script interactif d'ajout et retrait d'utilisateurs NFS/NIS. Le script est execute cote serveur. Il cree ou supprime les comptes, prepare les repertoires personnels NFS et regenere les maps NIS.

La partie NFS est validee si le client voit les repertoires dans `/mnt/FromNFS`.

La partie NIS est validee si le client voit les utilisateurs avec :

```bash
ypcat passwd
getent passwd nomUtilisateur
```

Sous WSL, `rpcbind` et `ypbind` peuvent etre instables avec `systemd`. C'est une limite de l'environnement WSL, pas du script. La map NIS est bien servie par le serveur et accessible depuis le client avec ypcat -d iut -h nfs-server passwd.byname.

Étapes à démontrer dans la présentation :

1. ajout d'un utilisateur cote serveur avec le script côté serveur;
2. regeneration des maps NIS ;
3. apparition du home dans `/mnt/FromNFS` côté client ;
4. afficher les nouveaux users avec `ls -l /mnt/FromNFS` côté client.

## Commandes utiles cote serveur

```bash
sudo systemctl status rpcbind
sudo systemctl status ypserv
sudo systemctl status yppasswdd
sudo make -C /var/yp
rpcinfo -p localhost
ypcat -d iut -h localhost passwd.byname
```

## Commandes utiles cote client

```bash
sudo rpcbind -w
sudo systemctl start ypbind-wsl
rpcinfo -p localhost
domainname
ypcat passwd
getent passwd demo
ls -l /mnt/FromNFS
```
