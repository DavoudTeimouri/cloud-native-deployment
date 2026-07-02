#!/bin/bash
# apply-config.sh - Apply generated config.yml to Jinja2 templates
# Usage: ./apply-config.sh <config.yml> <output-dir>

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <config.yml> <output-dir>"
    echo "Example: $0 generated/config.yml generated/"
    exit 1
fi

CONFIG_FILE="$1"
OUTPUT_DIR="$2"

# Check if yq is available (for parsing YAML)
if ! command -v yq &> /dev/null; then
    echo "Error: yq (https://github.com/mikefarah/yq) is required but not installed."
    echo "Please install it first (e.g., brew install yq or snap install yq)"
    exit 1
fi

# Check if jinja2-cli is available (for rendering templates)
if ! command -v jinja2 &> /dev/null; then
    echo "Error: jinja2-cli is required but not installed."
    echo "Please install it first (e.g., pip install jinja2-cli)"
    exit 1
fi

CONFIG_DIR="$(dirname "$0")/../templates"
TEMPLATE_DIR="$CONFIG_DIR"

mkdir -p "$OUTPUT_DIR"

echo "Loading configuration from: $CONFIG_FILE"
echo "Applying templates from: $TEMPLATE_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Process each template file
find "$TEMPLATE_DIR" -name "*.j2" -type f | while read -r template; do
    # Determine output file path (remove .j2 extension, preserve relative path)
    relative_path="${template#$TEMPLATE_DIR/}"
    output_file="$OUTPUT_DIR/${relative_path%.j2}"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    echo "Processing: $template -> $output_file"
    
    # Render template with Jinja2 using variables from YAML config
    jinja2 "$template" --format=yaml --data="$CONFIG_FILE" > "$output_file"
    
    # If it's a shell script, make it executable
    if [[ "$output_file" == *.sh ]]; then
        chmod +x "$output_file"
        echo "  Made executable: $output_file"
    fi
done

echo ""
echo "✅ Configuration applied successfully!"
echo "Generated files are in: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Review generated files in $OUTPUT_DIR"
echo "  2. Copy inventory to ansible/inventory/<cluster-name>/"
echo "  3. Run OS preparation scripts"
echo "  4. Deploy with KubeSpray"