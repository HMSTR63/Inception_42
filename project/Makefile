DATA_PATH_WP	= /Users/hmstr./data/wordpress
DATA_PATH_DB	= /Users/hmstr./data/mariadb

all: up

up:
	@echo "Starting inception..."
	@mkdir -p $(DATA_PATH_WP)
	@mkdir -p $(DATA_PATH_DB)
	@docker-compose -f srcs/docker-compose.yml up -d --build
	@echo "Done!"

down:
	@echo "Stopping inception..."
	@docker-compose -f srcs/docker-compose.yml down
	@echo "Done!"

clean: down
	@echo "Cleaning..."
	@docker system prune -f
	@echo "Done!"

fclean: down
	@echo "Full clean..."
	@docker system prune -af
	@docker volume rm $$(docker volume ls -q) 2>/dev/null || true
	@rm -rf $(DATA_PATH_WP)
	@rm -rf $(DATA_PATH_DB)
	@echo "Done!"

re-service:
	@docker-compos -f srcs/docker-compos.yml build $(service)
	@docker-compos -f srcs/docker-compos.yml up -d $(service)
re: fclean up

.PHONY: all up down clean fclean re
