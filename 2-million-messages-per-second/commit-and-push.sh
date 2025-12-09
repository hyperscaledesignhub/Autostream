#!/bin/bash
# Script to add, commit, and push the 2-million-messages-per-second benchmark documentation

set -e

cd "$(dirname "$0")/../.."

echo "=== Adding benchmark documentation files ==="
git add demos/2-million-messages-per-second/README.md
git add demos/2-million-messages-per-second/bench-mark/README.md

echo ""
echo "=== Checking git status ==="
git status --short demos/2-million-messages-per-second/

echo ""
echo "=== Committing changes ==="
git commit -m "docs: Add comprehensive benchmark documentation for 2M rows/sec test

- Add detailed README explaining producer device distribution (100K devices across 8 producers)
- Document Fluss table configuration (128 partitions, 3 tablet servers)
- Explain Flink job operators and data flow
- Add benchmark diagrams with explanations (10-deployment first, then 1-9)
- Include performance metrics and key indicators for each diagram
- Add HTML comments documenting the purpose of each README file"

echo ""
echo "=== Pushing to remote ==="
git push

echo ""
echo "=== Done ==="

