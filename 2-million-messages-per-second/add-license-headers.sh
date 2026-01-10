#!/bin/bash
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LICENSE_HEADER="#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the \"License\"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an \"AS IS\" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
"

# Function to check if file has license header
has_license_header() {
    local file="$1"
    if grep -q "Licensed to the Apache Software Foundation" "$file" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to add license header to file
add_license_header() {
    local file="$1"
    local temp_file=$(mktemp)
    
    # Check file type
    if [[ "$file" == *.sh ]] || [[ "$file" == *.bash ]]; then
        # Shell script - check if it starts with shebang
        if head -1 "$file" | grep -q "^#!"; then
            # Has shebang - add shebang, blank line, then license
            head -1 "$file" > "$temp_file"
            echo "" >> "$temp_file"
            echo "$LICENSE_HEADER" >> "$temp_file"
            tail -n +2 "$file" >> "$temp_file"
        else
            # No shebang - just add license at start
            echo "$LICENSE_HEADER" > "$temp_file"
            cat "$file" >> "$temp_file"
        fi
    elif [[ "$file" == *.yaml ]] || [[ "$file" == *.yml ]]; then
        # YAML file - add license before content
        echo "$LICENSE_HEADER" > "$temp_file"
        cat "$file" >> "$temp_file"
    elif [[ "$file" == *.tf ]]; then
        # Terraform file - add license before content
        echo "$LICENSE_HEADER" > "$temp_file"
        cat "$file" >> "$temp_file"
    elif [[ "$file" == *.java ]]; then
        # Java file - add license before package/import statements
        if head -1 "$file" | grep -q "^package\|^import"; then
            echo "$LICENSE_HEADER" > "$temp_file"
            cat "$file" >> "$temp_file"
        else
            echo "$LICENSE_HEADER" > "$temp_file"
            cat "$file" >> "$temp_file"
        fi
    elif [[ "$file" == *.py ]]; then
        # Python file - check if it starts with shebang or encoding
        if head -1 "$file" | grep -q "^#!"; then
            # Has shebang
            head -1 "$file" > "$temp_file"
            if head -2 "$file" | tail -1 | grep -q "^#.*coding\|^#.*encoding"; then
                head -2 "$file" | tail -1 >> "$temp_file"
                echo "" >> "$temp_file"
                echo "$LICENSE_HEADER" >> "$temp_file"
                tail -n +3 "$file" >> "$temp_file"
            else
                echo "" >> "$temp_file"
                echo "$LICENSE_HEADER" >> "$temp_file"
                tail -n +2 "$file" >> "$temp_file"
            fi
        else
            # No shebang - just add license at start
            echo "$LICENSE_HEADER" > "$temp_file"
            cat "$file" >> "$temp_file"
        fi
    else
        # Default - add license at start
        echo "$LICENSE_HEADER" > "$temp_file"
        cat "$file" >> "$temp_file"
    fi
    
    mv "$temp_file" "$file"
}

# Find all relevant files
echo "Finding files that need license headers..."
FILES=$(find "$SCRIPT_DIR" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.tf" -o -name "*.py" -o -name "*.java" \) ! -name "add-license-headers.sh" ! -path "*/target/*" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/.terraform/*")

TOTAL=0
ADDED=0
SKIPPED=0

for file in $FILES; do
    TOTAL=$((TOTAL + 1))
    if has_license_header "$file"; then
        echo "✓ Already has license: $file"
        SKIPPED=$((SKIPPED + 1))
    else
        echo "  Adding license to: $file"
        add_license_header "$file"
        ADDED=$((ADDED + 1))
    fi
done

echo ""
echo "=========================================="
echo "License Header Addition Summary"
echo "=========================================="
echo "Total files checked: $TOTAL"
echo "Files with existing license: $SKIPPED"
echo "Files updated: $ADDED"
echo ""

