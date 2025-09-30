.DEFAULT_GOAL := build

PORTS:="3530,3531,3532,5230,5231,5232,7006,7007"

build:
	dotnet restore dapr-dotnet-pub-sub.sln
	dotnet build dapr-dotnet-pub-sub.sln

update: build
	@cd consumer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package
	@cd producer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package

run: build stop
	dapr run -f .

#post:
#	curl -X POST http://localhost:5232/v1.0/publish/message-pubsub-kafka/incoming-messages -d '{"id": "e9cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "1"}'

post:
	curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "a1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "1"}'
	curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "b1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "2"}'
	curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z", "type": "0"}'
	curl -X POST http://localhost:5232/send -H "Content-Type: application/json" -d '{"id": "c1cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-26T02:52:04.835Z"}'
	curl -X POST http://localhost:5232/sendasbytes -H "Content-Type: application/json" -d '{"id": "b2cdd036-c529-4bf9-bd59-d7148ef9237d", "timeStamp": "2025-09-27T02:52:04.835Z", "type": "1"}'

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