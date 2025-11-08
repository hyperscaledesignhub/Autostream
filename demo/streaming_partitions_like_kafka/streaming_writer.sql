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
