#!/bin/bash
set -Eeuo pipefail

# https://www.mongodb.com/docs/manual/tutorial/deploy-shard-cluster/
# Adapted from https://github.com/docker-library/mongo/blob/master/docker-entrypoint.sh
# and https://github.com/bitnami/containers/blob/main/bitnami/mongodb-sharded/8.0/debian-12/docker-compose.yml

# Setup replicaset key
mkdir -p /opt/mongo && echo $MONGODB_REPLICA_SET_KEY >/opt/mongo/keyfile && chown mongodb /opt/mongo/keyfile && chmod 400 /opt/mongo/keyfile

echo "
Starting mongodb
Sharding mode: $MONGODB_SHARDING_MODE
"

if [[ "$MONGODB_SHARDING_MODE" = "configsvr" ]]; then

  if [ ! -f /data/configdb/container_initialized ]; then
    # Start configuration server, standalone mode
    mongod --configsvr --replSet $MONGODB_REPLICA_SET_NAME --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME} &

    sleep 1

    echo "============================"
    echo "Initializing replicaset"
    echo "============================"
    # Initialize replicaset
    mongosh --port 27019 --eval "rs.initiate({_id: '$MONGODB_REPLICA_SET_NAME', configsvr: true, members: [{_id: 0, host: '${MONGODB_ADVERTISED_HOSTNAME}:27019'}]})"
    sleep 1
    echo "============================"
    echo "Shutting down config server"
    echo "============================"
    sleep 1
    mongosh --port 27019 <<-EOJS
    use admin;
    db.shutdownServer({timeoutSecs: 2});
EOJS

    sleep 1
    echo "============================"
    echo "Restarting config server"
    echo "============================"
    sleep 1

    # Mark cluster as initialized for faster reboot
    touch /data/configdb/container_initialized
  fi

  exec mongod --configsvr --replSet $MONGODB_REPLICA_SET_NAME --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME}
fi

if [[ "$MONGODB_SHARDING_MODE" = "shardsvr" ]]; then
  if [ ! -f /data/db/container_initialized ]; then
    mongod --shardsvr --replSet $MONGODB_REPLICA_SET_NAME --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME} &

    sleep 1

    echo "Initializing replicaset"
    # Initialize replicaset
    mongosh --port 27018 --eval "rs.initiate({_id: '$MONGODB_REPLICA_SET_NAME', members: [{_id: 0, host: '${MONGODB_ADVERTISED_HOSTNAME}:27018'}]})"
    sleep 1
    echo "============================"
    echo "Shutting down server"
    echo "============================"
    sleep 1
    mongosh --port 27018 <<-EOJS
    use admin;
    db.shutdownServer({timeoutSecs: 2});
EOJS

    sleep 1
    echo "============================"
    echo "Restarting server"
    echo "============================"
    sleep 1

    # Mark cluster as initialized for faster reboot
    touch /data/db/container_initialized
  fi

  exec mongod --shardsvr --replSet $MONGODB_REPLICA_SET_NAME --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME}
fi

if [[ "$MONGODB_SHARDING_MODE" = "mongos" ]]; then
  echo "Sleeping to wait for shards and config server to come up..."
  sleep 2
  wait-for-it ${MONGODB_CFG_PRIMARY_HOST}:27019 -t 60 -- echo "Config server is up!"
  mongos --configdb ${MONGODB_CFG_REPLICA_SET_NAME}/${MONGODB_CFG_PRIMARY_HOST}:27019 --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME} --port 27017 &

  echo "============================"
  echo "Creating shards"
  echo "============================"
  sleep 2
  mongosh <<-EOJS
    sh.addShard( "shard0/mongo-shard0:27018"); 
EOJS
  sleep 1
  mongosh <<-EOJS
    sh.addShard( "shard1/mongo-shard1:27018"); 
EOJS
  sleep 1

  echo "============================"
  echo "Creating user $MONGODB_USERNAME"
  echo "============================"
  mongosh <<-EOJS
    use admin;
    db.createUser({
					user: "$MONGODB_USERNAME", 
					pwd: "$MONGODB_PASSWORD",
					roles: [ { role: 'root', db: 'admin' } ]
				})
EOJS
  sleep 1

  if [ -f /docker-entrypoint-initdb.d/mongo-init.js ]; then
    echo "============================"
    echo "Executing mongo-init.js"
    echo "============================"
    mongosh --file /docker-entrypoint-initdb.d/mongo-init.js
  fi

  echo "============================"
  echo "Shutting down server"
  echo "============================"
  sleep 1
  mongosh <<-EOJS
    use admin;
    db.shutdownServer({timeoutSecs: 2});
EOJS

  sleep 1
  echo "============================"
  echo "Restarting server"
  echo "============================"
  sleep 1

  exec mongos --configdb ${MONGODB_CFG_REPLICA_SET_NAME}/${MONGODB_CFG_PRIMARY_HOST}:27019 --bind_ip localhost,127.0.0.1,${MONGODB_ADVERTISED_HOSTNAME} --port 27017

fi
