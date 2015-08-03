#!/bin/bash
IP=`ip addr show eth0 | grep "inet " | cut -d '/' -f 1 | cut -d ' ' -f 6`;

# Functions

sex_it () {
    echo $2;
    exit $1;
}

# Global vars

if [ "$LOG_LEVEL" == "" ]; then
    LOG_LEVEL="notice";
fi


# redis server configs

if [ "$REDIS_SERVER_HOST" == "" ]; then
    REDIS_SERVER_HOST="0.0.0.0";
fi
if [ "$REDIS_SERVER_PORT" == "" ]; then
    REDIS_SERVER_PORT="6379";
fi

# redis sentinel configs

if [ "$REDIS_SENTINEL_HOST" == "" ]; then
    REDIS_SENTINEL_HOST="0.0.0.0";
fi
if [ "$REDIS_SENTINEL_PORT" == "" ]; then
    REDIS_SENTINEL_PORT="2${REDIS_SERVER_PORT}";
fi

# Cluster related

if [ "$CLUSTER_CONNECT_TIMEOUT" == "" ]; then
    CLUSTER_CONNECT_TIMEOUT=5;
fi

if [ "$CLUSTER_REPLICAS" == "" ]; then
    CLUSTER_REPLICAS=1;
fi

# Handle RUNNING_MODE defaults
if [ "$RUNNING_MODE" != "cluster" ] && [ "$RUNNING_MODE" != "standalone" ]; then
    if [ "$CLUSTER_NAME" != "" ]; then
        RUNNING_MODE="cluster";
    else
        RUNNING_MODE="standalone";
    fi
fi

# Start logging configs gathered
echo "Starting cusspvz/redis.docker at $IP";
echo "(Running in $RUNNING_MODE mode)";
echo;

if [ "$RUNNING_MODE" == "cluster" ]; then
    echo "CLUSTER NAME: $CLUSTER_NAME";
    echo "CLUSTER HOSTS: $CLUSTER_HOSTS";
fi

# Minor improvements

    # Disable thp
    echo never > /sys/kernel/mm/transparent_hugepage/enabled;


# Start docker
REDIS_CONFIG="
daemonize no
pidfile /var/run/redis/server.pid
port $REDIS_SERVER_PORT
bind $REDIS_SERVER_HOST
timeout 0
loglevel $LOG_LEVEL
databases 16

save 900 1
save 300 10
save 60 10000

rdbcompression yes
dbfilename dump.rdb
dir /var/lib/redis

";

if [ "$RUNNING_MODE" == "cluster" ]; then
REDIS_CONFIG="$REDIS_CONFIG
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly yes
"
fi

echo "Starting redis-server $REDIS_SERVER_HOST:$REDIS_SERVER_PORT...";
echo "$REDIS_CONFIG" > /etc/redis/redis.conf;
redis-server /etc/redis/redis.conf &
REDIS_SERVER_PID=$!;

sleep 5 && kill -0 $REDIS_SERVER_PID 2>/dev/null || sex_it 2 "Redis Server is not running...";


# In case we are working on cluster
if [ "$RUNNING_MODE" == "cluster" ]; then

    CLUSTER_STATE="new";

    # First start a sentinel instance
SENTINEL_CONFIG="
daemonize no
pidfile /var/run/redis/sentinel.pid
port $REDIS_SENTINEL_PORT
bind $REDIS_SENTINEL_HOST
timeout 0
loglevel $LOG_LEVEL
";

    echo "Starting redis-sentinel $REDIS_SENTINEL_HOST:$REDIS_SENTINEL_PORT...";
    echo "$SENTINEL_CONFIG" > /etc/redis/sentinel.conf
    redis-sentinel /etc/redis/sentinel.conf &
    REDIS_SENTINEL_PID=$!;

    sleep 5 && kill -0 $REDIS_SERVER_PID || sex_it 2 "Redis Sentinel is not running...";

    # If no CLUSTER_HOSTS is not specified, we assume this cluster is new
    if [ "$CLUSTER_HOSTS" != "" ]; then

        echo "Testing if cluster hosts are alive:";

        # On the other hand, lets try to reach our node friends, if we can
        # we just have to meet each other, otherwise, we will auto-elect.
        for CLUSTER_HOST in $( echo "$CLUSTER_HOSTS" | tr "," " " ); do
            echo -ne "- $CLUSTER_HOST ... ";

            nc -z -w$CLUSTER_CONNECT_TIMEOUT $( echo "$CLUSTER_HOST" | tr ":" " " ) 2>/dev/null && \
                echo "[alive]" || \
                echo "[dead]";

            if [ $? -eq 0 ]; then
                CLUSTER_STATE="existing";
            fi
        done;
    fi

    if [ "$CLUSTER_STATE" == "new" ]; then
        # If we are meant to initialize the cluster, lets do so...
        ./setup create $IP:$REDIS_SERVER_PORT;
    else
        ./setup add-node $IP:$REDIS_SERVER_PORT $CLUSTER_HOST;
    fi

        ./setup fix $CLUSTER_HOST 1>/dev/null 2>&1 <<EOF
yes
EOF

fi


# Keep up running while server is active while
    # Redis SERVER is up AND
      # we are running on standalone mode OR
      # Redis SENTINEL is running

while
    kill -0 $REDIS_SERVER_PID 2>/dev/null && ( \
        [ "$RUNNING_MODE" == "standalone" ] || \
        kill -0 $REDIS_SENTINEL_PID 2>/dev/null \
    );
do
    sleep 1;
done;

sex_it 0 "Exiting...";
