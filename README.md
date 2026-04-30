# Bible Intelligent App

Monorepo: ingestão PDF → JSON, API **Django** + **PostgreSQL** (ou SQLite sem FTS), app **Flutter** (Riverpod + Dio).

## Estrutura

| Pasta | Descrição |
|--------|-----------|
| `ingestion/` | Script `pdf_to_json.py` (PyMuPDF), `kjv_books_pt.yaml` |
| `data/` | `bible_kjv.json` gerado + `.meta.json` |
| `backend/` | Django (`core`, `api`, `embeddings`, `search`, `rag`, `services`) |
| `mobile/` | Flutter |

Na raiz: `bible.pdf` (BKJ português usado na ingestão).

## Pré-requisitos

- Python 3.11+
- PostgreSQL 14+ (opcional; sem `DB_NAME` o Django usa SQLite, sem índices FTS/trgm do Postgres)
- Flutter SDK (canal stable)

## 1. Ingestão PDF → JSON

```powershell
cd ingestion
pip install -r requirements.txt
python pdf_to_json.py --pdf ..\bible.pdf --out ..\data\bible_kjv.json
```

## 2. Backend

```powershell
cd backend
pip install -r requirements.txt
```

Copie `.env.example` da raiz para `.env` e defina `DB_NAME` (e credenciais) para usar PostgreSQL e busca FTS/trgm.

```powershell
# SQLite (rápido para testar)
python manage.py migrate
python manage.py import_bible --version-code BKJ_PT
python manage.py seed_entities
python manage.py runserver 8010
```

Com PostgreSQL, aplique migrações (a migração `0002` cria `pg_trgm` e índices GIN em `core_verse` e `core_entity`).

### API (prefixo `/api/`)

- `GET /api/search?q=` — versículos, livros, capítulos, entidades + campo `narrative`
- `GET /api/narrative?q=` — só narrativa
- `GET /api/books/` — `?version=BKJ_PT`
- `GET /api/books/{id}/chapters/`
- `GET /api/chapters/{id}/verses`
- `GET /api/verse/random` — opcional `?book_id=`
- `GET /api/verse/daily` — opcional `?version=BKJ_PT`
- CRUD ` /api/studies/`
- `POST /api/ask` — corpo `{ "question": "...", "version": "BKJ_PT" }` → `{ "answer", "sources", "backend" }` (RAG)

### RAG (perguntas em linguagem natural)

1. `pip install -r requirements.txt` (inclui `sentence-transformers`, `torch`, `numpy`, `httpx`).
2. `python manage.py generate_embeddings` — gera vetores 384d (`all-MiniLM-L6-v2`); pula versículos já indexados (`--force` recalcula). Teste: `--limit 500`.
3. `OPENAI_API_KEY` opcional — sem chave, resposta **stub** local; com chave, `rag/llm_service.py` chama API compatível com OpenAI (`OPENAI_API_BASE`, `OPENAI_MODEL`).
4. Busca **híbrida**: similaridade de cosseno (`search/semantic_search.py`) + texto (FTS/`icontains`).
5. `Verse.embedding` é JSON (lista de 384 floats). Para **pgvector** nativo no Postgres, pode acrescentar coluna `vector(384)` + IVFFlat manualmente.

Logs: modelo `AskLog` (admin). Cache de respostas RAG: `RAG_CACHE_TTL` (segundos). Throttles DRF: `search`, `ask`.

Limite na busca clássica: `limit` (máx. 100).

## 3. Flutter

O app usa o pacote `http` e resolve o URL do backend em [`mobile/lib/core/config.dart`](mobile/lib/core/config.dart): por omissão a porta local de desenvolvimento é **8000** (alinhada com `python manage.py runserver 8000`). O emulador **Android** obtém automaticamente **`http://10.0.2.2:8000`** (`10.0.2.2` é o alias do host no emulador; `127.0.0.1` no dispositivo aponta para o próprio emulador, não para o PC). iOS Simulator, desktop e outros usam **`http://127.0.0.1:8000`**.

Num **telemóvel físico** na mesma rede, o localhost do computador não é alcançável; use o IP da máquina na LAN, por exemplo:

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

Override explícito (útil também em CI ou quando a porta do Django não é 8000):

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use apenas o **origin** do servidor (`http://HOST:PORTA`). Se definir `API_BASE_URL` com `/api` no fim, o cliente remove esse sufixo para evitar URLs duplicadas (`/api/api/...`).

Para os versículos, busca e leitura funcionarem, o PostgreSQL do backend tem de conter a Bíblia importada. A partir da pasta `backend` (com o ambiente activo e a base de dados acessível), com o ficheiro `data/bible_kjv.json` na raiz do repositório:

```powershell
cd backend
python manage.py import_bible
```

Enquanto não houver versículos, o endpoint do versículo do dia devolve 404; a mensagem de erro do servidor (ex.: *Importe a Bíblia primeiro.*) passa a ser mostrada na app.

## Comandos úteis

| Comando | Função |
|---------|--------|
| `python manage.py import_bible` | JSON → `Book` / `Chapter` / `Verse` |
| `python manage.py seed_entities` | Entidades e relações de `fixtures/entities_kjv_seed.json` |
| `python manage.py extract_entities` | Contagem de menções por entidade (somente leitura) |
| `python manage.py generate_embeddings` | Índice semântico dos versículos (sentence-transformers) |

## Notas

- O ficheiro de saída mantém o nome `bible_kjv.json` por alinhamento com o plano; o conteúdo deste PDF é **BKJ em português**.
- Versões futuras: modelo `BibleVersion` + `Book.version`.
- Narrativa: templates em `backend/services/narrative.py`; substitua por `TransformersNarrativeBackend` quando integrar NLP.
