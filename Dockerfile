
ARG CONFLUENT_VERSION

FROM confluentinc/cp-kafka-connect:${CONFLUENT_VERSION}

# Versões dos plugins
ARG DEBEZIUM_CONNECTOR_VERSION=2.6.1
ARG S3_SINK_VERSION=10.5.5

USER root

RUN confluent-hub install --no-prompt \
    debezium/debezium-connector-postgresql:${DEBEZIUM_CONNECTOR_VERSION} \
    && confluent-hub install --no-prompt \
    debezium/debezium-connector-sqlserver:${DEBEZIUM_CONNECTOR_VERSION} \
    && confluent-hub install --no-prompt \
    confluentinc/kafka-connect-s3:${S3_SINK_VERSION}

# Diretório em que o Kafka Connect carrega os plugins
ENV CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/confluent-hub-components

USER appuser
