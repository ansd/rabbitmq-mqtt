## 1:1 Topology

This directory compares memory usage for the following workload:
* 200,000 MQTT clients in total (100,000 MQTT publishers and 100,000 MQTT subscribers)
* Each publisher publishes 1 MQTT application message with 64 bytes payload and QoS 0 every 2 minutes to exactly 1 QoS 0 subscriber
