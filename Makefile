.PHONY: help install api clean data db-up db-down db-status db-schema db-reset database pipeline analysis model test shiny all

COMPOSE := docker compose

help:
	@echo "Commandes disponibles :"
	@echo "  make install  - Restaurer les dependances R"
	@echo "  make api      - Recuperer les donnees Open-Meteo"
	@echo "  make clean    - Nettoyer les donnees"
	@echo "  make data     - Executer API + nettoyage"
	@echo "  make db-up    - Demarrer PostgreSQL et attendre son etat healthy"
	@echo "  make db-down  - Arreter PostgreSQL sans supprimer les donnees"
	@echo "  make db-status - Afficher l'etat du service PostgreSQL"
	@echo "  make db-schema - Reappliquer explicitement le schema SQL"
	@echo "  make db-reset - DESTRUCTIF : supprimer le conteneur et son volume"
	@echo "  make database - Charger le CSV nettoye dans PostgreSQL"
	@echo "  make pipeline - Executer data, PostgreSQL, schema et import"
	@echo "  make analysis - Lancer les visualisations (04_analysis.R)"
	@echo "  make model    - Entrainer les modeles ML et exporter results/"
	@echo "  make test     - Lancer tous les tests automatises (testthat)"
	@echo "  make shiny    - Lancer l'application Shiny"
	@echo "  make all      - Pipeline complet : data → DB → analyse → modele"

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
	@echo "Pipeline API -> nettoyage -> PostgreSQL termine."

analysis:
	Rscript R/04_analysis.R

model:
	Rscript R/05_model.R

test:
	Rscript tests/run_tests.R

shiny:
	Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"

all: pipeline analysis model
	@echo "Pipeline complet termine."
