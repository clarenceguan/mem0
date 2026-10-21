# Local evaluation service (no Docker)

This guide targets the `convert-evaluation-to-subtree` branch. The local config is
`evaluation/configs/local-qwen3.5.yaml`; the FastAPI wrapper is
`evaluation/docker/mem0/main.py`.

## 1. Install the checkout's Mem0 code

Run these commands from the repository root, in the Python environment you intend to use:

```bash
python -m pip install -e ".[extras]"
python -m pip install fastapi "uvicorn[standard]" pyyaml spacy
python -m spacy download en_core_web_sm
```

The editable install is important: it makes Python import the `mem0/` package from this
checkout rather than the remote Git dependency listed in the container requirements file.
Do not install `evaluation/docker/mem0/requirements.txt` for this local workflow because
it pins a separate remote Mem0 Git revision.

Verify the imported package:

```bash
python -c "import mem0; print(mem0.__file__)"
```

The printed path should be inside this repository's `mem0/` directory.

## 2. Configure the LLM endpoint

The YAML config expects an OpenAI-compatible Chat Completions endpoint. Set the key and
base URL supplied by your model provider; do not commit the key to Git.

```bash
export LLM_API_KEY='YOUR_API_KEY'
export LLM_BASE_URL='YOUR_OPENAI_COMPATIBLE_BASE_URL'
```

For Alibaba Cloud Model Studio, use the endpoint documented for your account and region.
Do not assume a mainland-China endpoint if your account is in another region. The model ID
is configured as `qwen3.5-397b-a17b`; confirm that your chosen endpoint exposes that exact
model ID.

## 3. Configure and launch

The provided config points at the existing local model directory:

`/home/guanxin/model/Qwen/Qwen3-Embedding-0.6B`

It uses 1024-dimensional vectors and `device: cuda`. If this environment cannot run the
embedding model on a compatible GPU, change `device: cuda` to `device: cpu`.

```bash
mkdir -p data
export MEM0_CONFIG_PATH="$PWD/evaluation/configs/local-qwen3.5.yaml"
python -m uvicorn evaluation.docker.mem0.main:app --host 127.0.0.1 --port 8888 --workers 1
```

Run from the repository root because Qdrant and SQLite paths are relative to the current
working directory. `--workers 1` is intentional: Qdrant Local storage should not be opened
by multiple Uvicorn worker processes simultaneously.

Health check and API docs:

```bash
curl http://127.0.0.1:8888/health
```

Open `http://127.0.0.1:8888/docs` in a browser for the interactive API schema.

## 4. Wrapper adapter changes

- `POST /search` maps the benchmark's `limit` to Mem0's `top_k`, and maps the
  `user_id` / `agent_id` / `run_id` fields into `filters`.
- `GET /memories` now accepts an optional `limit` query parameter (default 1000,
  maximum 10000) and calls `get_all(filters=..., top_k=limit)`.
- The benchmark HTTP contract is retained; the adapter translates it to this branch's
  Mem0 OSS API.

## 5. Important compatibility notes

- This is a configuration and wrapper change, not a successful runtime test. Before running
  a full benchmark, send a small add/search/get-all request and inspect the logs.
- The local Qdrant collection must be created with the same embedding dimension as the
  embedding model. If changing the model or dimension after writing vectors, use a new
  collection name or a fresh data path; vectors from different embedding models should not
  be mixed.
- If the API reports an unknown model, unsupported parameter, or authentication error, verify
  the exact model ID and endpoint expected by your API provider.
