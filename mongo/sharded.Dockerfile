FROM mongo:8.0.4


RUN apt-get update && apt-get install -y jq wait-for-it

COPY ./sharded/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY ./sharded/mongo-init.js /docker-entrypoint-initdb.d/mongo-init.js


