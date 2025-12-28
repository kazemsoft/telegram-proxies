#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_URL="https://github.com/kazemsoft/telegram-proxies/blob/main/mtproto.txt"
RAW_URL="https://raw.githubusercontent.com/kazemsoft/telegram-proxies/main/mtproto.txt"
OUTPUT_FILE="checked-proxies.txt"
TEMP_FILE="/tmp/mtproto_proxies.txt"
TIMEOUT=5
MAX_PARALLEL=20

# Counters
TOTAL=0
WORKING=0
FAILED=0

echo "======================================"
echo "MTProto Proxy Checker"
echo "======================================"
echo ""

# Fetch proxy list from GitHub
echo "Fetching proxy list from GitHub..."
if curl -s -L -o "$TEMP_FILE" "$RAW_URL"; then
    echo -e "${GREEN}✓${NC} Successfully fetched proxy list"
else
    echo -e "${RED}✗${NC} Failed to fetch proxy list"
    exit 1
fi

# Count total proxies
TOTAL=$(grep -c "https://t.me/proxy" "$TEMP_FILE" 2>/dev/null || echo 0)

if [ "$TOTAL" -eq 0 ]; then
    echo -e "${RED}✗${NC} No proxies found in the file"
    exit 1
fi

echo -e "Found ${YELLOW}$TOTAL${NC} proxies to test"
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Function to extract host and port from URL
parse_proxy() {
    local url="$1"
    local host=$(echo "$url" | sed -n 's/.*server=\([^&]*\).*/\1/p')
    local port=$(echo "$url" | sed -n 's/.*port=\([^&]*\).*/\1/p')
    echo "$host $port"
}

# Function to test a single proxy
test_proxy() {
    local url="$1"
    local index="$2"
    
    # Parse URL
    read -r host port <<< $(parse_proxy "$url")
    
    if [ -z "$host" ] || [ -z "$port" ]; then
        echo -e "[${index}/${TOTAL}] ${RED}✗${NC} Invalid URL format"
        return 1
    fi
    
    # Test connectivity
    if timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port 2>/dev/null" 2>/dev/null; then
        echo -e "[${index}/${TOTAL}] ${GREEN}✓${NC} $host:$port - WORKING"
        echo "$url" >> "$OUTPUT_FILE"
        return 0
    else
        echo -e "[${index}/${TOTAL}] ${RED}✗${NC} $host:$port - UNREACHABLE"
        return 1
    fi
}

# Export functions for parallel execution
export -f test_proxy
export -f parse_proxy
export TIMEOUT
export TOTAL
export OUTPUT_FILE
export RED GREEN YELLOW NC

# Process proxies
echo "Testing proxies (timeout: ${TIMEOUT}s, parallel: ${MAX_PARALLEL})..."
echo ""

# Create a temporary file with indexed URLs
INDEXED_FILE="/tmp/indexed_proxies.txt"
awk '{print NR, $0}' "$TEMP_FILE" > "$INDEXED_FILE"

# Test proxies in parallel
while read -r index url; do
    test_proxy "$url" "$index" &
    
    # Limit parallel jobs
    while [ $(jobs -r | wc -l) -ge "$MAX_PARALLEL" ]; do
        sleep 0.1
    done
done < "$INDEXED_FILE"

# Wait for all background jobs to complete
wait

# Count results
WORKING=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo 0)
FAILED=$((TOTAL - WORKING))

# Print summary
echo ""
echo "======================================"
echo "SUMMARY"
echo "======================================"
echo -e "Total proxies tested: ${YELLOW}$TOTAL${NC}"
echo -e "Working proxies:      ${GREEN}$WORKING${NC}"
echo -e "Failed proxies:       ${RED}$FAILED${NC}"
echo -e "Success rate:         $(awk "BEGIN {printf \"%.1f\", ($WORKING/$TOTAL)*100}")%"
echo "======================================"
echo ""

if [ "$WORKING" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Saved $WORKING working proxies to: $OUTPUT_FILE"
    echo ""
    echo "Top 5 working proxies:"
    head -5 "$OUTPUT_FILE" | nl
else
    echo -e "${RED}⚠${NC} No working proxies found!"
    rm -f "$OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE" "$INDEXED_FILE"

echo ""
echo "Done!"
