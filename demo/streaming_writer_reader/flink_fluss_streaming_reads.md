# Flink ↔︎ Fluss Streaming Job

This guide walks through a continuous log-table pipeline: Flink generates events, writes them into a Fluss log table, and a second Flink job/SQL session consumes the stream in real time.

## 1. Prerequisites

- `fluss-0.7.0` unpacked in `/Users/<user>/IOT/FLUSS/fluss-0.7.0`
- `flink-1.20.3` unpacked in `/Users/<user>/IOT/FLUSS/flink-1.20.3`
- `fluss-flink-1.20-0.7.0.jar` copied into `/Users/<user>/IOT/FLUSS/flink-1.20.3/lib/`

Flink dashboard: <http://localhost:8081>.

## 2. Start services

```bash
cd /Users/<user>/IOT/FLUSS/fluss-0.7.0
./bin/local-cluster.sh start         # ZooKeeper + CoordinatorServer + TabletServer

cd /Users/<user>/IOT/FLUSS/flink-1.20.3
./bin/start-cluster.sh               # JobManager + TaskManager

# Optional: add extra capacity so writer and reader can run together
./bin/taskmanager.sh start
```

## 3. Create the Fluss log table

```bash
cd /Users/<user>/IOT/FLUSS/flink-1.20.3
./bin/sql-client.sh
```

Run:

```sql
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;

CREATE DATABASE IF NOT EXISTS streaming_demo;
USE streaming_demo;

DROP TABLE IF EXISTS streaming_orders;
CREATE TABLE streaming_orders (
  order_id STRING,
  user_id STRING,
  quantity INT,
  amount DOUBLE,
  order_ts TIMESTAMP(3)
) WITH (
  'connector' = 'fluss',
  'table.type' = 'log',
  'bucket.num' = '4'
);
```

## 4. Start a continuous writer (datagen → Fluss)

In the SQL client, run:

```sql
USE CATALOG fluss_catalog;
USE streaming_demo;

CREATE TEMPORARY TABLE log_orders_source (
  order_id STRING,
  user_id STRING,
  quantity INT,
  amount DOUBLE,
  order_ts TIMESTAMP(3)
) WITH (
  'connector' = 'datagen',
  'rows-per-second' = '5',
  'fields.order_id.length' = '8',
  'fields.user_id.length' = '6',
  'fields.quantity.min' = '1',
  'fields.quantity.max' = '5',
  'fields.amount.min' = '10',
  'fields.amount.max' = '100'
);

SET 'execution.runtime-mode' = 'streaming';
SET 'sql-client.execution.result-mode' = 'tableau';

INSERT INTO streaming_orders
SELECT * FROM log_orders_source;
```

Leave this session running. It launches the Flink job `insert-into_fluss_catalog.streaming_demo.streaming_orders` that continuously populates the log table.

## 5. Attach a streaming reader

Open another SQL client session:

```bash
./bin/sql-client.sh
```

Execute:

```sql
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;
USE streaming_demo;

SET 'execution.runtime-mode' = 'streaming';
SET 'sql-client.execution.result-mode' = 'tableau';

SELECT * FROM streaming_orders;
```

Keep this CLI open; it prints `+I` rows as new events arrive. This mimics a message-consumer view. To run as a standalone job, route the stream to a sink (e.g., `print`, Kafka, filesystem).

## 6. Clean up

1. Cancel jobs (Ctrl+C in SQL sessions or `./bin/flink list` + `./bin/flink cancel <jobId>`).
2. Stop clusters:

```bash
cd /Users/<user>/IOT/FLUSS/flink-1.20.3
./bin/stop-cluster.sh
./bin/taskmanager.sh stop    # if extra TMs were started

cd /Users/<user>/IOT/FLUSS/fluss-0.7.0
./bin/local-cluster.sh stop
```

