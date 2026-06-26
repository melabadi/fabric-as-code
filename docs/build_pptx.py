#!/usr/bin/env python
"""
build_pptx.py — generate a simple PowerPoint deck for the Fabric-as-Code demo.

Usage:
    python docs/build_pptx.py

Produces: docs/Fabric-as-Code.pptx (embedding the screenshots in docs/screenshots).
Requires: python-pptx  (pip install python-pptx)
"""
from pathlib import Path
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

HERE = Path(__file__).resolve().parent
SHOTS = HERE / "screenshots"
OUT = HERE / "Fabric-as-Code.pptx"

# 16:9
prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
SW, SH = prs.slide_width, prs.slide_height

BLANK = prs.slide_layouts[6]

FABRIC = RGBColor(0x11, 0x73, 0x65)   # Fabric green
DARK = RGBColor(0x20, 0x20, 0x20)
GREY = RGBColor(0x55, 0x55, 0x55)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


def add_band(slide, height=Inches(1.1), color=FABRIC):
    box = slide.shapes.add_shape(1, 0, 0, SW, height)  # 1 = rectangle
    box.fill.solid()
    box.fill.fore_color.rgb = color
    box.line.fill.background()
    box.shadow.inherit = False
    return box


def textbox(slide, left, top, width, height, text, size=18, color=DARK,
            bold=False, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    lines = text.split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        run = p.add_run()
        run.text = line
        run.font.size = Pt(size)
        run.font.bold = bold
        run.font.color.rgb = color
    return tb


def title_slide(title, subtitle, tagline):
    s = prs.slides.add_slide(BLANK)
    bg = s.shapes.add_shape(1, 0, 0, SW, SH)
    bg.fill.solid(); bg.fill.fore_color.rgb = FABRIC; bg.line.fill.background()
    bg.shadow.inherit = False
    textbox(s, Inches(0.8), Inches(2.4), Inches(11.7), Inches(1.5), title,
            size=54, color=WHITE, bold=True)
    textbox(s, Inches(0.85), Inches(3.9), Inches(11.6), Inches(1.2), subtitle,
            size=24, color=WHITE)
    textbox(s, Inches(0.85), Inches(5.2), Inches(11.6), Inches(0.6), tagline,
            size=16, color=RGBColor(0xD7, 0xEF, 0xE9))


def content_slide(title, bullets):
    s = prs.slides.add_slide(BLANK)
    add_band(s)
    textbox(s, Inches(0.6), Inches(0.18), Inches(12), Inches(0.8), title,
            size=30, color=WHITE, bold=True, anchor=MSO_ANCHOR.MIDDLE)
    body = s.shapes.add_textbox(Inches(0.8), Inches(1.5), Inches(11.7), Inches(5.4))
    tf = body.text_frame
    tf.word_wrap = True
    for i, (txt, lvl) in enumerate(bullets):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.level = lvl
        run = p.add_run()
        run.text = ("• " if lvl == 0 else "– ") + txt
        run.font.size = Pt(22 if lvl == 0 else 18)
        run.font.color.rgb = DARK if lvl == 0 else GREY
        p.space_after = Pt(8)


def image_slide(title, caption, images):
    """images: list of filenames placed side by side."""
    s = prs.slides.add_slide(BLANK)
    add_band(s)
    textbox(s, Inches(0.6), Inches(0.18), Inches(12), Inches(0.8), title,
            size=30, color=WHITE, bold=True, anchor=MSO_ANCHOR.MIDDLE)
    textbox(s, Inches(0.6), Inches(1.2), Inches(12.1), Inches(0.6), caption,
            size=16, color=GREY)

    paths = [SHOTS / n for n in images]
    paths = [p for p in paths if p.exists()]
    if not paths:
        textbox(s, Inches(0.6), Inches(3), Inches(12), Inches(1),
                "[screenshot missing: " + ", ".join(images) + "]", size=16, color=GREY)
        return

    from PIL import Image
    area_top = Inches(2.0)
    area_h = Inches(4.9)
    gap = Inches(0.3)
    n = len(paths)
    total_w = SW - Inches(1.2) - gap * (n - 1)
    each_w = int(total_w / n)
    x = Inches(0.6)
    for p in paths:
        with Image.open(p) as im:
            ar = im.height / im.width
        w = each_w
        h = int(w * ar)
        if h > area_h:
            h = int(area_h)
            w = int(h / ar)
        y = area_top + int((area_h - h) / 2)
        s.shapes.add_picture(str(p), x, y, width=w, height=h)
        x += each_w + gap


# ---- Build the deck ---------------------------------------------------------
title_slide(
    "Fabric-as-Code",
    "Deploy Microsoft Fabric end-to-end — from nothing to a running platform",
    "Azure CLI  ·  Bicep  ·  Fabric REST APIs",
)

content_slide("The problem: two control planes", [
    ("Microsoft Fabric has two separate control planes — the portal covers neither repeatably:", 0),
    ("Azure — the Fabric capacity (Microsoft.Fabric/capacities), the billable compute", 1),
    ("Fabric — workspaces and items: Lakehouse, Warehouse, Notebook, Pipeline…", 1),
    ("Data — objects inside an item, e.g. stored procedures in a Warehouse", 1),
    ("ARM/portal cannot create workspaces or items — only the Fabric REST API can.", 0),
])

content_slide("What this repo does", [
    ("One config file drives a fully working environment:", 0),
    ("Provision a resource group + Fabric capacity (Bicep)", 1),
    ("Create a Fabric workspace (REST)", 1),
    ("Assign the workspace to the capacity (REST)", 1),
    ("Deploy items — Lakehouse, Warehouse, Notebook, Data Pipeline (REST)", 1),
    ("Deploy stored procedures into the Warehouse (T-SQL)", 1),
    ("Optional: connect the workspace to Git", 1),
    ("Every step is idempotent and parameter-driven — re-runnable and safe.", 0),
])

content_slide("Repeatable by design", [
    ("All tenant / subscription / secret values live in a git-ignored .env", 0),
    ("Duplicate .env per environment: .env.dev, .env.customerA, …", 0),
    ("Same scripts, different config → identical environment in any tenant / RG", 0),
    ("Service-principal auth for CI/CD and multi-tenant automation", 0),
    ("PowerShell and bash versions of every script", 0),
    ("Public repo: contains no secrets", 0),
])

image_slide("Fabric — workspace contents",
            "Every item created via the Fabric REST API.",
            ["01-workspace-list.png"])
image_slide("Fabric — Lakehouse with data",
            "orders_bronze Delta table, written by the notebook run (5 rows).",
            ["02-lakehouse-table.png"])
image_slide("Fabric — Notebook",
            "nb_demo_load, bound to the Lakehouse, writes the demo dataset with PySpark.",
            ["03-notebook.png"])
image_slide("Fabric — Data Pipeline",
            "Wait → Run Notebook (design), and a Succeeded run.",
            ["04-pipeline-canvas.png", "05-pipeline-run.png"])
image_slide("Azure — Fabric capacity",
            "The billable Microsoft.Fabric/capacities resource (F2), deployed by Bicep.",
            ["06-azure-capacity.png"])

content_slide("What you can build on this", [
    ("Medallion data platform — Lakehouse (bronze/silver/gold) + Spark notebooks", 0),
    ("SQL warehousing — Warehouse with versioned schema, tables & stored procedures", 0),
    ("Orchestration — Data Pipelines chaining notebooks, copies & procs", 0),
    ("Promotion — Git integration + deployment pipelines (dev → test → prod)", 0),
    ("Governance as code — capacity sizing, admins and RBAC in source control", 0),
])

content_slide("Get started", [
    ("git clone https://github.com/<owner>/fabric-as-code", 0),
    ("cp .env.example .env   (fill in tenant / subscription / capacity)", 0),
    ("pwsh ./scripts/powershell/deploy-all.ps1", 0),
    ("…or  ./scripts/bash/deploy-all.sh", 0),
    ("Tear it all down with 99-teardown.", 0),
])

prs.save(OUT)
print(f"Wrote {OUT}")
