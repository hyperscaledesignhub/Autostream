# Streaming with Kafka-like Partitions (Fluss + Flink)

This guide walks you through recreating the multi-shard writer/reader demo so you can watch Flink writing to and reading from multiple Fluss buckets (shards) just like Kafka partitions.

---

## 1. Start Fluss and Flink locally

```bash
cd ./fluss-0.7.0
./bin/local-cluster.sh start

cd ./flink-1.20.3
./bin/start-cluster.sh
```

Optional: add extra TaskManagers if you want more slots (helpful when running separate writer and reader jobs):

```bash
./bin/taskmanager.sh start
# repeat if you want additional TaskManagers
```

Flink dashboard is available at <http://localhost:8081>.

---

## 2. Create or reset the Fluss table

Launch the SQL client:

```bash
cd ./flink-1.20.3
./bin/sql-client.sh
```

Run the following statements (choose your desired shard count by changing `'bucket.num'`):

```sql
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;

CREATE DATABASE IF NOT EXISTS demo;
USE demo;

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
  'bucket.num' = '8'        -- set to 4 if you want four buckets instead
);
```

Exit the SQL client with `QUIT;` when finished.

---

## 3. Prepare the streaming writer script

Create the writer SQL file (this example uses parallelism 4 and 20 rows/sec):

```bash
cat >./streaming_writer.sql <<'EOSQL'
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;
USE demo;

SET 'parallelism.default' = '4';
SET 'execution.runtime-mode' = 'streaming';

CREATE TEMPORARY TABLE log_orders_source (
  order_id STRING,
  user_id STRING,
  quantity INT,
  amount DOUBLE,
  order_ts TIMESTAMP(3)
) WITH (
  'connector' = 'datagen',
  'rows-per-second' = '20',
  'fields.order_id.length' = '12',
  'fields.user_id.length' = '8',
  'fields.quantity.min' = '1',
  'fields.quantity.max' = '10',
  'fields.amount.min' = '10',
  'fields.amount.max' = '200'
);

INSERT INTO streaming_orders
SELECT * FROM log_orders_source;
EOSQL
```

Submit the writer job in detached mode:

```bash
cd ./flink-1.20.3
./bin/sql-client.sh -f ../streaming_writer.sql --detached
```

Confirm it is running:

```bash
./bin/flink list
```

---

## 4. Prepare the streaming reader script

Create the reader SQL file:

```bash
cat >./streaming_reader.sql <<'EOSQL'
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;
USE demo;

SET 'parallelism.default' = '4';
SET 'execution.runtime-mode' = 'streaming';
SET 'sql-client.execution.result-mode' = 'tableau';

CREATE TEMPORARY TABLE console_sink (
  order_id STRING,
  user_id STRING,
  quantity INT,
  amount DOUBLE,
  order_ts TIMESTAMP(3)
) WITH (
  'connector' = 'print'
);

INSERT INTO console_sink
SELECT * FROM streaming_orders;
EOSQL
```

Submit the reader job:

```bash
./bin/sql-client.sh -f ../streaming_reader.sql --detached
```

Verify both writer and reader jobs are running:

```bash
./bin/flink list
```

---

## 5. Observe shard assignments and output

- **TaskManager logs** (print sink output):
  ```bash
  tail -f ./log/flink-*-taskexecutor-*.out
  ```
  You will see lines like `1> +I[...]`, `2> +I[...]`, etc. The prefix indicates the reader subtask handling those buckets.

- **Flink dashboard**: open the reader job, drill into the operator "Source: streaming_orders -> Sink: console_sink", then inspect the subtasks tab to confirm throughput per shard.

- **Fluss tablets** (optional):
  ```bash
  cd ../fluss-0.7.0
  ./bin/fluss-console.sh tablets
  ```
  This lists each bucket (`log-<tableId>-<bucketId>`) with its current tablet server and row counts.

---

## 6. Variations

- Set `'bucket.num' = '4'` when recreating the table if you want four buckets; keep job parallelism 4 so each subtask owns exactly one shard.
- To watch rows directly in the SQL client instead of logs, run the reader interactively (no `--detached`) and execute `SELECT * FROM streaming_orders;`.

---

## 7. Clean up

Cancel jobs and stop services when you are done:

```bash
cd ./flink-1.20.3
./bin/flink list               # note job IDs
./bin/flink cancel <writerJobId>
./bin/flink cancel <readerJobId>
./bin/stop-cluster.sh

cd ../fluss-0.7.0
./bin/local-cluster.sh stop
```

This returns both Fluss and Flink to a clean state for the next run.
