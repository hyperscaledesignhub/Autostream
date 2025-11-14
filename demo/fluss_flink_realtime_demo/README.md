# Fluss + Flink Realtime Demo

This demo replaces the `Pulsar → Flink → ClickHouse` leg from the `RealtimeDataPlatform`
repository with a Fluss-native setup:

1. A Java producer (`FlussSensorProducerApp`) writes synthetic IoT sensor updates to a
   Fluss primary-key table.
2. A Flink streaming job (`FlinkSensorAggregatorJob`) reads the same table via the Fluss
   connector, performs 1-minute tumbling aggregations, and prints aggregated metrics.

The schema, windowing logic, and KPIs mirror the original `realtime-platform-1million-events`
pipeline so you can compare behaviour side-by-side.

## Prerequisites

* Build Fluss 0.8.0 artifacts locally (they are not yet published to Maven Central):

  ```bash
  cd /Users/vijayabhaskarv/IOT/FLUSS/demos/demo/deploy_local_kind_fluss/fluss-0.8.0-incubating
  ./mvnw -pl \
    fluss-common,fluss-rpc,fluss-client,fluss-flink-common,fluss-flink-1.20 \
    -am clean install -DskipTests
  ```

* Have a Fluss cluster running. The Kind deployment created previously
  (`deploy_fluss_kind.sh`) exposes the coordinator on `localhost:9124`.

* Flink 1.20 distribution available locally (the same one used for previous demos).

## Build the demo jar

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS
mvn -pl demos/demo/fluss_flink_realtime_demo -am clean package
```

The shaded artifact is written to
`demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar`.

## 1. Start the Fluss producer

The producer ensures the `iot.sensor_readings` table exists (primary key on `sensor_id`,
12 buckets by default) and streams random sensor updates.

```bash
java \
  -jar demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9124 \
  --database iot \
  --table sensor_readings \
  --buckets 12 \
  --rate 5000 \
  --flush 5000
```

Useful flags:

| Flag | Description | Default |
|------|-------------|---------|
| `--bootstrap` | Coordinator address (`host:port`) | `localhost:9124` |
| `--database`  | Target Fluss database | `iot` |
| `--table`     | Target Fluss table | `sensor_readings` |
| `--buckets`   | Number of table buckets | `12` |
| `--sensors`   | Size of simulated sensor fleet | `10000` |
| `--rate`      | Records per second (0 = unthrottled) | `5000` |
| `--count`     | Stop after N records (omit for continuous) | continuous |
| `--duration`  | Stop after duration (e.g. `5M`, `30S`) | indefinite |
| `--flush`     | Flush interval in records | `5000` |

The application installs a shutdown hook, so `Ctrl+C` performs a final flush.

## 2. Run the Flink aggregation job

Submit the job with the same shaded jar. The job registers a Fluss catalog, reads the
primary-key table, assigns event-time watermarks, and emits 1-minute aggregates.

```bash
/opt/flink-1.20.3/bin/flink run \
  -c com.example.fluss.flink.FlinkSensorAggregatorJob \
  /Users/vijayabhaskarv/IOT/FLUSS/demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9124 \
  --database iot \
  --table sensor_readings \
  --window-minutes 1
```

The `PrintSink` reveals lines such as:

```
SensorAggregate{sensorId=sensor-000042, window=[2025-11-13T10:15:00Z,2025-11-13T10:16:00Z), avgTemp=24.71, avgHumidity=68.32, avgPressure=1009.14, avgBattery=72.10, status=ONLINE}
```

Each record corresponds to the metrics that the ClickHouse sink used to materialize
in the original pipeline.

## 3. Verifying end-to-end flow

1. Start the producer (Step 1) – it will continuously upsert sensor state.
2. Launch the Flink job (Step 2). After ~60 seconds you should see the first aggregate
   printed for each active sensor. Because Fluss retains both the KV snapshot and the
   change log, the job restarts with exactly-once semantics out of the box.
3. If desired, query the table directly via the Flink SQL client:

   ```sql
   CREATE CATALOG fluss WITH (
     'type' = 'fluss',
     'bootstrap.servers' = 'localhost:9124',
     'default-database' = 'iot'
   );
   USE CATALOG fluss;
   SELECT sensor_id, temperature, battery_level, event_time FROM sensor_readings LIMIT 5;
   ```

This setup demonstrates a full "Fluss-only" replacement for the Pulsar + ClickHouse
realtime leg, while keeping the schema, aggregation window, and metrics identical to
`RealtimeDataPlatform/realtime-platform-1million-events`.
