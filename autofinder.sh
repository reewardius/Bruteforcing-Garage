#!/bin/bash

# Advanced Endpoint Discovery & Fuzzing Script with Results Dashboard
# Author: Security Research Team
# Version: 2.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINDER_DIR="${SCRIPT_DIR}/finder"
RESULTS_DIR="${FINDER_DIR}/results"
RAW_DIR="${FINDER_DIR}/raw"
FILTERED_DIR="${FINDER_DIR}/filtered"
DASHBOARD_DIR="${FINDER_DIR}/dashboard"

# Default values
JS_LIST="js.txt"
ENDPOINTS_FILE="endpoints.txt"
ALIVE_SERVICES="alive_http_services.txt"
THREADS=50
RATE_LIMIT=100
TIMEOUT=10

# Banner
print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               ADVANCED ENDPOINT DISCOVERY                    ║"
    echo "║                     & FUZZING SUITE                          ║"
    echo "║                        v2.0                                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[+]${NC} ${timestamp} - ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[!]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[-]${NC} ${timestamp} - ${message}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[*]${NC} ${timestamp} - ${message}"
            ;;
    esac
    echo "${timestamp} - [${level}] ${message}" >> "${RESULTS_DIR}/scan.log"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -j, --js-list FILE        JavaScript files list (default: js.txt)"
    echo "  -s, --services FILE       Alive HTTP services file (default: alive_http_services.txt)"
    echo "  -t, --threads NUM         Number of threads (default: 50)"
    echo "  -r, --rate NUM            Rate limit per second (default: 100)"
    echo "  -T, --timeout NUM         Request timeout in seconds (default: 10)"
    echo "  -d, --dashboard           Generate dashboard only"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -j js_files.txt -s services.txt -t 30 -r 50"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -j|--js-list)
                JS_LIST="$2"
                shift 2
                ;;
            -s|--services)
                ALIVE_SERVICES="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            -r|--rate)
                RATE_LIMIT="$2"
                shift 2
                ;;
            -T|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -d|--dashboard)
                generate_dashboard
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Setup directory structure
setup_directories() {
    log "INFO" "Setting up directory structure..."
    
    rm -rf "${FINDER_DIR}" 2>/dev/null
    mkdir -p "${FINDER_DIR}"/{raw,filtered,results,dashboard}
    
    log "INFO" "Directory structure created successfully"
}

# Check dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."
    
    local deps=("python3" "ffuf" "grep" "sort" "sed" "awk")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        log "ERROR" "Please install missing tools and try again"
        exit 1
    fi
    
    # Check for required files
    local files=("$JS_LIST" "$ALIVE_SERVICES")
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log "ERROR" "Required file not found: $file"
            exit 1
        fi
    done
    
    log "INFO" "All dependencies and files verified"
}

# Extract endpoints from JavaScript files
extract_endpoints() {
    log "INFO" "Extracting endpoints from JavaScript files..."
    
    if python3 finder-js.py -l "${JS_LIST}" -o "${ENDPOINTS_FILE}"; then
        local endpoint_count=$(wc -l < "${ENDPOINTS_FILE}" 2>/dev/null || echo "0")
        log "INFO" "Endpoint extraction completed: ${endpoint_count} endpoints found"
    else
        log "ERROR" "Endpoint extraction failed"
        exit 1
    fi
}

# Filter and categorize endpoints
filter_endpoints() {
    log "INFO" "Filtering and categorizing endpoints..."
    
    # Juicy endpoints (API, admin, sensitive)
    grep -Ei 'api|v[0-9]+|user|admin|internal|debug|data|account|config|auth|login|token|key|secret|password|jwt|session|oauth' \
        "${ENDPOINTS_FILE}" > "${RAW_DIR}/juicyinfo.txt" 2>/dev/null
    
    # HTTP links
    grep -E '^https?://' "${ENDPOINTS_FILE}" > "${RAW_DIR}/http_links.txt" 2>/dev/null
    
    # Interesting API endpoints (CRUD operations)
    grep -Ei 'create|add|new|insert|security|reset|update|edit|patch|delete|remove|drop|modify|list|get|fetch|show|display|trace|allow|disallow|approve|reject|start|stop|enable|disable|set|put|post|upload|download|export|import|backup|restore' \
        "${ENDPOINTS_FILE}" > "${RAW_DIR}/interested_api_endpoints.txt" 2>/dev/null
    
    # Webhook and callback endpoints
    grep -Ei 'webhook|callback|notify|trigger|event|subscribe|unsubscribe|cors|csrf' \
        "${ENDPOINTS_FILE}" > "${RAW_DIR}/webhooks.txt" 2>/dev/null
    
    # Configuration and settings endpoints
    grep -Ei 'config|setting|preference|option|parameter|env|environment|flag|feature' \
        "${ENDPOINTS_FILE}" > "${RAW_DIR}/configurations.txt" 2>/dev/null
    
    log "INFO" "Endpoint filtering completed"
}

# Clean and deduplicate endpoints
clean_endpoints() {
    log "INFO" "Cleaning and deduplicating endpoints..."
    
    for raw_file in "${RAW_DIR}"/*.txt; do
        if [[ -f "$raw_file" ]]; then
            local filename=$(basename "$raw_file")
            local clean_file="${FILTERED_DIR}/${filename}"
            
            # Remove leading slashes, clean whitespace, and deduplicate
            sed 's|^/||; s/^[[:space:]]*//; s/[[:space:]]*$//' "$raw_file" | \
            grep -v '^$' | \
            sort -u > "$clean_file"
            
            local count=$(wc -l < "$clean_file" 2>/dev/null || echo "0")
            log "DEBUG" "Cleaned ${filename}: ${count} unique endpoints"
        fi
    done
    
    log "INFO" "Endpoint cleaning completed"
}

# Fuzzing function
run_fuzzing() {
    local category=$1
    local wordlist=$2
    local output_name=$3
    
    log "INFO" "Starting fuzzing: ${category}"
    
    if [[ ! -f "$wordlist" ]] || [[ ! -s "$wordlist" ]]; then
        log "WARN" "Wordlist ${wordlist} is empty or doesn't exist, skipping ${category}"
        return
    fi
    
    local wordlist_count=$(wc -l < "$wordlist")
    local services_count=$(wc -l < "$ALIVE_SERVICES")
    local total_requests=$((wordlist_count * services_count))
    
    log "INFO" "Fuzzing ${category}: ${total_requests} total requests (${wordlist_count} endpoints × ${services_count} services)"
    
    ffuf -u "URL/FUZZ" \
         -w "${ALIVE_SERVICES}:URL" \
         -w "${wordlist}:FUZZ" \
         -ac \
         -mc 200 \
         -o "${RESULTS_DIR}/${output_name}.json" \
         -fs 0 \
         -t "$THREADS" \
         -rate "$RATE_LIMIT" \
         -timeout "$TIMEOUT" \
         -s 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Fuzzing completed for ${category}"
        
        # Process results if delete_falsepositives.py exists
        if [[ -f "delete_falsepositives.py" ]]; then
            python3 delete_falsepositives.py \
                -j "${RESULTS_DIR}/${output_name}.json" \
                -o "${RESULTS_DIR}/${output_name}_clean.txt" \
                -fp "${RESULTS_DIR}/${output_name}_fp.txt" 2>/dev/null
            
            if [[ -f "${RESULTS_DIR}/${output_name}_clean.txt" ]]; then
                local clean_count=$(wc -l < "${RESULTS_DIR}/${output_name}_clean.txt")
                log "INFO" "${category}: ${clean_count} valid endpoints found"
            fi
        else
            # Extract results manually if script doesn't exist
            if [[ -f "${RESULTS_DIR}/${output_name}.json" ]]; then
                python3 -c "
import json
try:
    with open('${RESULTS_DIR}/${output_name}.json', 'r') as f:
        data = json.load(f)
    with open('${RESULTS_DIR}/${output_name}_clean.txt', 'w') as f:
        for result in data.get('results', []):
            f.write(f\"{result['url']} [{result['status']}] [{result['length']}]\\n\")
except Exception as e:
    print(f'Error processing results: {e}')
" 2>/dev/null
            fi
        fi
    else
        log "ERROR" "Fuzzing failed for ${category}"
    fi
}

# Main fuzzing process
execute_fuzzing() {
    log "INFO" "Starting fuzzing process..."
    
    # Define fuzzing targets
    declare -A fuzz_targets=(
        ["Juicy Endpoints"]="${FILTERED_DIR}/juicyinfo.txt:fuzz_juicy"
        ["API Endpoints"]="${FILTERED_DIR}/interested_api_endpoints.txt:fuzz_api"
        ["Webhooks"]="${FILTERED_DIR}/webhooks.txt:fuzz_webhooks"
        ["Configurations"]="${FILTERED_DIR}/configurations.txt:fuzz_configs"
    )
    
    for category in "${!fuzz_targets[@]}"; do
        IFS=':' read -r wordlist output_name <<< "${fuzz_targets[$category]}"
        run_fuzzing "$category" "$wordlist" "$output_name"
    done
    
    log "INFO" "All fuzzing tasks completed"
}

# Generate summary statistics
generate_summary() {
    log "INFO" "Generating summary statistics..."
    
    local summary_file="${RESULTS_DIR}/summary.txt"
    local stats_file="${RESULTS_DIR}/statistics.json"
    
    echo "=== ENDPOINT DISCOVERY SUMMARY ===" > "$summary_file"
    echo "Scan Date: $(date)" >> "$summary_file"
    echo "Duration: ${scan_duration}s" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Count results
    local total_found=0
    echo "Results by category:" >> "$summary_file"
    
    for result_file in "${RESULTS_DIR}"/*_clean.txt; do
        if [[ -f "$result_file" ]]; then
            local filename=$(basename "$result_file" "_clean.txt")
            local count=$(wc -l < "$result_file" 2>/dev/null || echo "0")
            total_found=$((total_found + count))
            printf "  %-20s: %d endpoints\n" "$filename" "$count" >> "$summary_file"
        fi
    done
    
    echo "" >> "$summary_file"
    echo "Total endpoints found: $total_found" >> "$summary_file"
    
    # Generate JSON statistics
    cat > "$stats_file" << EOF
{
    "scan_date": "$(date -Iseconds)",
    "duration": ${scan_duration},
    "total_endpoints_found": ${total_found},
    "categories": {
EOF
    
    local first=true
    for result_file in "${RESULTS_DIR}"/*_clean.txt; do
        if [[ -f "$result_file" ]]; then
            local filename=$(basename "$result_file" "_clean.txt")
            local count=$(wc -l < "$result_file" 2>/dev/null || echo "0")
            
            if [[ "$first" = false ]]; then
                echo "," >> "$stats_file"
            fi
            echo "        \"$filename\": $count" >> "$stats_file"
            first=false
        fi
    done
    
    cat >> "$stats_file" << EOF
    }
}
EOF
    
    log "INFO" "Summary generated: $summary_file"
}

# Generate HTML dashboard
generate_dashboard() {
    log "INFO" "Generating results dashboard..."
    
    local dashboard_file="${DASHBOARD_DIR}/dashboard.html"
    local stats_file="${RESULTS_DIR}/statistics.json"
    
    # Create dashboard HTML
    cat > "$dashboard_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Endpoint Discovery Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(45deg, #2c3e50, #3498db);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            padding: 30px;
        }
        
        .stat-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
            border-left: 5px solid #3498db;
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
        }
        
        .stat-card h3 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 1.1em;
        }
        
        .stat-number {
            font-size: 2.5em;
            font-weight: bold;
            color: #3498db;
            margin-bottom: 5px;
        }
        
        .stat-label {
            color: #7f8c8d;
            font-size: 0.9em;
        }
        
        .results-section {
            padding: 30px;
            background: #f8f9fa;
        }
        
        .results-section h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            font-size: 1.8em;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        
        .category-results {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .result-card {
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }
        
        .result-header {
            background: #34495e;
            color: white;
            padding: 15px 20px;
            font-weight: bold;
        }
        
        .result-content {
            max-height: 400px;
            overflow-y: auto;
            padding: 15px;
        }
        
        .endpoint-item {
            padding: 8px 12px;
            margin: 5px 0;
            background: #f8f9fa;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            border-left: 3px solid #3498db;
            transition: background-color 0.2s ease;
        }
        
        .endpoint-item:hover {
            background: #e9ecef;
        }
        
        .status-200 { border-left-color: #27ae60; }
        .status-301, .status-302 { border-left-color: #f39c12; }
        .status-403 { border-left-color: #e74c3c; }
        .status-500 { border-left-color: #8e44ad; }
        
        .footer {
            background: #2c3e50;
            color: white;
            text-align: center;
            padding: 20px;
        }
        
        .chart-container {
            width: 100%;
            height: 300px;
            margin: 20px 0;
        }
        
        .no-results {
            text-align: center;
            color: #7f8c8d;
            font-style: italic;
            padding: 40px;
        }
        
        @media (max-width: 768px) {
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .category-results {
                grid-template-columns: 1fr;
            }
            
            .header h1 {
                font-size: 2em;
            }
        }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎯 Endpoint Discovery Dashboard</h1>
            <p>Advanced Web Application Security Assessment Results</p>
        </div>
        
        <div class="stats-grid" id="statsGrid">
            <!-- Stats will be populated by JavaScript -->
        </div>
        
        <div class="results-section">
            <h2>📊 Results Overview</h2>
            <div class="chart-container">
                <canvas id="resultsChart"></canvas>
            </div>
        </div>
        
        <div class="results-section">
            <h2>🔍 Discovered Endpoints</h2>
            <div class="category-results" id="categoryResults">
                <!-- Results will be populated by JavaScript -->
            </div>
        </div>
        
        <div class="footer">
            <p>Generated on <span id="scanDate"></span> | Duration: <span id="scanDuration"></span>s</p>
        </div>
    </div>

    <script>
        // Load and display results
        async function loadResults() {
            try {
                // Load statistics
                const statsResponse = await fetch('../results/statistics.json');
                const stats = await statsResponse.json();
                
                displayStats(stats);
                createChart(stats);
                
                // Load individual result files
                await loadCategoryResults();
                
            } catch (error) {
                console.error('Error loading results:', error);
                document.getElementById('categoryResults').innerHTML = 
                    '<div class="no-results">No results data available. Run the scan first.</div>';
            }
        }
        
        function displayStats(stats) {
            const statsGrid = document.getElementById('statsGrid');
            const categories = stats.categories || {};
            
            // Total endpoints card
            statsGrid.innerHTML = `
                <div class="stat-card">
                    <h3>Total Endpoints Found</h3>
                    <div class="stat-number">${stats.total_endpoints_found || 0}</div>
                    <div class="stat-label">Across all categories</div>
                </div>
            `;
            
            // Category cards
            Object.entries(categories).forEach(([category, count]) => {
                const card = document.createElement('div');
                card.className = 'stat-card';
                card.innerHTML = `
                    <h3>${category.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</h3>
                    <div class="stat-number">${count}</div>
                    <div class="stat-label">endpoints discovered</div>
                `;
                statsGrid.appendChild(card);
            });
            
            // Update footer
            document.getElementById('scanDate').textContent = new Date(stats.scan_date).toLocaleString();
            document.getElementById('scanDuration').textContent = stats.duration || 'N/A';
        }
        
        function createChart(stats) {
            const ctx = document.getElementById('resultsChart').getContext('2d');
            const categories = stats.categories || {};
            
            new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: Object.keys(categories).map(cat => 
                        cat.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
                    ),
                    datasets: [{
                        data: Object.values(categories),
                        backgroundColor: [
                            '#3498db',
                            '#e74c3c',
                            '#27ae60',
                            '#f39c12',
                            '#9b59b6',
                            '#1abc9c',
                            '#34495e',
                            '#e67e22'
                        ],
                        borderWidth: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 20,
                                usePointStyle: true
                            }
                        }
                    }
                }
            });
        }
        
        async function loadCategoryResults() {
            const categoryResults = document.getElementById('categoryResults');
            const resultFiles = [
                'fuzz_juicy_clean.txt',
                'fuzz_api_clean.txt',
                'fuzz_webhooks_clean.txt',
                'fuzz_configs_clean.txt'
            ];
            
            const categoryNames = {
                'fuzz_juicy_clean.txt': 'Juicy Endpoints',
                'fuzz_api_clean.txt': 'API Endpoints',
                'fuzz_webhooks_clean.txt': 'Webhooks',
                'fuzz_configs_clean.txt': 'Configurations'
            };
            
            for (const file of resultFiles) {
                try {
                    const response = await fetch(`../results/${file}`);
                    if (response.ok) {
                        const text = await response.text();
                        const endpoints = text.trim().split('\n').filter(line => line.trim());
                        
                        if (endpoints.length > 0) {
                            const card = document.createElement('div');
                            card.className = 'result-card';
                            
                            const categoryName = categoryNames[file] || file;
                            card.innerHTML = `
                                <div class="result-header">
                                    ${categoryName} (${endpoints.length})
                                </div>
                                <div class="result-content">
                                    ${endpoints.map(endpoint => {
                                        const statusMatch = endpoint.match(/\[(\d+)\]/);
                                        const status = statusMatch ? statusMatch[1] : '200';
                                        return `<div class="endpoint-item status-${status}">${endpoint}</div>`;
                                    }).join('')}
                                </div>
                            `;
                            categoryResults.appendChild(card);
                        }
                    }
                } catch (error) {
                    console.error(`Error loading ${file}:`, error);
                }
            }
            
            if (categoryResults.children.length === 0) {
                categoryResults.innerHTML = '<div class="no-results">No endpoint results found.</div>';
            }
        }
        
        // Load results when page loads
        document.addEventListener('DOMContentLoaded', loadResults);
    </script>
</body>
</html>
EOF
    
    log "INFO" "Dashboard generated: ${dashboard_file}"
    log "INFO" "Open ${dashboard_file} in your browser to view results"
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_banner
    parse_args "$@"
    
    log "INFO" "Starting Advanced Endpoint Discovery & Fuzzing Suite"
    log "INFO" "Configuration: Threads=${THREADS}, Rate=${RATE_LIMIT}/s, Timeout=${TIMEOUT}s"
    
    setup_directories
    check_dependencies
    extract_endpoints
    filter_endpoints
    clean_endpoints
    execute_fuzzing
    
    local end_time=$(date +%s)
    scan_duration=$((end_time - start_time))
    
    generate_summary
    generate_dashboard
    
    log "INFO" "Scan completed successfully in ${scan_duration} seconds"
    log "INFO" "Results summary: ${RESULTS_DIR}/summary.txt"
    log "INFO" "Dashboard: ${DASHBOARD_DIR}/dashboard.html"
    
    # Display quick summary
    echo -e "\n${GREEN}=== QUICK SUMMARY ===${NC}"
    if [[ -f "${RESULTS_DIR}/summary.txt" ]]; then
        tail -n 10 "${RESULTS_DIR}/summary.txt"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
