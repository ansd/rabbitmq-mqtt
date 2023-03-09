## 1 Million Idle Connections

This directory compares memory usage for the following workload:
* 1,000,000 connections that only send MQTT Keep Alives (neither publish nor receive MQTT application messages)

Grafana panel `Memory used` uses following query:
```
rabbitmq_process_resident_memory_bytes * on(instance) group_left(rabbitmq_cluster, rabbitmq_node) rabbitmq_identity_info{namespace="$namespace"}
```
