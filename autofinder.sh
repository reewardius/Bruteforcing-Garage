#!/bin/bash
# -*- coding: utf-8 -*-

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

rm -f general* nuclei* fuzz* fp* http* juicy* interested* js.txt subs.txt alive* root.txt

# Function to show help
show_help() {
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 -d <domain>          # For single domain"
    echo "  $0 -f <file>            # For multiple domains from file"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 -d target.com"
    echo "  $0 -f domains.txt"
    echo ""
    echo -e "${BLUE}Description:${NC}"
    echo "  Script performs complete subdomain reconnaissance including:"
    echo "  - Subdomain discovery (subfinder)"
    echo "  - Live service check (httpx)"
    echo "  - JS file extraction (getJS)"
    echo "  - Endpoint discovery (finder-js.py)"
    echo "  - Fuzzing (ffuf)"
    echo "  - Vulnerability scanning (nuclei)"
}

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to check installed tools
check_tools() {
    local tools=("subfinder" "httpx" "getJS" "ffuf" "nuclei" "python3")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "The following tools are not installed: ${missing_tools[*]}"
        echo "Install missing tools and run script again."
        exit 1
    fi
    
    # Check Python scripts
    if [ ! -f "finder-js.py" ]; then
        error "File finder-js.py not found in current directory"
        exit 1
    fi
    
    if [ ! -f "delete_falsepositives.py" ]; then
        error "File delete_falsepositives.py not found in current directory"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -f success.txt fuzz_results.json 2>/dev/null
}

# Main reconnaissance function
run_recon() {
    local domain_input="$1"
    local input_type="$2"
    
    log "Starting reconnaissance for: $domain_input"
    
    # Step 1: Subdomain discovery
    log "Step 1: Subdomain discovery with subfinder..."
    if [ "$input_type" = "domain" ]; then
        subfinder -d "$domain_input" -all -silent -o subs.txt
    else
        subfinder -dL "$domain_input" -all -silent -o subs.txt
    fi
    
    if [ $? -ne 0 ] || [ ! -s subs.txt ]; then
        error "Failed to find subdomains or subs.txt is empty"
        exit 1
    fi
    
    log "Found $(wc -l < subs.txt) subdomains"
    
    # Step 2: Check live HTTP services
    log "Step 2: Checking live HTTP services with httpx..."
    httpx -l subs.txt -mc 200 -o alive_http_services.txt
    
    if [ $? -ne 0 ] || [ ! -s alive_http_services.txt ]; then
        error "No live HTTP services found"
        exit 1
    fi
    
    log "Found $(wc -l < alive_http_services.txt) live HTTP services"
    
    # Step 3: Extract JS files
    log "Step 3: Extracting JS files with getJS..."
    getJS -input alive_http_services.txt -threads 50 -complete -output js.txt
    
    if [ $? -ne 0 ] || [ ! -s js.txt ]; then
        warning "Failed to extract JS files or js.txt is empty"
        touch js.txt  # Create empty file to continue
    else
        log "Found $(wc -l < js.txt) JS files"
    fi
    
    # Step 4: Find endpoints in JS files
    log "Step 4: Finding endpoints with finder-js.py..."
    python3 finder-js.py -l js.txt -o endpoints.txt
    
    if [ $? -ne 0 ] || [ ! -s endpoints.txt ]; then
        warning "Failed to find endpoints or endpoints.txt is empty"
        touch endpoints.txt juicyinfo.txt http_links.txt interested_api_endpoints.txt
    else
        log "Found $(wc -l < endpoints.txt) endpoints"
        
        # Filter endpoints
        log "Filtering interesting endpoints..."
        cat endpoints.txt | grep -Ei 'api|v1|v2|v3|user|admin|internal|debug|data|account|config' > juicyinfo.txt
        cat endpoints.txt | grep -E 'http://|https://' > http_links.txt
        cat endpoints.txt | grep -E 'create|add|security|reset|update|delete|modify|remove|list|offer|show|trace|allow|disallow|approve|reject|start|stop|set' > interested_api_endpoints.txt
        
        log "Juicy endpoints: $(wc -l < juicyinfo.txt)"
        log "HTTP links: $(wc -l < http_links.txt)"
        log "Interested APIs: $(wc -l < interested_api_endpoints.txt)"
    fi
    
    # Remove success.txt if exists
    rm -f success.txt
    
    # Step 5: Fuzzing with interested_api_endpoints
    if [ -s alive_http_services.txt ] && [ -s interested_api_endpoints.txt ]; then
        log "Step 5: Fuzzing with interested API endpoints..."
        ffuf -u URL/TOP -w alive_http_services.txt:URL -w interested_api_endpoints.txt:TOP -ac -mc 200 -r -o fuzz_results.json -fs 0
        
        if [ $? -eq 0 ] && [ -s fuzz_results.json ]; then
            python3 delete_falsepositives.py -j fuzz_results.json -o fuzz_output1.txt -fp fp_domains1.txt
            log "Fuzzing results 1 saved to fuzz_output1.txt"
        else
            warning "Fuzzing 1 produced no results"
            touch fuzz_output1.txt
        fi
    else
        warning "Skipping fuzzing 1 - no data to process"
        touch fuzz_output1.txt
    fi
    
    # Step 6: Fuzzing with juicyinfo
    if [ -s alive_http_services.txt ] && [ -s juicyinfo.txt ]; then
        log "Step 5b: Fuzzing with juicy endpoints..."
        ffuf -u URL/TOP -w alive_http_services.txt:URL -w juicyinfo.txt:TOP -ac -mc 200 -r -o fuzz_results.json -fs 0
        
        if [ $? -eq 0 ] && [ -s fuzz_results.json ]; then
            python3 delete_falsepositives.py -j fuzz_results.json -o fuzz_output2.txt -fp fp_domains2.txt
            log "Fuzzing results 2 saved to fuzz_output2.txt"
        else
            warning "Fuzzing 2 produced no results"
            touch fuzz_output2.txt
        fi
    else
        warning "Skipping fuzzing 2 - no data to process"
        touch fuzz_output2.txt
    fi
    
    # Step 7: Nuclei scanning
    if [ -s http_links.txt ]; then
        log "Step 6: Nuclei scanning for subdomain takeovers..."
        nuclei -l http_links.txt -profile subdomain-takeovers -nh -o nuclei_subdomain_takeovers.txt
        
        if [ $? -eq 0 ] && [ -s nuclei_subdomain_takeovers.txt ]; then
            log "Found $(wc -l < nuclei_subdomain_takeovers.txt) potential subdomain takeovers"
        else
            warning "Nuclei found no subdomain takeovers"
            touch nuclei_subdomain_takeovers.txt
        fi
    else
        warning "Skipping Nuclei scanning - no HTTP links"
        touch nuclei_subdomain_takeovers.txt
    fi
    
    # Step 8: Combine results
    log "Step 7: Combining all results..."
    cat fuzz_output1.txt fuzz_output2.txt nuclei_subdomain_takeovers.txt | sort -u > general_results.txt
    
    log "Reconnaissance completed! General results saved to general_results.txt"
    log "Total unique results: $(wc -l < general_results.txt)"
    
    # Show statistics
    echo ""
    echo -e "${BLUE}=== STATISTICS ===${NC}"
    echo "Subdomains: $(wc -l < subs.txt 2>/dev/null || echo 0)"
    echo "Live HTTP services: $(wc -l < alive_http_services.txt 2>/dev/null || echo 0)"
    echo "JS files: $(wc -l < js.txt 2>/dev/null || echo 0)"
    echo "Endpoints: $(wc -l < endpoints.txt 2>/dev/null || echo 0)"
    echo "Fuzzing results 1: $(wc -l < fuzz_output1.txt 2>/dev/null || echo 0)"
    echo "Fuzzing results 2: $(wc -l < fuzz_output2.txt 2>/dev/null || echo 0)"
    echo "Nuclei results: $(wc -l < nuclei_subdomain_takeovers.txt 2>/dev/null || echo 0)"
    echo "General results: $(wc -l < general_results.txt 2>/dev/null || echo 0)"
}

# Check command line arguments
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Process arguments
while getopts "d:f:h" opt; do
    case $opt in
        d)
            DOMAIN="$OPTARG"
            INPUT_TYPE="domain"
            ;;
        f)
            DOMAIN_FILE="$OPTARG"
            INPUT_TYPE="file"
            ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            error "Invalid flag: -$OPTARG"
            show_help
            exit 1
            ;;
    esac
done

# Check tools
check_tools

# Execute reconnaissance based on input type
if [ "$INPUT_TYPE" = "domain" ]; then
    if [ -z "$DOMAIN" ]; then
        error "Domain not specified"
        show_help
        exit 1
    fi
    
    log "Mode: Single domain ($DOMAIN)"
    run_recon "$DOMAIN" "domain"
    
elif [ "$INPUT_TYPE" = "file" ]; then
    if [ -z "$DOMAIN_FILE" ]; then
        error "Domain file not specified"
        show_help
        exit 1
    fi
    
    if [ ! -f "$DOMAIN_FILE" ]; then
        error "File $DOMAIN_FILE not found"
        exit 1
    fi
    
    log "Mode: Multiple domains from file ($DOMAIN_FILE)"
    run_recon "$DOMAIN_FILE" "file"
    
else
    error "Work mode not specified"
    show_help
    exit 1
fi

# Cleanup temporary files
cleanup

log "Script completed successfully!"
