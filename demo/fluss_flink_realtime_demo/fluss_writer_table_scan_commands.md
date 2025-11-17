# Fluss Writer / Table Scan Commands

Working directory for all commands:

```
cd /Users/vijayabhaskarv/IOT/FLUSS
```

## 1. Build the demo jar

```
mvn -pl demos/demo/fluss_flink_realtime_demo -am clean package
```

Output artifact:
```
demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar
```

## 2. Start / stop Fluss 0.8.0 local cluster

Start:
```
fluss-0.8.0-incubating/bin/local-cluster.sh start
```

Stop:
```
fluss-0.8.0-incubating/bin/local-cluster.sh stop
```

## 3. Producer commands

Continuous stream (Ctrl+C to stop):
```
java -jar demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9123 \
  --database iot \
  --table sensor_readings \
  --buckets 12 \
  --rate 2000 \
  --flush 5000 \
  --stats 20000   # log throughput every 20k records (optional)
```

Limit by count or duration:
```
java -jar demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9123 --database iot --table sensor_readings --count 50000

java -jar demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9123 --database iot --table sensor_readings --duration 5M
```
Add `--stats <records>` to control how often the producer logs overall/windowed throughput.

## 4. Flink SQL client (metadata check)

```
flink-1.20.3/bin/sql-client.sh -e "CREATE CATALOG fluss WITH ('type'='fluss','bootstrap.servers'='localhost:9123'); \
  USE CATALOG fluss; SHOW DATABASES;"
```

## 5. CLI helpers bundled in the jar

### List databases / tables
```
java -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  com.example.fluss.inspect.FlussMetadataInspector localhost:9123
```
Optional single database:
```
java -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  com.example.fluss.inspect.FlussMetadataInspector localhost:9123 iot
```

### Peek change log records

```
java --add-opens=java.base/java.nio=ALL-UNNAMED \
  -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  com.example.fluss.inspect.FlussTableLogPeek localhost:9123 iot sensor_readings 5
```
(Change `5` to print more/less records.)

### Peek primary-key snapshot rows

```
java --add-opens=java.base/java.nio=ALL-UNNAMED \
  -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  com.example.fluss.inspect.FlussPrimaryKeySnapshotPeek localhost:9123 iot sensor_readings 5
```
(Reads current table snapshot; only supports non-partitioned primary-key tables.)

## 6. Flink aggregation job

(Requires Flink cluster running in `flink-1.20.3`)
```
flink-1.20.3/bin/flink run \
  -c com.example.fluss.flink.FlinkSensorAggregatorJob \
  demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
  --bootstrap localhost:9123 --database iot --table sensor_readings --window-minutes 1
```
