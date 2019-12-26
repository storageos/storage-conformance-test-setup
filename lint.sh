#!/bin/bash

# Check all the scripts. Ignore .git dir.
find "$PWD" -path "$PWD/.git" -prune -o -type f -exec grep -Eq '^#!(.*/|.*env +)(sh|bash|ksh)' {} \; -print |
  while IFS="" read -r file
  do
    shellcheck "$file"
  done
