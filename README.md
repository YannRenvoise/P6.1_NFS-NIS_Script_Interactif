# P6.1 - Gestion d'utilisateurs NFS/NIS

Projet d'Administration Linux realise par Yann RENVOISE et Valentin MENON.

## Sujet

Creer un script Bash interactif permettant l'ajout et le retrait d'un ou plusieurs utilisateurs dans un environnement NFS/NIS.

L'environnement utilise deux distributions Debian sous WSL2 :

- `debian-nfs-server` : serveur NFS et NIS
- `debian-nfs-client` : client NFS/NIS

Le serveur exporte `/srv/nfs/home` et le client monte ce partage dans `/mnt/FromNFS`. Le domaine NIS utilise le nom `iut`.

## Prerequis

- Debian sous WSL2 avec `systemd` active dans `/etc/wsl.conf`
- Paquets NFS et NIS installes cote serveur
- Services serveur : `rpcbind`, `ypserv`, `yppasswdd`
- Services client : `rpcbind`, `ypbind`
- Domaine NIS : `iut`
- Export NFS serveur : `/srv/nfs/home`
- Maps NIS regenerables avec `make -C /var/yp`

## Structure

```text
.
├── README.md
├── scripts/
│   └── gestion_users_nis.sh
├── docs/
│   ├── rapport.tex
│   ├── images/
│   └── references/
├── tests/
│   └── sample_users.txt
└── .gitignore
```

## Utilisation prevue

Le script principal doit etre execute cote serveur NIS :

```bash
sudo bash scripts/gestion_users_nis.sh
```

Les verifications principales se font ensuite cote client :

```bash
ypcat passwd
getent passwd nomUtilisateur
su - nomUtilisateur
```

## Tests manuels

1. Lancer le script cote serveur :

```bash
sudo bash scripts/gestion_users_nis.sh
```

2. Ajouter l'utilisateur `demoNIS`.
3. Regenerer les maps NIS si le script ne l'a pas deja fait.
4. Cote client, verifier :

```bash
ypcat passwd | grep demoNIS
getent passwd demoNIS
su - demoNIS
```

5. Cote serveur, supprimer `demoNIS` avec le script.
6. Cote client, verifier que l'utilisateur n'apparait plus :

```bash
ypcat passwd | grep demoNIS
getent passwd demoNIS
```

## Todo

- [x] Initialiser la structure du projet
- [x] Preparer le README
- [ ] Creer le script interactif
- [ ] Ajouter les fonctions d'ajout et suppression
- [ ] Ajouter la regeneration des maps NIS
- [ ] Tester sur serveur et client WSL
- [ ] Rediger le rapport LaTeX complet
