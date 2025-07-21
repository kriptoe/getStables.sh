#!/bin/bash

# Configuration
RPC_URL="https://rpc.hyperliquid.xyz/evm"
ARBISCAN_API_KEY="HHTM8VBV6PN8KWGX8CK8ASD1UDGZ9ESEPM"  # Set this as environment variable or replace
BRIDGE_ADDRESS="0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7"
USDC_CONTRACT="0xaf88d065e77c8cc2239327c5edb3a432268e5831"

# Contracts and their corresponding asset names
declare -A CONTRACT_NAMES=(
    ["0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5"]="USDhl"
    ["0x02c6a2fa58cc01a18b8d9e00ea48d65e4df26c70"]="FEUSD"
    ["0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb"]="USDTO"
    ["0x5d3a1ff2b6bab83b63cd9ad0787074081a52ef34"]="USDE"
    ["0xca79db4b49f608ef54a5cb813fbed3a6387bc645"]="USDXL"
)

CONTRACTS=(
    "0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5"
    "0x02c6a2fa58cc01a18b8d9e00ea48d65e4df26c70"
    "0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb"
    "0x5d3a1ff2b6bab83b63cd9ad0787074081a52ef34"
    "0xca79db4b49f608ef54a5cb813fbed3a6387bc645"
)

# Format number with commas
format_number() {
    echo "$1" | awk '{printf "%'\''d\n", $1}'
}

# Get Arbitrum USDC balance
get_arbiscan_usdc_balance() {
    local api_key="$1"
    
    if [ "$api_key" = "your_api_key_here" ] || [ -z "$api_key" ]; then
        echo "⚠️  Warning: No Arbiscan API key provided. Set ARBISCAN_API_KEY environment variable."
        echo "Bridge USDC Balance: Skipped (no API key)"
        echo "------------------------"
        return
    fi
    
    local api_url="https://api.arbiscan.io/api?module=account&action=tokenbalance&contractaddress=${USDC_CONTRACT}&address=${BRIDGE_ADDRESS}&tag=latest&apikey=${api_key}"
    
    echo "🌉 Fetching Arbitrum Bridge USDC Balance..."
    
    local response=$(curl -s "$api_url")
    
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to fetch data from Arbiscan API"
        echo "------------------------"
        return
    fi
    
    local status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    local result=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$status" = "1" ] && [ -n "$result" ]; then
        local balance_wei="$result"
        local balance_truncated="${balance_wei:0:-6}"
        [[ -z "$balance_truncated" ]] && balance_truncated=0
        local balance_formatted=$(format_number "$balance_truncated")
        
        echo "Asset: Bridge USDC (Arbitrum)"
        echo "Balance: $balance_formatted USDC"
        echo "------------------------"
        
        bridge_balance="$balance_truncated"
    else
        echo "❌ Error: Failed to parse Arbiscan response or API returned error"
        echo "Response: $response"
        echo "------------------------"
        bridge_balance=0
    fi
}

# Initialize totals
usdc_total=0
bridge_balance=0

# Get total supply for a contract
get_total_supply() {
    local contract=$1
    local name=${CONTRACT_NAMES[$contract]}
    
    echo "📊 Fetching data for $name..."
    
    decimals=$(cast call "$contract" "decimals()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -z "$decimals" ]; then
        echo "❌ Error: Could not fetch decimals for $contract ($name)."
        echo "------------------------"
        return
    fi
    
    total_supply=$(cast call "$contract" "totalSupply()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -z "$total_supply" ]; then
        echo "❌ Error: Could not fetch total supply for $contract ($name)."
        echo "------------------------"
        return
    fi
    
    total_supply=$(echo "$total_supply" | tr -d '[:space:]' | sed 's/\[.*\]//')
    
    if [[ "$total_supply" =~ ^0x ]]; then
        total_supply_integer=$(echo "ibase=16; $(echo "$total_supply" | tr '[:lower:]' '[:upper:]' | cut -c3-)" | bc)
    else
        total_supply_integer=$(echo "$total_supply" | grep -o '^[0-9]\+' || echo "0")
    fi
    [[ -z "$total_supply_integer" ]] && total_supply_integer=0
    
    if [[ ! "$total_supply_integer" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Invalid total_supply_integer: $total_supply_integer"
        echo "------------------------"
        return
    fi
    
    echo "✅ Asset: $name"
    if [ "$contract" = "0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb" ] || [ "$contract" = "0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5" ]; then
        truncated_6digits="${total_supply_integer:0:-6}"
        [[ -z "$truncated_6digits" ]] && truncated_6digits=0
        formatted_truncated_6digits=$(format_number "$truncated_6digits")
        usdc_total=$(echo "$usdc_total + $truncated_6digits" | bc)
        echo " USDC Value: $formatted_truncated_6digits"
    else
        truncated_18digits="${total_supply_integer:0:-18}"
        [[ -z "$truncated_18digits" ]] && truncated_18digits=0
        formatted_truncated_18digits=$(format_number "$truncated_18digits")
        usdc_total=$(echo "$usdc_total + $truncated_18digits" | bc)
        echo " USDC Value: $formatted_truncated_18digits"
    fi
    echo "------------------------"
}

# Print header
echo "🚀 Hyperliquid Asset Supply & Bridge Balance Checker"
echo "=================================================="
echo ""

# Check if required tools are available
if ! command -v cast &> /dev/null; then
    echo "❌ Error: 'cast' command not found. Please install Foundry."
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "❌ Error: 'bc' command not found. Please install bc for calculations."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "❌ Error: 'curl' command not found. Please install curl."
    exit 1
fi

# Get Arbitrum bridge balance first
get_arbiscan_usdc_balance "$ARBISCAN_API_KEY"

echo ""
echo "📈 Hyperliquid Asset Total Supplies:"
echo "====================================="

# Loop through contracts
for contract in "${CONTRACTS[@]}"; do
    get_total_supply "$contract"
done

# Calculate grand total including bridge
grand_total=$(echo "$usdc_total + $bridge_balance" | bc)
formatted_usdc_total=$(format_number "$usdc_total")
formatted_bridge=$(format_number "$bridge_balance")
formatted_grand_total=$(format_number "$grand_total")

# Output summary
echo ""
echo "📊 SUMMARY:"
echo "==========="
echo "💰 Total Supply (Hyperliquid Assets): $formatted_usdc_total USDC"
echo "🌉 Bridge Balance (Arbitrum USDC): $formatted_bridge USDC"
echo "🎯 Grand Total: $formatted_grand_total USDC"
