.DEFAULT_GOAL := build

PORTS:="7006,7007"

build:
	dotnet restore dapr-dotnet-pub-sub.sln
	dotnet build dapr-dotnet-pub-sub.sln

upgrade: build
	@cd consumer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package
	@cd producer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package

run: build
	dapr run -f .

stop-dapr:
	dapr stop -f .

stop-local-dapr:
	docker stop redis dapr_scheduler dapr_placement dapr_redis dapr_zipkin

# Kill processes running on multiple ports
stop-apps:
	@if [ -z "$(PORTS)" ]; then \
		echo "Usage: make stop-apps PORTS=\"<port1> <port2> <port3> ...\""; \
	else \
		for PORT in $(PORTS); do \
			echo "Checking for processes using port $$PORT..."; \
			if PIDS=$$(lsof -t -i:$$PORT) && [ -n "$$PIDS" ]; then \
				echo "Found processes using port $$PORT: $$PIDS"; \
				echo "Killing processes..."; \
				kill -9 $$PIDS; \
				echo "Processes on port $$PORT killed."; \
			else \
				echo "No processes found using port $$PORT."; \
			fi; \
		done; \
	fi

stop: stop-dapr stop-apps
	echo "All stopped."
	
#runk: @ Run Kafka
runk:
	@ docker compose --file docker-compose-kafka.yml up 

#stopk: @ Stop Kafka
stopk:
	@ docker compose --file docker-compose-kafka.yml down --remove-orphans --volumes