#!/bin/bash
# Keeps xcodebuild output readable: errors, warnings from our code, and the final verdict.
set -o pipefail
grep -E --line-buffered "(error:|warning: .*(Dropshot/|DropshotCore/)|\*\* BUILD|\*\* ARCHIVE|\*\* TEST|^xcodebuild: error)" | grep -v "appintentsmetadataprocessor" | awk '!seen[$0]++'
exit "${PIPESTATUS[0]}"
