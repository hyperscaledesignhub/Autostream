# Fluss + Flink Local Quickstart

This guide captures the exact steps we used to download the artifacts, start both clusters, create a Fluss-backed table from the Flink SQL Client, insert sample records, and query them back.

## 1. Download the binaries and connector

From `/Users/vijayabhaskarv/IOT/FLUSS` run the helper script (or the equivalent `curl` commands):

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS
chmod +x download_fluss_flink.sh  # one-time
./download_fluss_flink.sh
```

Artifacts fetched:

- `fluss-0.7.0-bin.tgz`
- `flink-1.20.3-bin-scala_2.12.tgz`
- `fluss-flink-1.20-0.7.0.jar`

## 2. Extract Fluss and Flink

```bash
tar -xzf fluss-0.7.0-bin.tgz
tar -xzf flink-1.20.3-bin-scala_2.12.tgz
```

Resulting directories:

- `fluss-0.7.0`
- `flink-1.20.3`

## 3. Start the Fluss local cluster

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS/fluss-0.7.0
./bin/local-cluster.sh start
```

This launches ZooKeeper, the coordinator, and a tablet server locally.

## 4. Install the Flink connector JAR

```bash
cp /Users/vijayabhaskarv/IOT/FLUSS/fluss-flink-1.20-0.7.0.jar \
   /Users/vijayabhaskarv/IOT/FLUSS/flink-1.20.3/lib/
```

The connector must be in Flink’s `lib/` before you start the cluster so the SQL client can discover the `fluss` connector.

## 5. Start the Flink standalone cluster

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS/flink-1.20.3
./bin/start-cluster.sh
```

The Flink dashboard is now available at <http://localhost:8081>.

## 6. Use the Flink SQL Client to work with Fluss

Launch the client:

```bash
./bin/sql-client.sh
```

Then execute the following statements to create a catalog, table, insert data, and query it back:

```sql
CREATE CATALOG IF NOT EXISTS fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'localhost:9123'
);
USE CATALOG fluss_catalog;

CREATE DATABASE IF NOT EXISTS quickstart;
USE quickstart;

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  order_id STRING,
  user_id STRING,
  num_items INT,
  total_amount DOUBLE,
  PRIMARY KEY (order_id) NOT ENFORCED
) WITH (
  'connector' = 'fluss',
  'table.type' = 'primary-key',
  'table.primary-key.fields' = 'order_id',
  'bucket.num' = '4'
);

SET 'execution.runtime-mode' = 'batch';
SET 'sql-client.execution.result-mode' = 'tableau';

INSERT INTO orders VALUES
  ('o-1','u-1',1,10.5),
  ('o-2','u-2',2,25.0),
  ('o-3','u-1',3,42.75);

SELECT * FROM orders WHERE order_id = 'o-1';
SELECT * FROM orders LIMIT 10;

QUIT;
```

Notes:

- The `connector`, `table.type`, and `table.primary-key.fields` options ensure Flink routes reads/writes to Fluss.
- Queries that scan the table must run in batch mode unless Lakehouse tiering is configured.

## 7. Stop the services when finished

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS/flink-1.20.3
./bin/stop-cluster.sh

cd /Users/vijayabhaskarv/IOT/FLUSS/fluss-0.7.0
./bin/local-cluster.sh stop
```

This shuts down both Flink and Fluss cleanly.

