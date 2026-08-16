import sys
from decimal import Decimal, InvalidOperation

if len(sys.argv) != 3:
    print("Usage: reconcile_anomaly.py <hive_file> <mysql_file>")
    sys.exit(2)

hive_file = sys.argv[1]
mysql_file = sys.argv[2]

DECIMAL_COLUMNS = {
    1,   # total_sales
    5,   # avg_order_value
    7,   # prev_sales
    8,   # sales_change_pct
    9,   # sales_loss_amount
    10,  # orders_change_pct
    11,  # customers_change_pct
    12,  # quantity_change_pct
    13,  # aov_change_pct
}


def normalize(value, column_index):
    value = value.strip()

    if value in {"NULL", r"\N", ""}:
        return None

    if column_index in DECIMAL_COLUMNS:
        try:
            return Decimal(value)
        except InvalidOperation:
            return value

    return value


def load(path):
    rows = {}

    with open(path, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            line = line.rstrip("\n")

            if not line:
                continue

            columns = line.split("\t")

            if len(columns) != 16:
                raise ValueError(
                    f"{path}:{line_number}: expected 16 columns, "
                    f"got {len(columns)}"
                )

            normalized = tuple(
                normalize(value, index)
                for index, value in enumerate(columns)
            )

            dt = normalized[0]

            if dt in rows:
                raise ValueError(
                    f"{path}:{line_number}: duplicate dt={dt}"
                )

            rows[dt] = normalized

    return rows


hive_rows = load(hive_file)
mysql_rows = load(mysql_file)

all_dates = sorted(set(hive_rows) | set(mysql_rows))

errors = 0

for dt in all_dates:
    hive_row = hive_rows.get(dt)
    mysql_row = mysql_rows.get(dt)

    if hive_row is None:
        print(f"MISMATCH dt={dt}: missing in Hive")
        errors += 1
        continue

    if mysql_row is None:
        print(f"MISMATCH dt={dt}: missing in MySQL")
        errors += 1
        continue

    if hive_row != mysql_row:
        print(f"MISMATCH dt={dt}")

        for index, (hive_value, mysql_value) in enumerate(
            zip(hive_row, mysql_row)
        ):
            if hive_value != mysql_value:
                print(
                    f"  column[{index}]: "
                    f"Hive={hive_value!r}, MySQL={mysql_value!r}"
                )

        errors += 1

if errors:
    print(f"FAIL: {errors} business date(s) mismatched.")
    sys.exit(1)

print(
    f"PASS: Hive/MySQL anomaly data matched "
    f"for {len(hive_rows)} business date(s)."
)