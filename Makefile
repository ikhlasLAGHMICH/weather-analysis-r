.PHONY: help install api clean data db-up db-down db-status db-schema db-reset database pipeline

COMPOSE := docker compose

help:
	@echo "Commandes disponibles :"
	@echo "  make install  - Restaurer les dépendances R"
	@echo "  make api      - Récupérer les données Open-Meteo"
	@echo "  make clean    - Nettoyer les données"
	@echo "  make data     - Exécuter API + nettoyage"
	@echo "  make db-up    - Démarrer PostgreSQL et attendre son état healthy"
	@echo "  make db-down  - Arrêter PostgreSQL sans supprimer les données"
	@echo "  make db-status - Afficher l'état du service PostgreSQL"
	@echo "  make db-schema - Réappliquer explicitement le schéma SQL"
	@echo "  make db-reset - DESTRUCTIF : supprimer le conteneur et son volume"
	@echo "  make database - Charger le CSV nettoyé dans PostgreSQL"
	@echo "  make pipeline - Exécuter data, PostgreSQL, schéma et import"

install:
	Rscript -e 'renv::restore()'

api:
	Rscript R/01_api.R

clean:
	Rscript R/02_cleaning.R

data: api clean
	@echo "Pipeline de données terminé."

db-up:
	@test -f .env || (echo "Erreur : copiez .env.example vers .env." && exit 1)
	$(COMPOSE) up -d --wait postgres

db-down:
	$(COMPOSE) down

db-status:
	$(COMPOSE) ps

db-schema: db-up
	$(COMPOSE) exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"' < sql/schema.sql

db-reset:
	@echo "ATTENTION : suppression du volume PostgreSQL et de toutes ses données."
	$(COMPOSE) down --volumes

database: db-schema
	Rscript R/03_database.R

pipeline: data database
	@echo "Pipeline API → nettoyage → PostgreSQL terminé."
