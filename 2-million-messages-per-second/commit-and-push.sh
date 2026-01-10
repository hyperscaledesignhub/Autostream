#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#!/bin/bash
# Script to add, commit, and push the 2-million-messages-per-second benchmark documentation

set -e

cd "$(dirname "$0")/../.."

echo "=== Adding benchmark documentation files ==="
git add demos/2-million-messages-per-second/README.md
git add demos/2-million-messages-per-second/bench-mark-images/README.md

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

