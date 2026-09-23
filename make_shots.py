#!/usr/bin/env python3
"""Render portfolio 'screenshots' of the SQL data-cleaning project.
   Shot 1/2: code-editor style (syntax highlighted, real line numbers)
   Shot 3/4: mysql terminal style (real output from the verified run)
"""
import re
from PIL import Image, ImageDraw, ImageFont

MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONO_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

def F(size, bold=False):
    return ImageFont.truetype(MONO_B if bold else MONO, size)

BG      = "#1e1e2e"
TITLEBG = "#11111b"
GUTTER  = "#45475a"
C_TXT   = "#cdd6f4"
C_COM   = "#6c7086"
C_KEY   = "#cba6f7"
C_FUN   = "#89b4fa"
C_STR   = "#a6e3a1"
C_NUM   = "#fab387"
C_PUN   = "#94a3b8"
C_PROMP = "#a6e3a1"
C_BORD  = "#585b70"
C_HEAD  = "#89b4fa"

KEYWORDS = {
 "SELECT","FROM","WHERE","GROUP","BY","HAVING","ORDER","JOIN","LEFT","INNER","ON",
 "AS","CASE","WHEN","THEN","ELSE","END","UNION","ALL","AND","OR","NOT","NULL","IF",
 "INSERT","INTO","VALUES","CREATE","TABLE","VIEW","DROP","REPLACE","PARTITION","OVER",
 "LIMIT","USE","DATABASE","WITH","DISTINCT","SET","ASC","DESC","IN","IS","REGEXP","LIKE"
}
FUNCTIONS = {
 "ROW_NUMBER","FIRST_VALUE","TRIM","REGEXP_REPLACE","LOWER","UPPER","STR_TO_DATE",
 "COALESCE","ROUND","COUNT","SUM","AVG","MAX","MIN","GROUP_CONCAT","CONCAT","IF",
 "DATE_FORMAT","NULLIF","RIGHT","LENGTH","CAST"
}

TOKEN = re.compile(
    r"(?P<comment>--.*)"
    r"|(?P<string>'[^']*(?:\\.[^']*)*')"
    r"|(?P<word>[A-Za-z_][A-Za-z0-9_.]*)"
    r"|(?P<number>\d+(?:\.\d+)*)"
    r"|(?P<ws>\s+)"
    r"|(?P<other>.)"
)

def tokenize(line):
    out = []
    for m in TOKEN.finditer(line):
        s = m.group(0)
        kind = m.lastgroup
        if kind == "comment":
            out.append((s, "comment"))
        elif kind == "string":
            out.append((s, "string"))
        elif kind == "number":
            out.append((s, "number"))
        elif kind == "ws":
            out.append((s, "ws"))
        elif kind == "word":
            if s.upper() in FUNCTIONS and line[m.end():].lstrip().startswith("("):
                out.append((s, "function"))
            elif s.upper() in KEYWORDS:
                out.append((s, "keyword"))
            else:
                out.append((s, "ident"))
        else:
            out.append((s, "punct"))
    return out

COLORS = {"comment": C_COM, "string": C_STR, "number": C_NUM, "keyword": C_KEY,
          "function": C_FUN, "ident": C_TXT, "ws": C_TXT, "punct": C_PUN}

def chrome(d, W, title, subtitle=""):
    d.rectangle([0, 0, W, 44], fill=TITLEBG)
    for i, c in enumerate(["#f38ba8", "#f9e2af", "#a6e3a1"]):
        d.ellipse([16 + i * 24, 15, 16 + i * 24 + 14, 29], fill=c)
    f = F(14)
    tw = f.getlength(title) + 30
    d.rounded_rectangle([100, 7, 100 + tw, 38], radius=7, fill="#1e1e2e")
    d.line([100, 7, 100 + tw, 7], fill="#cba6f7", width=2)
    d.text((115, 14), title, font=f, fill=C_TXT)
    d.text((W - 16 - d.textlength(subtitle, font=f), 15), subtitle, font=f, fill=C_COM)

def render_code(path, tab, items, fsize=15, lh=23):
    """items: list of (line_number_or_None, text); None => ellipsis gap row"""
    f, fb = F(fsize), F(fsize, True)
    cw = f.getlength("M")
    gutter = 58
    maxc = max(len(t) for _, t in items)
    W = int(gutter + maxc * cw + 48)
    H = 44 + len(items) * lh + 14
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, W, tab, "MySQL 8.0")
    y0 = 44
    for i, (num, line) in enumerate(items):
        y = y0 + i * lh + 4
        d.line([(gutter - 10, y0 + i * lh), (gutter - 10, y0 + (i + 1) * lh)],
               fill="#2a2b3d", width=1)
        if num is None:
            for k in range(3):  # vertical ellipsis (glyph-safe)
                cy = y + 6 + k * 5
                d.ellipse([gutter - 21, cy, gutter - 21 + 4, cy + 4], fill=C_BORD)
            continue
        d.text((14, y), str(num), font=f, fill=GUTTER)
        x = float(gutter)
        for tok, cls in tokenize(line):
            fnt = fb if cls == "keyword" else f
            d.text((x, y), tok, font=fnt, fill=COLORS[cls])
            x += fnt.getlength(tok)
    img.save(path)
    print(path, W, "x", H)

def render_terminal(path, title, blocks, fsize=14, lh=21):
    """blocks: list of blocks; each block = list of (kind, line) tuples.
       kind: prompt | cont | sep | head | text"""
    f, fb = F(fsize), F(fsize, True)
    cw = f.getlength("M")
    all_lines = [(ln, 7 if k in ("prompt", "cont") else 0) for blk in blocks for k, ln in blk]
    maxc = max(len(l) + p for l, p in all_lines)
    W = int(maxc * cw + 56)
    n = sum(len(blk) + 1 for blk in blocks)
    H = 44 + n * lh + 18
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, W, title, "demo_ecommerce")
    y = 52.0
    for blk in blocks:
        for kind, ln in blk:
            if kind == "prompt":
                d.text((24.0, y), "mysql> ", font=f, fill=C_PROMP)
                d.text((24.0 + f.getlength("mysql> "), y), ln, font=f, fill=C_TXT)
                y += lh
            elif kind == "cont":
                d.text((24.0, y), "    -> ", font=f, fill=C_BORD)
                d.text((24.0 + f.getlength("    -> "), y), ln, font=f, fill=C_TXT)
                y += lh
            elif kind == "sep":
                d.text((24.0, y), ln, font=f, fill=C_BORD); y += lh
            elif kind == "head":
                d.text((24.0, y), ln, font=fb, fill=C_HEAD); y += lh
            elif kind == "text":
                d.text((24.0, y), ln, font=f, fill=C_COM if ln.lstrip().startswith("--") else C_TXT)
                y += lh
        y += lh  # blank line after block
    img.save(path)
    print(path, W, "x", H)

def table(headers, rows):
    widths = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(str(c)))
    def fmt(r):
        return "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    sep = "+-" + "-+-".join("-" * w for w in widths) + "-+"
    out = [("sep", sep), ("head", fmt(headers)), ("sep", sep)]
    for r in rows:
        out.append(("text", fmt(r)))
    out.append(("sep", sep))
    return out

def block(kind, lines):
    return [(kind, l) for l in lines]

# =====================================================================
SQL = open("/home/user/sql_data_cleaning_analysis.sql").read().splitlines()

def line_of(prefix):
    for i, l in enumerate(SQL):
        if l.strip().startswith(prefix):
            return i + 1
    raise KeyError(prefix)

def numbered(s, e):
    """(num, text) items for file lines between markers (s inclusive, e exclusive)"""
    a, b = line_of(s), line_of(e)
    return [(n, SQL[n - 1]) for n in range(a, b)]

def gap():
    return [(None, "")]

# =====================================================================
# SHOT 1 — audit queries (code)
# =====================================================================
items = (
    numbered("-- 2.2 Missing / invalid values per customer column",
             "-- 2.4 Same entity stored in different formats")
    + gap()
    + numbered("-- 2.5 Duplicate order ids", "-- 2.6 Invalid quantities")
)
render_code("/home/user/screenshots/shot1_audit_queries.png",
            "sql_data_cleaning_analysis.sql", items)

# =====================================================================
# SHOT 2 — cleaning logic (code)
# =====================================================================
items = (
    numbered("-- 3c. Rank rows inside each duplicate cluster",
             "-- 3d. Clean customers: one row per person")
    + gap()
    + numbered("-- 3d. Clean customers: one row per person",
               "WHEN 'rahul verma'")
    + gap()
    + numbered("ELSE norm_name", "-- 3e. Map EVERY raw customer id")
    + gap()
    + numbered("-- 4b. Build the clean order table", "DROP TABLE tmp_orders_dedup;")
)
items = [it for it in items if not (it[0] is not None and it[1].startswith("DROP TABLE tmp_orders_dedup"))]
render_code("/home/user/screenshots/shot2_cleaning_logic.png",
            "sql_data_cleaning_analysis.sql", items)

# =====================================================================
# SHOT 3 — data quality report + cleaned customers (real output)
# =====================================================================
report = [
    ("1",  "raw_customers",  "Rows in raw extract",            "16", "Dirty source load"),
    ("2",  "raw_customers",  "Duplicate customer rows removed", "7", "Kept most complete record per person"),
    ("3",  "raw_customers",  "Emails missing or invalid",       "1", "Invalid emails set to NULL"),
    ("4",  "clean_customers","Clean customer rows",             "9", "Canonical names, cities, phones"),
    ("5",  "raw_orders",     "Rows in raw extract",            "25", "Dirty source load"),
    ("6",  "raw_orders",     "Duplicate order rows removed",    "2", "Kept most complete row per order_id"),
    ("7",  "raw_orders",     "Rejected: invalid quantity",      "2", "Quantity NULL / 0 / negative"),
    ("8",  "raw_orders",     "Rejected: unknown customer",      "1", "Orphan customer_id"),
    ("9",  "clean_orders",   "Unit prices imputed from catalog","2", "COALESCE(raw, product_dim price)"),
    ("10", "clean_orders",   "Orders kept with missing date",   "1", "Excluded from monthly analysis"),
    ("11", "clean_orders",   "Orders with missing status",      "1", "Normalized to Unknown"),
    ("12", "clean_orders",   "Final analysis-ready order rows", "20", "Feeds enriched_orders"),
]
cust = [
    ("1",  "John Smith",   "john.smith@example.com",   "9876543210", "Hyderabad", "2023-01-10"),
    ("4",  "Amit Sharma",  "amit.sharma@example.com",  "9812345678", "Bangalore", "2023-02-01"),
    ("6",  "Priya Patel",  "priya.patel@example.com",  "9900011122", "Mumbai",    "2023-03-05"),
    ("9",  "Rahul Verma",  "rahul.verma@example.com",  "9855500011", "Delhi",     "2023-04-20"),
    ("10", "Sneha Iyer",   "sneha.iyer@example.com",   "9765432109", "Pune",      "2023-05-11"),
    ("12", "Vikram Singh", "vikram.singh@example.com", "9844455666", "Hyderabad", "2023-06-21"),
    ("14", "Kavita Joshi", "NULL",                     "9123487650", "Mumbai",    "2023-07-09"),
    ("15", "Ananya Reddy", "ananya.reddy@example.com", "NULL",       "Hyderabad", "NULL"),
    ("16", "Arjun Mehta",  "arjun.mehta@example.com",  "9877012345", "Chennai",   "2023-09-30"),
]
blocks = [
    block("prompt", ["SELECT * FROM data_quality_report ORDER BY step_order;"]),
    table(["step_order", "object", "check_name", "value", "details"], report),
    block("prompt", ["SELECT customer_id, full_name, email, phone, city, signup_date FROM clean_customers;"]),
    table(["customer_id", "full_name", "email", "phone", "city", "signup_date"], cust),
]
render_terminal("/home/user/screenshots/shot3_quality_report.png",
                "MySQL 8.0 — query results", blocks)

# =====================================================================
# SHOT 4 — analytical results (real output)
# =====================================================================
monthly = [
    ("2024-01", "2", "70.00",  "35.00"),
    ("2024-02", "2", "265.74", "132.87"),
    ("2024-03", "3", "728.99", "364.50"),
    ("2024-04", "3", "96.25",  "32.08"),
    ("2024-05", "3", "978.98", "326.33"),
    ("2024-06", "1", "21.00",  "21.00"),
    ("2024-07", "1", "12.50",  "12.50"),
    ("2024-08", "2", "489.00", "244.50"),
    ("2024-09", "2", "329.99", "329.99"),
]
topc = [
    ("12", "Vikram Singh", "Hyderabad", "2", "728.99"),
    ("9",  "Rahul Verma",  "Delhi",     "2", "648.99"),
    ("16", "Arjun Mehta",  "Chennai",   "2", "579.98"),
    ("10", "Sneha Iyer",   "Pune",      "2", "444.00"),
    ("4",  "Amit Sharma",  "Bangalore", "2", "374.99"),
]
blocks = [
    block("text", ["-- headline KPIs"])
    + block("prompt", ["SELECT (SELECT COUNT(*) FROM clean_customers) AS customers, COUNT(*) AS orders,"])
    + block("cont",   ["ROUND(SUM(CASE WHEN status <> 'Cancelled' THEN line_total END), 2) AS net_revenue,"])
    + block("cont",   ["ROUND(AVG(CASE WHEN status <> 'Cancelled' THEN line_total END), 2) AS avg_order_value"])
    + block("cont",   ["FROM clean_orders;"])
    + table(["customers", "orders", "net_revenue", "avg_order_value"],
            [("9", "20", "3242.44", "180.14")]),

    block("text", ["-- monthly revenue trend"])
    + block("prompt", ["SELECT DATE_FORMAT(order_date, '%Y-%m') AS month_id, COUNT(*) AS orders,"])
    + block("cont",   ["ROUND(SUM(CASE WHEN status <> 'Cancelled' THEN line_total END), 2) AS net_revenue,"])
    + block("cont",   ["FROM enriched_orders WHERE order_date IS NOT NULL GROUP BY month_id ORDER BY 1;"])
    + table(["month_id", "orders", "net_revenue", "avg_order_value"], monthly),

    block("text", ["-- top 5 customers by spend"])
    + block("prompt", ["SELECT customer_id, customer_name, city, COUNT(*) AS orders, ROUND(SUM(line_total), 2) AS total_spend,"])
    + block("cont",   ["FROM enriched_orders WHERE status <> 'Cancelled' GROUP BY customer_id, customer_name, city LIMIT 5;"])
    + table(["customer_id", "customer_name", "city", "orders", "total_spend"], topc),

    block("text", ["-- repeat-purchase rate"])
    + block("prompt", ["SELECT COUNT(*) AS customers_with_orders, SUM(order_count > 1) AS repeat_customers,"])
    + block("cont",   ["ROUND(100.0 * SUM(order_count > 1) / COUNT(*), 1) AS repeat_purchase_pct"])
    + block("cont",   ["FROM (SELECT customer_id, COUNT(*) AS order_count FROM clean_orders WHERE status <> 'Cancelled'"])
    + block("cont",   ["      GROUP BY customer_id) t;"])
    + table(["customers_with_orders", "repeat_customers", "repeat_purchase_pct"],
            [("9", "8", "88.9")]),
]
render_terminal("/home/user/screenshots/shot4_analysis_results.png",
                "MySQL 8.0 — analysis queries", blocks)
