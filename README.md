# redis.docker

redis container with auto-clustering capabilities (kind of super powers)!

This image relies on two main variables for clustering: `CLUSTER_NAME` and `CLUSTER_HOSTS`.

## Environment variables

* `CLUSTER_NAME` - You should give a name to your cluster and place it here.


* `RUNNING_MODE` - This variable could be set with values: `cluster` and `standalone`.
  - Defaults to `cluster` if `CLUSTER_NAME` is set and non-empty, otherwise it will always default to `cluster`.


* `CLUSTER_HOSTS` - Here you should place a cluster fqdn or IP plus port, separated.
  - If empty, or unable to connect to hosts, container will act as the first one on the cluster.
  - Defaults to ` ` (empty string).
  - Examples:
    - `10.0.0.10:4423,10.0.0.11:4423,10.0.0.12:4423`
    - `local.skydns.redis.clustername:1234`


* `CLUSTER_CONNECT_TIMEOUT` - seconds it should wait for each host before elects itself as the first one on the cluster.
  - Defaults to `5`.


* `CLUSTER_REPLICAS` - number of replica servers
  - Defaults to `1`.


* `PORT` - port where redis should be listening on.
  - Defaults to `6379`.


* `LOG_LEVEL` - log level to be specified on servers configs.
  - Defaults to `notice`;


## Container startup explained

- `RUNNING_MODE` is set as `cluster`
- Container tries to ping `CLUSTER_HOSTS`
  - if any of them respond to ping, `RUNNING_MODE` is set to `cluster`
- `redis` configs are updated and service is started
- if `RUNNING_MODE` is `cluster`
  - `redis-sentinel` configs are updated and service is started
  - `redis/tool/cluster`

## Running on CoreOS

I've added `redis@.service` fleet unit file on this repo in case you want to use with CoreOS. This unit relies on `skydns` for service discovery, so it will only work with it, sorry. :)

Submit this unit into CoreOS before starting launching instances:
```bash
fleetctl submit redis@.service
```

### Launching an instance

We use unit instance id variable to pass also `CLUSTER_NAME` configuration.

```bash
# redis@{CLUSTER_NAME}:{ID}

# Launching 4 nodes cluster for gitlab service.
fleetctl launch redis@gitlab:1;
fleetctl launch redis@gitlab:2;
fleetctl launch redis@gitlab:3;
fleetctl launch redis@gitlab:4;

# Now, if your dig your domain, it should return all instances:
dig @sky.dns.srv.ip gitlab.redis.skydns.local;

```

## Developing

### Building image

```bash
docker build -t cusspvz/redis .
```
