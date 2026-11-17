"""Stream CMS's national Open Payments general payments CSV and keep Maryland recipients.

Usage: curl -s URL | python3 -I scripts/filter_open_payments.py data-raw/open_payments_md_2025.csv

The national file is roughly 15 million rows; streaming it avoids storing it on disk.
fetch_data.R reads the filtered file if it exists instead of paging through the API.
"""
import csv
import sys

csv.field_size_limit(10_000_000)
reader = csv.reader(sys.stdin)
header = next(reader)
state_col = header.index("Recipient_State")
kept = 0
with open(sys.argv[1], "w", newline="") as out:
    writer = csv.writer(out)
    writer.writerow(header)
    for row in reader:
        if len(row) > state_col and row[state_col] == "MD":
            writer.writerow(row)
            kept += 1
print(f"kept {kept} Maryland rows", file=sys.stderr)
