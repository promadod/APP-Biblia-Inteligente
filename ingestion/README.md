# Ingestão PDF → JSON

Converte `bible.pdf` (raiz do repositório ou caminho via `--pdf`) em `data/bible_kjv.json`.

## Uso

```bash
cd ingestion
pip install -r requirements.txt
python pdf_to_json.py --pdf ../bible.pdf --out ../data/bible_kjv.json
```

Opções úteis:

- `--max-pages N` — limitar páginas (debug)
- `--debug` — imprimir linhas detectadas

## Layout

O script assume texto extraído em ordem de leitura (PDF de coluna única ou fluxo linear). Para PDFs com duas colunas, o bloco é ordenado por `(coluna, y, x)` via bbox.

Ruídos comuns (cabeçalho BVBooks, número de página isolado) são filtrados.
