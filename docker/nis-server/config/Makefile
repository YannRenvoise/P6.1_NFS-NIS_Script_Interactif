# =============================================================================
# NIS Makefile - Compilation des maps NIS
# =============================================================================
# Ce Makefile est utilise par 'make -C /var/yp' pour generer les maps NIS.
# Il definit les bases de donnees a compiler et leurs sources.
# =============================================================================

# Domain NIS
NISDOMAIN = localdomain

# Repertoire source (fichiers systeme)
DIR = /etc

# Maps a generer
# passwd.db  - base utilisateurs (source: /etc/passwd)
# group.db   - base groupes (source: /etc/group)
# shadow.db  - mots de passe hashes (source: /etc/shadow)

# Target par defaut: compiler toutes les maps
all: passwd.db group.db

# Map passwd
passwd.db: $(DIR)/passwd
	ypmake passwd

# Map group
group.db: $(DIR)/group
	ypmake group

# Map shadow (optionnelle - requiert /etc/shadow)
shadow.db: $(DIR)/shadow
	ypmake shadow

# Nettoyage
clean:
	rm -f *.db

.PHONY: all clean