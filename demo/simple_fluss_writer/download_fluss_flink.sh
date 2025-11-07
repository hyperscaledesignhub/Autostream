#!/bin/bash

set -euo pipefail

FLUSS_VERSION="0.7.0"
FLINK_VERSION="1.20.3"
SCALA_BINARY="2.12"

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

FLUSS_TARBALL="fluss-${FLUSS_VERSION}-bin.tgz"
FLINK_TARBALL="flink-${FLINK_VERSION}-bin-scala_${SCALA_BINARY}.tgz"
CONNECTOR_JAR="fluss-flink-1.20-${FLUSS_VERSION}.jar"

download() {
  local url="$1"
  local target="$2"

  if [[ -f "${target}" ]];
  then
    echo "[skip] ${target} already exists"
    return
  fi

  echo "[download] ${url} -> ${target}"
  curl -L --fail --output "${target}" "${url}"
}

cd "${BASE_DIR}"

download "https://github.com/apache/fluss/releases/download/v${FLUSS_VERSION}/${FLUSS_TARBALL}" "${FLUSS_TARBALL}"

download "https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/${FLINK_TARBALL}" "${FLINK_TARBALL}"

download "https://repo1.maven.org/maven2/com/alibaba/fluss/fluss-flink-1.20/${FLUSS_VERSION}/${CONNECTOR_JAR}" "${CONNECTOR_JAR}"

echo "All downloads completed."

