LOGIN       = rcarpio-
DATA_DIR    = /home/$(LOGIN)/data
COMPOSE     = docker compose -f srcs/docker-compose.yml

all: up

up:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	@$(COMPOSE) up -d --build

down:
	@$(COMPOSE) down

stop:
	@$(COMPOSE) stop

start:
	@$(COMPOSE) start

logs:
	@$(COMPOSE) logs -f

status:
	@$(COMPOSE) ps

clean: down
	@docker system prune -af

fclean:
	@$(COMPOSE) down -v --rmi all
	@docker system prune -af --volumes
	@sudo rm -rf $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

re: fclean all

.PHONY: all up down stop start logs status clean fclean re