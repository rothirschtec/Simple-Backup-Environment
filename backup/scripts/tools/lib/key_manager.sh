#!/bin/bash
#
# Key management functions for SBE using the key server API
# Dependencies: curl

# Key server settings
KEYSERVER_HOST="${KEYSERVER_HOST:-https://sbe.keyserver.your.domain:8443}"
KEYSERVER_API_KEY="${KEYSERVER_API_KEY:-your_api_key_here}"

# Store encryption key to the key server
store_encryption_key() {
    local hostname="$1"
    local encryption_key="$2"
    
    # Validate inputs
    if [ -z "$hostname" ] || [ -z "$encryption_key" ]; then
        echo "Error: hostname and encryption key are required"
        return 1
    fi
    
    # Create JSON payload
    local payload="{\"hostname\":\"$hostname\",\"key\":\"$encryption_key\"}"
    
    # Send request to key server
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $KEYSERVER_API_KEY" \
        -d "$payload" \
        "$KEYSERVER_HOST/api/keys")
    
    # Check response
    if echo "$response" | grep -q '"message"'; then
        echo "Key stored successfully for $hostname"
        return 0
    else
        echo "Error storing key: $response"
        return 1
    fi
}

# Retrieve encryption key from the key server
retrieve_encryption_key() {
    local hostname="$1"
    
    # Validate input
    if [ -z "$hostname" ]; then
        echo "Error: hostname is required"
        return 1
    fi
    
    # Send request to key server
    local response=$(curl -s -X GET \
        -H "Authorization: Bearer $KEYSERVER_API_KEY" \
        "$KEYSERVER_HOST/api/keys/$hostname")
    
    # Check response
    if echo "$response" | grep -q '"key"'; then
        # Extract the key from JSON response
        local key=$(echo "$response" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
        echo "$key"
        return 0
    else
        echo "Error retrieving key: $response"
        return 1
    fi
}

# Delete encryption key from the key server
delete_encryption_key() {
    local hostname="$1"
    
    # Validate input
    if [ -z "$hostname" ]; then
        echo "Error: hostname is required"
        return 1
    fi
    
    # Send request to key server
    local response=$(curl -s -X DELETE \
        -H "Authorization: Bearer $KEYSERVER_API_KEY" \
        "$KEYSERVER_HOST/api/keys/$hostname")
    
    # Check response
    if echo "$response" | grep -q '"message"'; then
        echo "Key deleted successfully for $hostname"
        return 0
    else
        echo "Error deleting key: $response"
        return 1
    fi
}

# Check if key server is available
check_keyserver_health() {
    local response=$(curl -s -X GET "$KEYSERVER_HOST/health")
    
    if echo "$response" | grep -q '"status":"healthy"'; then
        return 0
    else
        echo "Key server is unavailable"
        return 1
    fi
}
