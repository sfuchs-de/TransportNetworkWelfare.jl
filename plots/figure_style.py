"""Shared visual language for package, replication, and guide figures."""

import os
from pathlib import Path
import tempfile

os.environ.setdefault(
    "MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "tnw-matplotlib-cache")
)
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, Normalize, TwoSlopeNorm
import numpy as np


INK = "#20272B"
MUTED = "#677077"
LIGHT = "#D8DEE2"
PALE = "#F2F4F5"
WHITE = "#FFFFFF"

BLUE = "#1E71A4"
TEAL = "#2A9D8F"
ORANGE = "#CA682A"
GOLD = "#E1AE33"
PURPLE = "#7A6E9D"
RED = "#B64E4E"

SEQUENTIAL_CMAP = "viridis"
DIVERGING_CMAP = LinearSegmentedColormap.from_list(
    "tnw_orange_blue", (ORANGE, WHITE, BLUE))
MODE_COLORS = {
    "road": MUTED,
    "transit": BLUE,
    "bus": TEAL,
    "rail": ORANGE,
    "subway": PURPLE,
    "streetcar": GOLD,
    "ferry": BLUE,
    "all_transit": INK,
}

METRIC_LABELS = {
    "hulten": "Traditional approach: welfare elasticity",
    "realized_NC": "No-congestion welfare elasticity",
    "realized_NT": "Road-congestion welfare elasticity",
    "realized_F": "Realized-cost welfare elasticity",
    "primitive_F": "Extended approach: welfare elasticity",
    "extended_gain_pct": "Welfare gain from a 1% improvement (%)",
    "traditional_gain_pct": "Welfare gain from a 1% improvement (%)",
    "extended_minus_traditional_pct":
        "Extended minus traditional welfare gain (percentage points)",
}


def configure():
    """Apply the repository figure style without depending on a system font."""
    matplotlib.rcParams.update({
        "font.family": "serif",
        "font.serif": ["DejaVu Serif"],
        "mathtext.fontset": "dejavuserif",
        "font.size": 8.5,
        "axes.labelsize": 8.5,
        "axes.titlesize": 9.0,
        "axes.titleweight": "normal",
        "axes.edgecolor": MUTED,
        "axes.labelcolor": INK,
        "axes.linewidth": 0.6,
        "xtick.color": MUTED,
        "ytick.color": MUTED,
        "xtick.labelsize": 7.5,
        "ytick.labelsize": 7.5,
        "legend.fontsize": 7.5,
        "text.color": INK,
        "grid.color": LIGHT,
        "grid.linewidth": 0.45,
        "grid.alpha": 0.65,
        "lines.linewidth": 1.2,
        "figure.facecolor": "none",
        "savefig.facecolor": "none",
        "savefig.transparent": True,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    })


configure()


def metric_label(metric):
    """Return an economics-facing label for a result column."""
    return METRIC_LABELS.get(metric, metric.replace("_", " ").capitalize())


def style_axis(axis, *, grid_axis=None, zero_line=False):
    """Remove framing and retain only guides that support comparison."""
    axis.spines[["top", "right"]].set_visible(False)
    axis.spines["left"].set_color(MUTED)
    axis.spines["bottom"].set_color(MUTED)
    axis.tick_params(length=2.5, width=0.5, colors=MUTED)
    if grid_axis:
        axis.grid(axis=grid_axis, zorder=0)
    else:
        axis.grid(False)
    if zero_line:
        axis.axvline(0.0, color=MUTED, linewidth=0.75, zorder=0)
    return axis


def finite_range(values, *, robust=False, quantiles=(0.02, 0.98),
                 include_zero=False):
    """Return a finite plotting range, optionally resistant to extreme tails."""
    array = np.asarray(values, dtype=float)
    array = array[np.isfinite(array)]
    if array.size == 0:
        raise ValueError("a figure scale requires at least one finite value")
    if robust and array.size > 2:
        lower, upper = np.quantile(array, quantiles)
    else:
        lower, upper = float(array.min()), float(array.max())
    if include_zero:
        lower, upper = min(0.0, lower), max(0.0, upper)
    if upper <= lower:
        span = max(abs(lower), 1.0) * np.finfo(float).eps
        upper = lower + span
    return float(lower), float(upper)


def welfare_norm(values, *, robust=False, include_zero=True):
    """Return a perceptually ordered welfare scale and colormap."""
    lower, upper = finite_range(
        values, robust=robust, include_zero=include_zero)
    if lower < 0 < upper:
        limit = max(abs(lower), abs(upper))
        return TwoSlopeNorm(vmin=-limit, vcenter=0.0, vmax=limit), DIVERGING_CMAP
    return Normalize(vmin=lower, vmax=upper, clip=robust), SEQUENTIAL_CMAP


def shared_identity_limits(x, y, *, padding=0.04):
    """Return common x and y limits for an identity-line comparison."""
    lower, upper = finite_range(np.concatenate((x, y)), include_zero=False)
    margin = padding * (upper-lower)
    return lower-margin, upper+margin


def average_ranks(values):
    """Return average zero-based ranks with deterministic tie handling."""
    values = np.asarray(values, dtype=float)
    order = np.argsort(values, kind="mergesort")
    ranks = np.empty(len(values), dtype=float)
    first = 0
    while first < len(values):
        last = first + 1
        while last < len(values) and values[order[last]] == values[order[first]]:
            last += 1
        ranks[order[first:last]] = 0.5 * (first+last-1)
        first = last
    return ranks


def correlations(x, y):
    """Return Pearson and Spearman correlations, or NaN for a singleton."""
    x, y = np.asarray(x, dtype=float), np.asarray(y, dtype=float)
    if len(x) < 2 or np.ptp(x) == 0.0 or np.ptp(y) == 0.0:
        return np.nan, np.nan
    x_rank, y_rank = average_ranks(x), average_ranks(y)
    spearman = (
        np.nan if np.ptp(x_rank) == 0.0 or np.ptp(y_rank) == 0.0
        else float(np.corrcoef(x_rank, y_rank)[0, 1])
    )
    return float(np.corrcoef(x, y)[0, 1]), spearman


def add_panel_label(axis, label, description=None):
    """Place a quiet panel marker inside an otherwise untitled panel."""
    if description is None:
        text = label
    elif label:
        text = f"{label}  {description}"
    else:
        text = description
    axis.text(
        0.0, 1.015, text, transform=axis.transAxes, ha="left", va="bottom",
        fontsize=8.5, fontweight="normal", color=INK,
    )


def save_figure(
    figure, path, *, dpi=300, close=True, transparent=True, tight=True
):
    """Write one deterministic PDF or transparent PNG."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = {"Creator": "TransportNetworkWelfare.jl"}
    if path.suffix.lower() == ".pdf":
        metadata.update({"CreationDate": None, "ModDate": None})
    elif path.suffix.lower() == ".png":
        metadata = {"Software": "TransportNetworkWelfare.jl"}
    figure.savefig(
        path, dpi=dpi, bbox_inches="tight" if tight else None,
        transparent=transparent,
        metadata=metadata,
    )
    if close:
        plt.close(figure)
    return path


def save_figure_pair(figure, output, stem, *, dpi=300, tight=True):
    """Write matching deterministic PDF and transparent PNG assets."""
    output = Path(output)
    pdf = save_figure(
        figure, output / f"{stem}.pdf", dpi=dpi, close=False,
        transparent=True, tight=tight)
    png = save_figure(
        figure, output / f"{stem}.png", dpi=dpi, close=False,
        transparent=True, tight=tight)
    plt.close(figure)
    return [pdf, png]
