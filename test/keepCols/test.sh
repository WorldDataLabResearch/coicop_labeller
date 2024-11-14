#!/bin/bash

# Flag to control file deletion (default to false)
DELETE_OUTPUT=false

# Parse command line arguments
while getopts "d" flag; do
    case "${flag}" in
        d) DELETE_OUTPUT=true ;;
    esac
done

# Input and output file paths
INPUT_FILE="test/keepCols/test.csv"
OUTPUT_FILE="${INPUT_FILE%.*}_output.csv"

## running the R script
Rscript coicop_labeller.R "$INPUT_FILE" index product_name_en

## checking if the R script ran successfully
if [ $? -ne 0 ]; then
    echo "Test failed: R script execution failed"
    exit 1
fi

## checking if both input and output files exist
if [ ! -f "$INPUT_FILE" ] || [ ! -f "$OUTPUT_FILE" ]; then
    echo "Test failed: Input or output file missing"
    exit 1
fi

# Get output header and clean it
OUTPUT_HEADER=$(head -n 1 "$OUTPUT_FILE" | tr -d '\r' | tr -d '"')

# Define required columns
REQUIRED_COLS=("testCol1" "testCol2" "testCol3")

# Check for each required column
MISSING_COLS=()
for col in "${REQUIRED_COLS[@]}"; do
    if ! echo "$OUTPUT_HEADER" | grep -q "$col"; then
        MISSING_COLS+=("$col")
    fi
done

# If any required columns are missing, fail the test
if [ ${#MISSING_COLS[@]} -ne 0 ]; then
    echo "Test failed: The following required columns are missing from the output file:"
    printf '%s\n' "${MISSING_COLS[@]}"
    exit 1
fi

echo "Test passed: All required columns are present in the output file"

# Delete output file if flag is set
if [ "$DELETE_OUTPUT" = true ]; then
    rm "$OUTPUT_FILE"
    echo "Output file deleted"
fi

exit 0