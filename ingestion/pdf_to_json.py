"""
Extrai versículos de um PDF bíblico (BKJ/BVBooks) para JSON estruturado.
Usa PyMuPDF; suporta ordenação por colunas via bbox.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import fitz  # PyMuPDF
import yaml

VERSE_START = re.compile(r"^(\d+)\s+(.+)$")


def load_books(yaml_path: Path) -> tuple[list[str], dict[str, str], dict[str, str], str]:
    data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
    books = [b["name"] for b in data["books"]]
    abbrev = {b["name"]: b["abbreviation"] for b in data["books"]}
    # Sinônimos → nome canônico do YAML
    aliases: dict[str, str] = {"Filemom": "Filemon"}
    return books, abbrev, aliases, data.get("version_code", "BKJ_PT")


def normalize_line(line: str) -> str:
    return " ".join(line.split())


def is_noise_line(line: str) -> bool:
    s = line.strip()
    if not s:
        return True
    low = s.lower()
    noise_substrings = (
        "bíblia king james",
        "biblia king james",
        "bvbooks",
        "editora",
        "tradução original",
        "traducao original",
        "velho testamento",
        "novo testamento",
        "old testament",
        "new testament",
        "português",
        "portugues",
        "all bible",
        "bkjfiel",
    )
    if any(n in low for n in noise_substrings):
        return True
    if re.fullmatch(r"\d{1,4}", s) and len(s) <= 4:
        return True
    return False


def page_text_ordered(page: fitz.Page) -> str:
    """Extrai texto ordenando blocos para leitura em 1 ou 2 colunas."""
    d = page.get_text("dict")
    blocks = d.get("blocks", [])
    rects: list[tuple[float, float, float, float, str]] = []
    page_w = page.rect.width
    mid_x = page_w / 2
    for b in blocks:
        if b.get("type") != 0:
            continue
        x0, y0, x1, y1 = b["bbox"]
        parts: list[str] = []
        for line in b.get("lines", []):
            spans = line.get("spans", [])
            if not spans:
                continue
            t = "".join(s.get("text", "") for s in spans)
            if t.strip():
                parts.append(t)
        if not parts:
            continue
        text = "\n".join(parts)
        col = 0 if x0 < mid_x else 1
        rects.append((col, y0, x0, text))
    rects.sort(key=lambda r: (r[0], r[1], r[2]))
    return "\n".join(r[3] for r in rects)


def extract_full_text(doc: fitz.Document, max_pages: int | None) -> str:
    chunks: list[str] = []
    n = len(doc) if max_pages is None else min(len(doc), max_pages)
    for i in range(n):
        chunks.append(page_text_ordered(doc.load_page(i)))
    return "\n".join(chunks)


def find_text_start(full: str) -> int:
    """Pula sumário: começa no primeiro Gn 1:1 típico."""
    markers = ("No princípio criou Deus", "No principio criou Deus")
    for m in markers:
        idx = full.find(m)
        if idx != -1:
            return max(0, idx - 500)
    return 0


def match_chapter_line(line: str, books_sorted: list[str], aliases: dict[str, str]) -> tuple[str, int] | None:
    s = normalize_line(line)
    for book in books_sorted:
        if not s.startswith(book + " "):
            continue
        rest = s[len(book) :].strip()
        if rest.isdigit():
            canon_name = aliases.get(book, book)
            return canon_name, int(rest)
    return None


def parse_verses(
    text: str,
    books: list[str],
    aliases: dict[str, str],
    debug: bool,
) -> list[dict]:
    books_sorted = sorted(books, key=len, reverse=True)
    lines = text.splitlines()
    start_idx = 0
    joined = "\n".join(lines)
    anchor = find_text_start(joined)
    if anchor > 0:
        prefix = joined[:anchor]
        line_skip = prefix.count("\n")
        start_idx = max(0, line_skip)

    out: list[dict] = []
    current_book: str | None = None
    current_chapter: int | None = None
    current_verse: int | None = None
    verse_buf: list[str] = []

    def flush_verse():
        nonlocal current_book, current_chapter, current_verse, verse_buf
        if current_book and current_chapter and current_verse is not None and verse_buf:
            body = " ".join(verse_buf).strip()
            if body:
                out.append(
                    {
                        "book": current_book,
                        "chapter": current_chapter,
                        "verse": current_verse,
                        "text": body,
                    }
                )
        verse_buf = []

    for raw in lines[start_idx:]:
        line = raw.strip()
        if is_noise_line(line):
            continue

        ch = match_chapter_line(line, books_sorted, aliases)
        if ch:
            flush_verse()
            current_book, current_chapter = ch
            current_verse = None
            if debug:
                print("[chapter]", current_book, current_chapter)
            continue

        if current_book is None or current_chapter is None:
            continue

        vm = VERSE_START.match(line)
        if vm:
            flush_verse()
            current_verse = int(vm.group(1))
            verse_buf = [vm.group(2).strip()]
            if debug:
                print("[verse]", current_book, current_chapter, current_verse)
            continue

        if current_verse is not None:
            verse_buf.append(line)

    flush_verse()
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="PDF da Bíblia → JSON de versículos")
    ap.add_argument("--pdf", type=Path, default=Path(__file__).resolve().parent.parent / "bible.pdf")
    ap.add_argument("--books-yaml", type=Path, default=Path(__file__).resolve().parent / "kjv_books_pt.yaml")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "data" / "bible_kjv.json")
    ap.add_argument("--meta-out", type=Path, default=None)
    ap.add_argument("--max-pages", type=int, default=None)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    books, abbrev, aliases, version_code = load_books(args.books_yaml)
    doc = fitz.open(args.pdf)
    try:
        full = extract_full_text(doc, args.max_pages)
        verses = parse_verses(full, books, aliases, args.debug)
    finally:
        doc.close()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(verses, ensure_ascii=False, indent=2), encoding="utf-8")

    meta = {
        "version_code": version_code,
        "source_pdf": str(args.pdf.resolve()),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "verse_count": len(verses),
        "abbreviations": abbrev,
    }
    meta_path = args.meta_out or (args.out.parent / (args.out.stem + ".meta.json"))
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(verses)} verses to {args.out}")
    print(f"Meta: {meta_path}")


if __name__ == "__main__":
    main()
