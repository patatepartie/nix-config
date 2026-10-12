{ pkgs }:

# Prints the warnings found in a rebuild's output ($1) that match no entry of the accepted list ($2).
pkgs.writeShellScript "unknown-warnings" ''
  set -euo pipefail

  # Byte semantics, so that undecodable output is passed through and the truncation below is predictable.
  export LC_ALL=C

  ${pkgs.gawk}/bin/awk -v accepted="$2" '
    function flush(  i) {
      if (block == "") return
      for (i = 1; i <= count; i++) {
        if (index(block, patterns[i])) { block = ""; return }
      }
      if (!(block in seen)) {
        seen[block] = 1
        report = report block "\n"
      }
      block = ""
    }

    BEGIN {
      while ((getline line < accepted) > 0) {
        sub(/[ \t\r]+$/, "", line)
        if (line != "" && line !~ /^#/) patterns[++count] = line
      }
    }

    tolower($0) ~ /warning:/ { flush(); block = $0; next }
    block != "" && /^[ \t]/ { block = block "\n" $0; next }
    { flush() }

    END {
      flush()
      # Telegram rejects a message longer than 4096 characters.
      if (length(report) > 3000) {
        report = substr(report, 1, 3000)
        # Drop a UTF-8 character cut in half, which Telegram would reject.
        sub(/[\300-\377][\200-\277]*$/, "", report)
        report = report "\n[truncated]\n"
      }
      printf "%s", report
    }
  ' "$1"
''
