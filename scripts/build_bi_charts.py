"""Generate three BI charts from the Fashionable sales mart.

Each chart maps directly to a brief question:

    01_mumbai_styles_and_categories.png  — Q1: styles + categories in Mumbai
    02_seasonal_revenue.png              — Q2: sales trend across seasons
    03_cancellation_rate_by_region.png   — extra: geography × cancellation
"""

from pathlib import Path

import duckdb
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / "warehouse" / "fashionable.duckdb"
OUTPUT_DIR = ROOT / "presentations" / "charts"

NAVY = "#1F2A44"
RED = "#C0392B"
GREY = "#6C757D"
CATEGORY_COLORS = ["#1F2A44", "#C0392B", "#2E86AB", "#F18F01", "#5A7D3A"]


plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "axes.edgecolor": GREY,
        "axes.labelcolor": NAVY,
        "axes.titlesize": 14,
        "axes.titleweight": "bold",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "xtick.color": GREY,
        "ytick.color": GREY,
        "grid.color": "#E5E7EB",
        "figure.dpi": 120,
    }
)


def save_chart(filename: str) -> None:
    """Format and save the current chart."""
    plt.tight_layout()
    plt.savefig(
        OUTPUT_DIR / filename,
        bbox_inches="tight",
        dpi=120,
        pad_inches=0.4,
    )
    plt.close()


def set_wide_layout() -> None:
    """Make charts visually wider and prevent label overlap."""
    plt.gcf().set_size_inches(14, 6)
    plt.subplots_adjust(bottom=0.18)


def mumbai_styles_and_categories(con: duckdb.DuckDBPyConnection) -> None:
    """Brief Q1: which styles and categories are most popular in Mumbai?

    Two panels side by side:
      - LEFT  : top 10 styles by units
      - RIGHT : all categories by units (usually 5-9 present per city)
    """
    style_rows = con.execute(
        """
        select
            p.product_style,
            sum(f.quantity) as units
        from marts.fct_sales f
        join marts.dim_product      p using (product_key)
        join marts.dim_geography    g using (geography_key)
        join marts.dim_order_status s using (status_key)
        where g.ship_city = 'MUMBAI'
          and s.status_group in ('Delivered', 'Shipped')
        group by p.product_style
        order by units desc
        limit 10
        """
    ).fetchall()

    category_rows = con.execute(
        """
        select
            p.product_category,
            sum(f.quantity) as units
        from marts.fct_sales f
        join marts.dim_product      p using (product_key)
        join marts.dim_geography    g using (geography_key)
        join marts.dim_order_status s using (status_key)
        where g.ship_city = 'MUMBAI'
          and s.status_group in ('Delivered', 'Shipped')
        group by p.product_category
        order by units desc
        """
    ).fetchall()

    fig, (ax_style, ax_cat) = plt.subplots(
        1, 2,
        figsize=(15, 6),
        gridspec_kw={"width_ratios": [1.3, 1]},
    )

    # LEFT — top 10 styles
    style_names = [row[0] for row in reversed(style_rows)]
    style_units = [row[1] for row in reversed(style_rows)]
    bars = ax_style.barh(style_names, style_units, color=NAVY)
    for bar, value in zip(bars, style_units):
        ax_style.text(
            bar.get_width() + max(style_units) * 0.01,
            bar.get_y() + bar.get_height() / 2,
            f"{value:,}",
            va="center",
        )
    ax_style.set_title("Top 10 styles in Mumbai")
    ax_style.set_xlabel("Units")
    ax_style.grid(axis="x")
    ax_style.set_axisbelow(True)

    # RIGHT — all categories present in Mumbai
    cat_names = [row[0] for row in reversed(category_rows)]
    cat_units = [row[1] for row in reversed(category_rows)]
    bars = ax_cat.barh(cat_names, cat_units, color=RED)
    for bar, value in zip(bars, cat_units):
        ax_cat.text(
            bar.get_width() + max(cat_units) * 0.01,
            bar.get_y() + bar.get_height() / 2,
            f"{value:,}",
            va="center",
        )
    ax_cat.set_title("Categories in Mumbai")
    ax_cat.set_xlabel("Units")
    ax_cat.grid(axis="x")
    ax_cat.set_axisbelow(True)

    fig.suptitle(
        "Mumbai product popularity — delivered + shipped orders",
        fontsize=15,
        fontweight="bold",
        y=1.02,
        color=NAVY,
    )
    plt.tight_layout()
    plt.savefig(
        OUTPUT_DIR / "01_mumbai_styles_and_categories.png",
        bbox_inches="tight",
        dpi=120,
        pad_inches=0.4,
    )
    plt.close(fig)


def seasonal_revenue(con: duckdb.DuckDBPyConnection) -> None:
    """Brief Q2: what is the sales trend for different seasons?

    Data range 2022-03-31 → 2022-06-29 covers Spring (Mar–Apr) and Summer
    (May–Jun) only. Reports both total revenue and average daily revenue
    because Spring has ~31 days in the window and Summer ~61 — raw totals
    without normalization would misrepresent the per-day trend.
    """
    rows = con.execute(
        """
        select
            d.season,
            count(distinct d.full_date)               as days_in_data,
            count(*)                                  as orders,
            sum(f.revenue_amount)                     as total_revenue,
            sum(f.revenue_amount)
                / count(distinct d.full_date)         as avg_daily_revenue
        from marts.fct_sales f
        join marts.dim_date d using (date_key)
        group by d.season
        order by min(d.month)
        """
    ).fetchall()

    seasons  = [row[0] for row in rows]
    days     = [row[1] for row in rows]
    orders   = [row[2] for row in rows]
    total    = [float(row[3]) / 1_000_000 for row in rows]   # ₹ millions
    per_day  = [float(row[4]) / 1_000_000 for row in rows]   # ₹ millions/day

    x = list(range(len(seasons)))
    width = 0.35

    set_wide_layout()
    bars_total = plt.bar(
        [i - width / 2 for i in x], total, width,
        color=NAVY, label="Total revenue",
    )
    bars_daily = plt.bar(
        [i + width / 2 for i in x], per_day, width,
        color=RED, label="Average daily revenue",
    )

    for bar, value in zip(bars_total, total):
        plt.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + max(total) * 0.02,
            f"₹{value:.1f}M",
            ha="center",
            fontweight="bold",
        )
    for bar, value in zip(bars_daily, per_day):
        plt.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + max(total) * 0.02,
            f"₹{value:.2f}M/day",
            ha="center",
            fontweight="bold",
            color=RED,
        )

    plt.xticks(
        x,
        [f"{s}\n({d} days · {o:,} orders)" for s, d, o in zip(seasons, days, orders)],
    )
    plt.ylabel("Revenue (INR millions)")
    plt.title("Sales trend by season — total vs average daily")
    plt.legend(frameon=False, loc="upper left")
    plt.grid(axis="y")
    plt.ylim(0, max(max(total), max(per_day)) * 1.25)

    plt.figtext(
        0.5, -0.02,
        "Data range: 2022-03-31 → 2022-06-29  ·  "
        "Only Spring (Mar–Apr) and Summer (May–Jun) fall inside the window",
        ha="center",
        fontsize=9,
        style="italic",
        color=GREY,
    )
    save_chart("02_seasonal_revenue.png")


def cancellation_rate_by_region(con: duckdb.DuckDBPyConnection) -> None:
    rows = con.execute(
        """
        select
            g.region,
            count(*) as line_items,
            100 * avg(
                case when f.is_cancelled then 1 else 0 end
            ) as cancellation_rate
        from marts.fct_sales f
        join marts.dim_geography g using (geography_key)
        where g.region != 'Unknown'
        group by g.region
        order by cancellation_rate desc
        """
    ).fetchall()

    regions = [row[0] for row in rows]
    counts = [row[1] for row in rows]
    rates = [float(row[2]) for row in rows]

    set_wide_layout()

    bars = plt.bar(regions, rates, color=RED, width=0.55)

    for bar, rate, count in zip(bars, rates, counts):
        x = bar.get_x() + bar.get_width() / 2

        plt.text(
            x,
            rate + max(rates) * 0.02,
            f"{rate:.1f}%",
            ha="center",
            fontweight="bold",
        )

        plt.text(
            x,
            max(rates) * 0.05,
            f"n={count:,}",
            ha="center",
            color="white",
        )

    plt.title("Cancellation rate by region")
    plt.ylabel("Cancellation rate (%)")
    plt.ylim(0, max(rates) * 1.2)
    plt.grid(axis="y")
    save_chart("03_cancellation_rate_by_region.png")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Remove the two renamed PNGs from the previous chart set (harmless if absent).
    for stale in ("01_top_styles_mumbai.png", "02_weekly_revenue_by_category.png"):
        (OUTPUT_DIR / stale).unlink(missing_ok=True)

    with duckdb.connect(str(DATABASE), read_only=True) as connection:
        mumbai_styles_and_categories(connection)
        seasonal_revenue(connection)
        cancellation_rate_by_region(connection)

    print(f"Created 3 charts in {OUTPUT_DIR.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
