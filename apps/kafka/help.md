kubectl run kafka-0 --rm -ti --image bitnami/kafka:3.1.0 -- bash

kafka-console-producer.sh \
  --topic test \
  --request-required-acks all \
  --bootstrap-server kafka-0.kafka-hs.kafka.svc.cluster.local:9092,kafka-1.kafka-hs.kafka.svc.cluster.local:9092,kafka-2.kafka-hs.kafka.svc.cluster.local:9092


kafka-console-consumer.sh \
  --topic test \
  --from-beginning \
  --bootstrap-server kafka-0.kafka-hs.kafka.svc.cluster.local:9092,kafka-1.kafka-hs.kafka.svc.cluster.local:9092,kafka-2.kafka-hs.kafka.svc.cluster.local:9092


kafka-topics.sh --describe \
  --topic test \
  --bootstrap-server kafka-0.kafka-hs.kafka.svc.cluster.local:9092,kafka-1.kafka-hs.kafka.svc.cluster.local:9092,kafka-2.kafka-hs.kafka.svc.cluster.local:9092



# Dentro de um pod kafka-client (com binários do Kafka)
kafka-topics.sh --bootstrap-server kafka-0.kafka-hs.kafka.svc.cluster.local:9092 --list

# Ou verificar se todos os brokers estão no cluster:

kafka-broker-api-versions.sh --bootstrap-server kafka-0.kafka-hs.kafka.svc.cluster.local:9092

