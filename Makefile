.PHONY: start-production stop-production start-staging stop-staging

start-production:
	docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --pull always

stop-production:
	docker compose -f deploy/docker-compose.yml down

start-staging:
	docker compose -f deploy/docker-compose.staging.yml --env-file deploy/.env.staging up -d --pull always

stop-staging:
	docker compose -f deploy/docker-compose.staging.yml down
