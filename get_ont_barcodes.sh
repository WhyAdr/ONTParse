#!/usr/bin/env bash
# ==============================================================================
# get_ont_barcodes.sh
# Extract unique Sample IDs and Barcodes from ONT FASTQ files
# ==============================================================================

set -euo pipefail

# --- Defaults ---
threads=4
input_file=""
output_file=""

# --- Functions ---
usage() {
    echo "Usage: $(basename "$0") -i <reads.fastq.gz> [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -i, --input FILE      Input ONT FASTQ file (gzipped or uncompressed)"
    echo ""
    echo "Optional:"
    echo "  -o, --output FILE     Output TSV file (default: print to STDOUT)"
    echo "  -t, --threads N       Number of threads for decompression (default: 4)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Example:"
    echo "  bash $(basename "$0") --input pass.fastq.gz --output barcodes.tsv --threads 8"
    exit 0
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
    exit 1
}

# --- Parse Arguments ---
if [[ $# -eq 0 ]]; then usage; fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)   input_file="$2"; shift 2 ;;
        -o|--output)  output_file="$2"; shift 2 ;;
        -t|--threads) threads="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            log_error "Unknown flag: $1. Use --help for usage." ;;
    esac
done

# --- Validation ---
if [[ -z "${input_file}" ]]; then
    log_error "Missing required argument: --input. Use --help for usage."
fi

if [[ ! -f "${input_file}" ]]; then
    log_error "File not found: ${input_file}"
fi

if ! [[ "${threads}" =~ ^[0-9]+$ ]] || [[ "${threads}" -le 0 ]]; then
    log_error "Threads must be a positive integer, got: ${threads}"
fi

# --- Determine Read Command ---
if [[ "${input_file}" == *.gz ]]; then
    # Fallback to single-threaded zcat if pigz isn't installed
    if command -v pigz &>/dev/null; then
        READ_CMD="pigz -dc -p ${threads}"
    else
        echo -e "\033[1;33m[WARN]\033[0m pigz not found. Falling back to single-threaded zcat." >&2
        READ_CMD="zcat -f"
    fi
else
    READ_CMD="cat"
fi

# --- Execution ---
process_reads() {
    $READ_CMD "${input_file}" | awk '
    BEGIN {
        print "Sample_ID\tBarcode"
        print "-----------------------------------"
    }
    NR % 4 == 1 && /sample_id=/ && /barcode=/ {
        sample = "UNKNOWN"
        barcode = "UNKNOWN"
        
        for (i=1; i<=NF; i++) {
            if ($i ~ /^sample_id=/) { split($i, arr, "="); sample = arr[2] }
            if ($i ~ /^barcode=/) { split($i, arr, "="); barcode = arr[2] }
        }
        
        print sample "\t" barcode
    }' | sort -u | column -t
}

# Run processing and route output
if [[ -n "${output_file}" ]]; then
    process_reads > "${output_file}"
    echo -e "\033[1;32m[SUCCESS]\033[0m Extracted barcodes written to -> ${output_file}"
else
    process_reads
fi
