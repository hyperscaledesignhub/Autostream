# FLUSS Demo Environment

This workspace captures everything needed to run Apache Fluss locally, connect Apache Flink to it, and exercise a simple end-to-end demo.

## Contents

- `download_fluss_flink.sh` – script to download the required Fluss/Flink binaries and the Fluss ↔︎ Flink connector JAR.
- `fluss_flink_quickstart.md` – step-by-step guide for standing up both clusters, creating tables via Flink SQL, inserting sample data, and querying it back.

## tl;dr workflow

1. Fetch artifacts (from repo root):
   ```bash
   ./download_fluss_flink.sh
   ```
2. Follow the quickstart instructions:
   ```bash
   open fluss_flink_quickstart.md
   ```
3. Run the Flink SQL statements in the quickstart to create demo tables and validate reads/writes.

## Demo Goals

- Start a local Fluss cluster for experimentation.
- Start a local Flink standalone cluster.
- Use the Fluss connector to create catalogs/tables inside Flink SQL.
- Insert test data from Flink into Fluss and query it back to confirm the integration.

When you are done testing, remember to stop both clusters (`./bin/stop-cluster.sh` for Flink, `./bin/local-cluster.sh stop` for Fluss). For full details, consult the quickstart document.

