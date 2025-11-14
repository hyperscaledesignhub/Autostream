package com.example.fluss.flink;

import com.example.fluss.model.SensorData;
import org.apache.flink.api.common.eventtime.SerializableTimestampAssigner;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.sink.PrintSinkFunction;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.Table;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.apache.flink.table.data.StringData;
import org.apache.flink.table.data.TimestampData;
import org.apache.flink.types.Row;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Objects;

/**
 * Flink streaming job that reads the primary-key table written by {@link
 * com.example.fluss.producer.FlussSensorProducerApp}, performs tumbling-window aggregations, and
 * prints the results. The logic mirrors the Pulsar → Flink → ClickHouse path from the original
 * RealtimeDataPlatform example but uses Fluss as both the source and storage.
 */
public final class FlinkSensorAggregatorJob {
    private static final Logger LOG = LoggerFactory.getLogger(FlinkSensorAggregatorJob.class);

    public static void main(String[] args) throws Exception {
        JobOptions options = JobOptions.parse(args);
        LOG.info("Starting Flink aggregation job with options: {}", options);

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        EnvironmentSettings settings = EnvironmentSettings.newInstance().inStreamingMode().build();
        StreamTableEnvironment tEnv = StreamTableEnvironment.create(env, settings);

        String catalogDdl = String.format(
                Locale.ROOT,
                "CREATE CATALOG %s WITH (\n"
                        + "  'type' = 'fluss',\n"
                        + "  'bootstrap.servers' = '%s',\n"
                        + "  'default-database' = '%s'\n)",
                options.catalog,
                options.bootstrap,
                options.database);
        tEnv.executeSql(catalogDdl);
        tEnv.executeSql("USE CATALOG " + options.catalog);
        tEnv.executeSql("USE " + options.database);

        Table sourceTable = tEnv.from(options.table);
        DataStream<Row> rowStream = tEnv.toDataStream(sourceTable);

        DataStream<SensorReading> sensorStream = rowStream.map(FlinkSensorAggregatorJob::toSensorReading);

        WatermarkStrategy<SensorReading> watermarkStrategy = WatermarkStrategy
                .<SensorReading>forBoundedOutOfOrderness(Duration.ofSeconds(5))
                .withTimestampAssigner((SerializableTimestampAssigner<SensorReading>) (element, recordTimestamp) ->
                        element.eventTime.toEpochMilli());

        SingleOutputStreamOperator<SensorReading> timedStream = sensorStream.assignTimestampsAndWatermarks(watermarkStrategy);

        SingleOutputStreamOperator<SensorAggregate> aggregates = timedStream
                .keyBy(reading -> reading.sensorId)
                .window(TumblingEventTimeWindows.of(Time.minutes(options.windowMinutes)))
                .aggregate(new SensorAggregateFunction(), new WindowEnricher());

        aggregates.addSink(new PrintSinkFunction<>(true));

        env.execute("Fluss Sensor Aggregation Job");
    }

    private static SensorReading toSensorReading(Row row) {
        String sensorId = asString(row.getField(0));
        String sensorType = asString(row.getField(1));
        String location = asString(row.getField(2));
        double temperature = asDouble(row.getField(3));
        double humidity = asDouble(row.getField(4));
        double pressure = asDouble(row.getField(5));
        double battery = asDouble(row.getField(6));
        String status = asString(row.getField(7));
        Instant eventTime = asInstant(row.getField(8));
        String manufacturer = asString(row.getField(9));
        String model = asString(row.getField(10));
        String firmware = asString(row.getField(11));
        double latitude = asDouble(row.getField(12));
        double longitude = asDouble(row.getField(13));

        SensorData.MetaData meta = new SensorData.MetaData(manufacturer, model, firmware, latitude, longitude);
        return new SensorReading(sensorId, sensorType, location, temperature, humidity, pressure, battery, status, eventTime, meta);
    }

    private static double asDouble(Object value) {
        if (value == null) {
            return 0D;
        }
        if (value instanceof Number) {
            return ((Number) value).doubleValue();
        }
        return Double.parseDouble(value.toString());
    }

    private static String asString(Object field) {
        if (field == null) {
            return null;
        }
        if (field instanceof String) {
            return (String) field;
        }
        if (field instanceof StringData) {
            return field.toString();
        }
        return Objects.toString(field, null);
    }

    private static Instant asInstant(Object field) {
        if (field instanceof Instant) {
            return (Instant) field;
        }
        if (field instanceof TimestampData) {
            return ((TimestampData) field).toInstant();
        }
        if (field instanceof java.sql.Timestamp) {
            return ((java.sql.Timestamp) field).toInstant();
        }
        throw new IllegalArgumentException("Unsupported timestamp type: " + field);
    }

    private record JobOptions(String bootstrap, String database, String table, String catalog, int windowMinutes) {
        private static JobOptions parse(String[] args) {
            String bootstrap = "localhost:9124";
            String database = "iot";
            String table = "sensor_readings";
            String catalog = "fluss";
            int window = 1;

            for (int i = 0; i < args.length; i++) {
                switch (args[i]) {
                    case "--bootstrap":
                        bootstrap = args[++i];
                        break;
                    case "--database":
                        database = args[++i];
                        break;
                    case "--table":
                        table = args[++i];
                        break;
                    case "--catalog":
                        catalog = args[++i];
                        break;
                    case "--window-minutes":
                        window = Integer.parseInt(args[++i]);
                        break;
                    default:
                        throw new IllegalArgumentException("Unknown argument: " + args[i]);
                }
            }

            return new JobOptions(bootstrap, database, table, catalog, window);
        }
    }

    private record SensorReading(
            String sensorId,
            String sensorType,
            String location,
            double temperature,
            double humidity,
            double pressure,
            double batteryLevel,
            String status,
            Instant eventTime,
            SensorData.MetaData metadata) {}

    private static class SensorAggregateFunction
            implements AggregateFunction<SensorReading, SensorAccumulator, SensorAccumulator> {

        @Override
        public SensorAccumulator createAccumulator() {
            return new SensorAccumulator();
        }

        @Override
        public SensorAccumulator add(SensorReading value, SensorAccumulator accumulator) {
            if (accumulator.count == 0) {
                accumulator.sensorId = value.sensorId;
                accumulator.sensorType = value.sensorType;
                accumulator.location = value.location;
                accumulator.metadata = value.metadata;
            }

            accumulator.count++;
            accumulator.temperatureSum += value.temperature;
            accumulator.temperatureMin = Math.min(accumulator.temperatureMin, value.temperature);
            accumulator.temperatureMax = Math.max(accumulator.temperatureMax, value.temperature);

            accumulator.humiditySum += value.humidity;
            accumulator.humidityMin = Math.min(accumulator.humidityMin, value.humidity);
            accumulator.humidityMax = Math.max(accumulator.humidityMax, value.humidity);

            accumulator.pressureSum += value.pressure;
            accumulator.pressureMin = Math.min(accumulator.pressureMin, value.pressure);
            accumulator.pressureMax = Math.max(accumulator.pressureMax, value.pressure);

            accumulator.batterySum += value.batteryLevel;
            accumulator.batteryMin = Math.min(accumulator.batteryMin, value.batteryLevel);
            accumulator.batteryMax = Math.max(accumulator.batteryMax, value.batteryLevel);

            if (accumulator.latestEventTime == null || value.eventTime.isAfter(accumulator.latestEventTime)) {
                accumulator.latestEventTime = value.eventTime;
                accumulator.latestStatus = value.status;
            }
            return accumulator;
        }

        @Override
        public SensorAccumulator merge(SensorAccumulator a, SensorAccumulator b) {
            if (a.count == 0) {
                return b;
            }
            if (b.count == 0) {
                return a;
            }

            SensorAccumulator result = new SensorAccumulator();
            result.sensorId = a.sensorId;
            result.sensorType = a.sensorType;
            result.location = a.location;
            result.metadata = a.metadata;

            result.count = a.count + b.count;

            result.temperatureSum = a.temperatureSum + b.temperatureSum;
            result.temperatureMin = Math.min(a.temperatureMin, b.temperatureMin);
            result.temperatureMax = Math.max(a.temperatureMax, b.temperatureMax);

            result.humiditySum = a.humiditySum + b.humiditySum;
            result.humidityMin = Math.min(a.humidityMin, b.humidityMin);
            result.humidityMax = Math.max(a.humidityMax, b.humidityMax);

            result.pressureSum = a.pressureSum + b.pressureSum;
            result.pressureMin = Math.min(a.pressureMin, b.pressureMin);
            result.pressureMax = Math.max(a.pressureMax, b.pressureMax);

            result.batterySum = a.batterySum + b.batterySum;
            result.batteryMin = Math.min(a.batteryMin, b.batteryMin);
            result.batteryMax = Math.max(a.batteryMax, b.batteryMax);

            if (a.latestEventTime != null && b.latestEventTime != null) {
                if (a.latestEventTime.isAfter(b.latestEventTime)) {
                    result.latestEventTime = a.latestEventTime;
                    result.latestStatus = a.latestStatus;
                } else {
                    result.latestEventTime = b.latestEventTime;
                    result.latestStatus = b.latestStatus;
                }
            } else if (a.latestEventTime != null) {
                result.latestEventTime = a.latestEventTime;
                result.latestStatus = a.latestStatus;
            } else {
                result.latestEventTime = b.latestEventTime;
                result.latestStatus = b.latestStatus;
            }
            return result;
        }

        @Override
        public SensorAccumulator getResult(SensorAccumulator accumulator) {
            return accumulator;
        }
    }

    private static class WindowEnricher extends ProcessWindowFunction<
            SensorAccumulator, SensorAggregate, String, TimeWindow> {
        @Override
        public void process(String key, Context context, Iterable<SensorAccumulator> elements, Collector<SensorAggregate> out) {
            SensorAccumulator accumulator = elements.iterator().next();
            if (accumulator.count == 0) {
                return;
            }
            double avgTemp = accumulator.temperatureSum / accumulator.count;
            double avgHumidity = accumulator.humiditySum / accumulator.count;
            double avgPressure = accumulator.pressureSum / accumulator.count;
            double avgBattery = accumulator.batterySum / accumulator.count;

            SensorAggregate aggregate = new SensorAggregate(
                    key,
                    accumulator.sensorType,
                    accumulator.location,
                    context.window().getStart(),
                    context.window().getEnd(),
                    avgTemp,
                    accumulator.temperatureMin,
                    accumulator.temperatureMax,
                    avgHumidity,
                    accumulator.humidityMin,
                    accumulator.humidityMax,
                    avgPressure,
                    accumulator.pressureMin,
                    accumulator.pressureMax,
                    avgBattery,
                    accumulator.batteryMin,
                    accumulator.batteryMax,
                    accumulator.latestStatus,
                    accumulator.latestEventTime == null ? 0L : accumulator.latestEventTime.toEpochMilli(),
                    accumulator.metadata);
            out.collect(aggregate);
        }
    }

    private static final class SensorAccumulator {
        private String sensorId;
        private String sensorType;
        private String location;
        private SensorData.MetaData metadata;
        private long count = 0L;

        private double temperatureSum = 0D;
        private double temperatureMin = Double.POSITIVE_INFINITY;
        private double temperatureMax = Double.NEGATIVE_INFINITY;

        private double humiditySum = 0D;
        private double humidityMin = Double.POSITIVE_INFINITY;
        private double humidityMax = Double.NEGATIVE_INFINITY;

        private double pressureSum = 0D;
        private double pressureMin = Double.POSITIVE_INFINITY;
        private double pressureMax = Double.NEGATIVE_INFINITY;

        private double batterySum = 0D;
        private double batteryMin = Double.POSITIVE_INFINITY;
        private double batteryMax = Double.NEGATIVE_INFINITY;

        private Instant latestEventTime;
        private String latestStatus;
    }

    private record SensorAggregate(
            String sensorId,
            String sensorType,
            String location,
            long windowStart,
            long windowEnd,
            double avgTemperature,
            double minTemperature,
            double maxTemperature,
            double avgHumidity,
            double minHumidity,
            double maxHumidity,
            double avgPressure,
            double minPressure,
            double maxPressure,
            double avgBatteryLevel,
            double minBatteryLevel,
            double maxBatteryLevel,
            String latestStatus,
            long latestEventTime,
            SensorData.MetaData metadata) {
        @Override
        public String toString() {
            return String.format(
                    Locale.ROOT,
                    "SensorAggregate{sensorId=%s, window=[%s,%s), avgTemp=%.2f, avgHumidity=%.2f, avgPressure=%.2f, avgBattery=%.2f, status=%s}",
                    sensorId,
                    Instant.ofEpochMilli(windowStart),
                    Instant.ofEpochMilli(windowEnd),
                    avgTemperature,
                    avgHumidity,
                    avgPressure,
                    avgBatteryLevel,
                    latestStatus);
        }
    }
}
