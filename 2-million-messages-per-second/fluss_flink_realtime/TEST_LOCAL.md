<!--
 Licensed to the Apache Software Foundation (ASF) under one or more
 contributor license agreements.  See the NOTICE file distributed with
 this work for additional information regarding copyright ownership.
 The ASF licenses this file to You under the Apache License, Version 2.0
 (the "License"); you may not use this file except in compliance with
 the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
-->


# Local Testing Guide

This guide explains how to test the Fluss producer and Flink job locally with the minimal schema.

## Prerequisites

1. **Maven** - For building the JAR
2. **Fluss 0.8.0** - Extracted to `demos/demo/deploy_local_kind_fluss/fluss-0.8.0-incubating/`
3. **Flink 1.20.3** (optional) - For running Flink job locally
4. **Java 11+** - For running Java applications

## Quick Test (Automated)

Run the automated test script:

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS
./demos/demo/fluss_flink_realtime_demo/test-local.sh
```

This script will:
1. Build the demo JAR
2. Start Fluss local cluster
3. Create table with 48 buckets
4. Start producer (instance 0, 100K devices)
5. Start Flink aggregation job (if Flink is available)

## Manual Testing (Step-by-Step)

### Step 1: Build the JAR

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS
mvn -pl demos/demo/fluss_flink_realtime_demo -am clean package
```

### Step 2: Start Fluss Local Cluster

```bash
cd demos/demo/deploy_local_kind_fluss/fluss-0.8.0-incubating
./bin/local-cluster.sh start
```

Wait for Fluss to be ready (check coordinator on port 9123):
```bash
# Wait until this succeeds
nc -z localhost 9123
```

### Step 3: Create Table with 48 Buckets

```bash
cd /Users/vijayabhaskarv/IOT/FLUSS
java --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.nio=ALL-UNNAMED \
     --add-opens=java.base/java.time=ALL-UNNAMED \
     -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
     org.apache.fluss.benchmarks.setup.CreateTableWithBuckets \
     localhost:9123 iot sensor_readings 48 true
```

### Step 4: Start Producer

**Single instance (100K devices):**
```bash
java --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.nio=ALL-UNNAMED \
     --add-opens=java.base/java.time=ALL-UNNAMED \
     -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
     org.apache.fluss.benchmarks.producer.FlussSensorProducerAppMultiInstance \
     --bootstrap localhost:9123 \
     --database iot \
     --table sensor_readings \
     --buckets 48 \
     --total-producers 1 \
     --instance-id 0 \
     --rate 10000 \
     --writer-threads 4 \
     --flush 10000 \
     --stats 50000
```

**Multiple instances (4 instances, 25K devices each):**

Terminal 1 (Instance 0):
```bash
java --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.nio=ALL-UNNAMED \
     --add-opens=java.base/java.time=ALL-UNNAMED \
     -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
     org.apache.fluss.benchmarks.producer.FlussSensorProducerAppMultiInstance \
     --bootstrap localhost:9123 \
     --database iot \
     --table sensor_readings \
     --buckets 48 \
     --total-producers 4 \
     --instance-id 0 \
     --rate 50000 \
     --writer-threads 4
```

Terminal 2 (Instance 1):
```bash
# Same command but --instance-id 1
--instance-id 1
```

Terminal 3 (Instance 2):
```bash
# Same command but --instance-id 2
--instance-id 2
```

Terminal 4 (Instance 3):
```bash
# Same command but --instance-id 3
--instance-id 3
```

### Step 5: Start Flink Job

**If Flink is installed locally:**

```bash
# Start Flink cluster (if not running)
cd /Users/vijayabhaskarv/IOT/FLUSS/flink-1.20.3
./bin/start-cluster.sh

# Submit Flink job
./bin/flink run \
    -c org.apache.fluss.benchmarks.flink.FlinkSensorAggregatorJob \
    /Users/vijayabhaskarv/IOT/FLUSS/demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
    --bootstrap localhost:9123 \
    --database iot \
    --table sensor_readings \
    --window-minutes 1
```

**View Flink UI:**
- Open http://localhost:8081 in browser
- Check job status and metrics

### Step 6: Verify Data

**Check Fluss table:**
```bash
java --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.nio=ALL-UNNAMED \
     --add-opens=java.base/java.time=ALL-UNNAMED \
     -cp demos/demo/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar \
     org.apache.fluss.benchmarks.inspect.FlussTableLogPeek localhost:9123 iot sensor_readings 10
```

**Check Flink job output:**
- The Flink job will print aggregated records every 20,000 records
- Check Flink UI for job metrics and backpressure

## Schema Verification

The producer writes only these 8 fields to Fluss:
- `sensor_id` (INT)
- `sensor_type` (INT)
- `temperature` (DOUBLE)
- `humidity` (DOUBLE)
- `pressure` (DOUBLE)
- `battery_level` (DOUBLE)
- `status` (INT)
- `timestamp` (BIGINT)

The Flink job reads these fields and adds default values for remaining fields at the sink level, matching JDBCFlinkConsumer.java behavior.

## Cleanup

```bash
# Stop producer (Ctrl+C or kill PID)

# Stop Flink cluster
cd /Users/vijayabhaskarv/IOT/FLUSS/flink-1.20.3
./bin/stop-cluster.sh

# Stop Fluss cluster
cd demos/demo/deploy_local_kind_fluss/fluss-0.8.0-incubating
./bin/local-cluster.sh stop
```

