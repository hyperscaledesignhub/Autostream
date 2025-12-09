package com.example.fluss.inspect;

import org.apache.fluss.client.Connection;
import org.apache.fluss.client.ConnectionFactory;
import org.apache.fluss.client.table.Table;
import org.apache.fluss.client.table.scanner.ScanRecord;
import org.apache.fluss.client.table.scanner.log.LogScanner;
import org.apache.fluss.client.table.scanner.log.ScanRecords;
import org.apache.fluss.config.ConfigOptions;
import org.apache.fluss.config.Configuration;
import org.apache.fluss.metadata.TableInfo;
import org.apache.fluss.metadata.TablePath;

import java.time.Duration;
import java.util.Collections;

/**
 * Simple helper that prints a few records from the Fluss change log so we can confirm data flow.
 */
public final class FlussTableLogPeek {

    private FlussTableLogPeek() {}

    public static void main(String[] args) throws Exception {
        if (args.length < 3 || args.length > 4) {
            System.err.println(
                    "Usage: FlussTableLogPeek <bootstrap-host:port> <database> <table> [limit]"
                            + System.lineSeparator()
                            + "Example: FlussTableLogPeek localhost:9123 iot sensor_readings 5");
            System.exit(1);
        }

        String bootstrap = args[0];
        String database = args[1];
        String tableName = args[2];
        int limit = args.length == 4 ? Integer.parseInt(args[3]) : 10;

        Configuration conf = new Configuration();
        conf.set(ConfigOptions.BOOTSTRAP_SERVERS, Collections.singletonList(bootstrap));

        try (Connection connection = ConnectionFactory.createConnection(conf);
                Table table = connection.getTable(TablePath.of(database, tableName))) {
            TableInfo tableInfo = table.getTableInfo();
            int buckets = tableInfo.getNumBuckets();
            System.out.printf(
                    "Subscribing to %d buckets for table %s.%s%n", buckets, database, tableName);

            try (LogScanner scanner = table.newScan().createLogScanner()) {
                for (int bucket = 0; bucket < buckets; bucket++) {
                    scanner.subscribeFromBeginning(bucket);
                }

                int printed = 0;
                int emptyPolls = 0;
                while (printed < limit && emptyPolls < 5) {
                    ScanRecords records = scanner.poll(Duration.ofSeconds(1));
                    if (records.isEmpty()) {
                        emptyPolls++;
                        continue;
                    }
                    for (ScanRecord record : records) {
                        System.out.println(record);
                        printed++;
                        if (printed >= limit) {
                            break;
                        }
                    }
                }

                if (printed == 0) {
                    System.out.println("No records found (table might be empty or producer not running).");
                } else if (printed < limit) {
                    System.out.printf("Displayed %d records (no more records available now).%n", printed);
                }
            }
        }
    }
}
