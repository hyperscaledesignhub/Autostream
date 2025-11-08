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
