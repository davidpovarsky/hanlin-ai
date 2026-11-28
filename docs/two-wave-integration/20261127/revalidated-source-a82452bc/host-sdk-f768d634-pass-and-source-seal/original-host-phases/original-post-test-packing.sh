set -euo pipefail
  rm -rf Tests
  find . -type f -print | LC_ALL=C sort | zip -X -q "${OUTPUT_ROOT}/RuntimeHostResources.zip" -@
