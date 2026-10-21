# ShopVibe: Real-Time CDC Pipeline

Ingestão de pedidos em tempo real para um e-commerce: **PostgreSQL → Debezium (CDC) → Kafka → MinIO (camada bronze)**.
100% containerizado com Docker Compose e **sem nenhuma linha de código de aplicação**: o pipeline inteiro é configuração.

> Projeto desenvolvido para o MBA (caso de uso ShopVibe). Os números da empresa são fictícios.

## O problema

A ShopVibe processa cerca de 15 mil pedidos por dia, com picos de 20x na Black Friday. Hoje os dados chegam ao BI em lote (uma vez por dia), o que causou venda sem estoque, fraude descoberta tarde e carrinhos abandonados sem reação.
Este projeto implementa a **primeira etapa** da solução: capturar cada mudança no banco e armazenar o evento bruto, em segundos.

## Arquitetura

```
PostgreSQL ──(WAL)──> Debezium ──> Kafka ──> Kafka Connect (S3 Sink) ──> MinIO (bronze)
 inventory           (source)     tópicos                                 bucket "bronze"
```

| Camada | Tecnologia | Papel |
|---|---|---|
| Origem | PostgreSQL | Banco transacional (schema `inventory`) |
| Captura | Debezium (Kafka Connect source) | Lê o log de transações (WAL) e publica cada mudança |
| Mensageria | Apache Kafka + Schema Registry | Armazena e distribui os eventos |
| Ingestão | Kafka Connect S3 Sink | Grava os eventos no data lake |
| Armazenamento | MinIO (compatível com S3) | Camada bronze, para reprocessamento |
| Apoio | AKHQ, pgAdmin, Jupyter | Inspeção de tópicos, do banco e exploração |

### Implementado x evolução

- **Implementado:** Postgres → Debezium → Kafka → MinIO (bronze).
- **Evolução (apenas desenhada):** bronze → silver → gold; processamento em streaming para painel de vendas ao vivo e alerta de fraude; cache de estoque para o site.

Diagrama completo: `docs/desenho-solucao.png`

## Pré-requisitos

- Docker Desktop (com Docker Compose)
- Git
- PowerShell ou outro terminal

## Como executar

**1. Clone e configure o ambiente**

```powershell
git clone https://github.com/MatheusBarreto123/shopvibe-realtime-cdc-pipeline.git
cd shopvibe-realtime-cdc-pipeline
copy .env.example .env
```

Edite o `.env` se quiser trocar as credenciais de laboratório.

**2. Suba os contêineres**

```powershell
docker compose up -d --build
docker ps
```

**3. Registre os conectores**

Espere o Kafka Connect ficar `healthy` e crie os dois conectores a partir dos JSONs da pasta `conectores/`:

```powershell
docker exec kafkaConect curl -s -X PUT -H "Content-Type: application/json" --data "@/caminho/conector-postgres.json" http://localhost:8083/connectors/conector-postgres/config
docker exec kafkaConect curl -s -X PUT -H "Content-Type: application/json" --data "@/caminho/conector-minio-bronze.json" http://localhost:8083/connectors/conector-minio-bronze/config
```

> No `PUT /config`, o corpo é apenas o mapa de configurações, sem o envelope `{"name": ..., "config": ...}`.
> Ajuste o caminho dos arquivos conforme o volume montado no seu `docker-compose.yaml`.

**4. Verifique o status**

```powershell
docker exec kafkaConect curl -s http://localhost:8083/connectors/conector-postgres/status
docker exec kafkaConect curl -s http://localhost:8083/connectors/conector-minio-bronze/status
```

Os dois devem estar `RUNNING`.

## Demonstração: do pedido ao bronze

**1. Deixe um consumer aberto em um terminal** (mostra só os eventos novos):

```powershell
docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:29092 --topic shopvibe.inventory.orders
```

**2. Em outro terminal, crie um pedido na origem:**

```powershell
docker exec -it postgres psql -U postgres -d postgres -c "INSERT INTO inventory.orders (order_date, purchaser, quantity, product_id) VALUES (now(), 1001, 2, 102);"
```

**3. Observe o evento** com `"op":"c"` aparecer no consumer em poucos segundos.

**4. Confira o arquivo gravado no MinIO**, no bucket `bronze`, em `topics/shopvibe.inventory.orders/partition=0/`.

### Valores de `op` no evento Debezium

| op | Significado |
|---|---|
| `r` | leitura (snapshot inicial) |
| `c` | criação (INSERT) |
| `u` | atualização (UPDATE) |
| `d` | remoção (DELETE) |

## Comandos úteis

```powershell
# Tópicos existentes
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list

# Lag do sink no MinIO
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --describe --group connect-conector-minio-bronze

# Tabelas do schema de origem
docker exec -it postgres psql -U postgres -d postgres -c "\dt inventory.*"
```

## Decisões de projeto

- **CDC com Debezium** em vez de polling ou triggers: captura pelo log de transações, sem alterar a aplicação nem pesar no banco.
- **Kafka Connect** em vez de código próprio: menos código para manter e pipeline reprodutível via configuração.
- **MinIO + JSON como bronze:** armazenamento barato, compatível com S3 e reprocessável.
- **Sink S3 e `flush.size`:** o conector só fecha um arquivo ao juntar `flush.size` registros por partição. Em produção, o ideal é um valor alto combinado com `rotate.schedule.interval.ms`. Na demonstração usa-se um valor baixo para ver o resultado imediatamente.

Os ADRs completos ficam em `docs/adrs/`.

## Estrutura do repositório

```
.
├── conectores/
│   ├── conector-postgres.json        # Debezium (source)
│   └── conector-minio-bronze.json    # S3 Sink para o MinIO
├── docs/                             # ADRs e diagrama da solução
├── Dockerfile                        # Imagens customizadas
├── Dockerfile.connect
├── Dockerfile.jupyter
├── docker-compose.yaml
├── requirements.txt
├── .env.example
└── README.md
```

## Próximos passos

- Camada silver: achatar o envelope do Debezium (`after`, `op`, `ts_ms`), deduplicar e tratar deletes.
- Camada gold: vendas por hora, estoque atual por produto.
- Streaming: painel de vendas ao vivo e alerta de fraude a partir do tópico `orders`.
- Estoque confiável no site a partir do CDC de `products_on_hand`.

## Autor

**Matheus Barreto**: [GitHub](https://github.com/MatheusBarreto123)
