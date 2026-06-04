import json
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import uvicorn
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from workflow.workflow import run_graph_stream

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

app = FastAPI(title="DataAnalice Backend")


def _csv_path(name: str) -> Path:
    return UPLOAD_DIR / f"{name}.csv"


def _meta_path(name: str) -> Path:
    return UPLOAD_DIR / f"{name}_meta.json"


def _load_csv(name: str) -> pd.DataFrame:
    path = _csv_path(name)
    if not path.exists():
        raise HTTPException(404, f"Dataset '{name}' not found")
    return pd.read_csv(path)


def _is_numeric(dtype) -> bool:
    try:
        return np.issubdtype(dtype, np.number)
    except TypeError:
        return False


def _infer_column_type(col: str, df: pd.DataFrame) -> str:
    dtype = df[col].dtype
    uniques = int(df[col].nunique())
    total = len(df)

    if _is_numeric(dtype):
        if uniques == 2:
            return "boolean (numeric, binary)"
        ratio = uniques / total if total > 0 else 0
        if ratio > 0.05 and uniques > 20:
            return "continuous numeric"
        return "numeric (few distinct values)"
    if pd.api.types.is_bool_dtype(dtype):
        return "boolean"
    if pd.api.types.is_datetime64_any_dtype(dtype):
        return "datetime"
    if dtype == "object" or pd.api.types.is_string_dtype(dtype):
        if total > 0 and uniques / total <= 0.05:
            return "categorical (low cardinality)"
        if uniques == total:
            return "identifier / high-cardinality text"
        return "text / categorical"
    return str(dtype)


def _build_profile_summary(df: pd.DataFrame) -> str:
    total = len(df)
    cols = len(df.columns)
    lines = [f"## Dataset Profile\n"]
    lines.append(f"- **Rows**: {total}")
    lines.append(f"- **Columns**: {cols}")
    mem = int(df.memory_usage(deep=True).sum())
    lines.append(f"- **Memory**: {mem / 1024:.1f} KB\n")

    lines.append("### Column Summary\n")
    for col in df.columns:
        col_type = _infer_column_type(col, df)
        nulls = int(df[col].isna().sum())
        uniques = int(df[col].nunique())
        parts = [f"- **{col}** — {col_type}, {uniques} unique"]

        if nulls > 0:
            parts.append(f", {nulls} missing ({nulls / total * 100:.1f}%)")

        if _is_numeric(df[col].dtype):
            v = df[col].dropna()
            if len(v) > 0:
                parts.append(
                    f", range [{v.min():.4g} – {v.max():.4g}], mean {v.mean():.4g}"
                )

        lines.append("".join(parts))
        if uniques <= 15 and uniques > 0 and total > 0:
            if _is_numeric(df[col].dtype) or df[col].dtype == "object":
                try:
                    top = df[col].value_counts().head(8)
                    sample_str = ", ".join(
                        f"{k}={v}" for k, v in zip(top.index, top.values)
                    )
                    lines.append(f"  → top values: {sample_str}")
                except Exception:
                    pass

    lines.append("")
    numeric_cols = [
        c
        for c in df.columns
        if _is_numeric(df[c].dtype) and df[c].nunique() > 1
    ]
    if len(numeric_cols) >= 2:
        lines.append("### Correlation (numeric columns)\n")
        corr = df[numeric_cols].corr().round(3)
        lines.append("```")
        lines.append(corr.to_string())
        lines.append("```\n")

    lines.append("### Sample Rows (first 5)\n")
    lines.append("```")
    lines.append(df.head(5).to_string(index=False))
    lines.append("```")

    return "\n".join(lines)


def _extract_metadata(df: pd.DataFrame) -> dict:
    numeric_cols = [c for c in df.columns if _is_numeric(df[c].dtype)]
    cat_cols = [c for c in df.columns if not _is_numeric(df[c].dtype)]

    metadata = {
        "total_rows": len(df),
        "total_columns": len(df.columns),
        "dtypes": {col: str(df[col].dtype) for col in df.columns},
        "null_counts": {col: int(df[col].isna().sum()) for col in df.columns},
        "null_pct": {
            col: round(float(df[col].isna().sum() / len(df) * 100), 2)
            for col in df.columns
        },
        "unique_counts": {col: int(df[col].nunique()) for col in df.columns},
        "memory_usage_bytes": int(df.memory_usage(deep=True).sum()),
        "numeric_stats": {
            col: {
                "min": float(df[col].min()),
                "max": float(df[col].max()),
                "mean": float(df[col].mean()),
                "median": float(df[col].median()),
                "std": float(df[col].std()),
                "q25": float(df[col].quantile(0.25)),
                "q75": float(df[col].quantile(0.75)),
                "skew": float(df[col].skew()),
            }
            for col in numeric_cols
            if df[col].nunique() > 1
        },
        "categorical_top": {
            col: df[col].value_counts().head(10).to_dict()
            for col in cat_cols
            if df[col].nunique() <= 50
        },
        "sample_rows": df.head(10).to_dict(orient="records"),
        "profile_summary": _build_profile_summary(df),
    }

    if len(numeric_cols) >= 2:
        corr = df[numeric_cols].corr().round(4)
        metadata["correlation_matrix"] = {
            "columns": numeric_cols,
            "values": [
                [float(corr.at[r, c]) for c in numeric_cols] for r in numeric_cols
            ],
        }

    return metadata


def _build_dataset_context(name: str) -> str:
    df = _load_csv(name)
    return _build_profile_summary(df)


# ---------- Routes ----------


@app.get("/")
def root():
    return {"status": "ok", "service": "DataAnalice Backend"}


@app.get("/api/v1/datasets/list")
def list_datasets():
    names = sorted({f.stem for f in UPLOAD_DIR.iterdir() if f.suffix == ".csv"})
    return {"datasets": names}


@app.post("/api/v1/datasets/upload")
async def upload_dataset(file: UploadFile = File(...)):
    if not file.filename or not file.filename.endswith(".csv"):
        raise HTTPException(400, "Only .csv files are accepted")

    stem = Path(file.filename).stem
    csv_path = _csv_path(stem)
    content = await file.read()
    csv_path.write_bytes(content)

    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        csv_path.unlink(missing_ok=True)
        raise HTTPException(400, f"Failed to parse CSV: {e}")

    metadata = _extract_metadata(df)
    meta_path = _meta_path(stem)
    meta_path.write_text(json.dumps(metadata, indent=2, default=str))

    return {"metadata": metadata}


@app.get("/api/v1/datasets/{name}/metadata")
def get_metadata(name: str):
    csv_path = _csv_path(name)
    if not csv_path.exists():
        raise HTTPException(404, f"Dataset '{name}' not found")
    meta_path = _meta_path(name)
    if meta_path.exists():
        return json.loads(meta_path.read_text())
    df = _load_csv(name)
    return _extract_metadata(df)


@app.post("/api/v1/chat")
async def chat(
    prompt: str = Form(...),
    dataset: str = Form(...),
    api_url: str = Form(...),
    api_key: str = Form(...),
    model: str = Form(...),
):
    try:
        context = _build_dataset_context(dataset)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to load dataset: {e}")

    system_prompt = (
        "You are a senior data analyst. The user has uploaded a CSV dataset "
        "and will ask questions about it. Below is a full profile of the dataset:\n\n"
        f"{context}\n\n"
        "### Guidelines\n"
        "1. **Answer precisely** — use exact numbers from the data, cite column names.\n"
        "2. **Format with Markdown** — use tables, bullet points, bold, code blocks "
        "where appropriate for readability.\n"
        "3. **Interpret column types**:\n"
        "   - *Continuous numeric*: report range, mean, quartiles; mention skew if extreme.\n"
        "   - *Categorical/low-cardinality*: report counts, proportions, top categories.\n"
        "   - *Boolean*: report True/False ratios.\n"
        "   - *Identifier/high-cardinality text*: note it exists, avoid treating as "
        "analytic dimension.\n"
        "   - *Datetime*: report time span, frequency, gaps.\n"
        "4. **Handle missing data** — if a column has nulls, note the percentage "
        "and how it might affect results.\n"
        "5. **Be concise** — answer the question directly. Do not add disclaimers or "
        "unnecessary preamble.\n"
    )

    async def event_stream():
        thinking_events = [
            {"type": "thinking", "content": "Loading dataset profile..."},
            {
                "type": "thinking",
                "content": f"Dataset '{dataset}' loaded. Analyzing query...",
            },
        ]
        for ev in thinking_events:
            yield f"data: {json.dumps(ev)}\n\n"

        try:
            token_stream = run_graph_stream(
                api_url=api_url,
                api_key=api_key,
                model=model,
                prompt=prompt,
                system_prompt=system_prompt,
                dataset=dataset,
            )
            async for token in token_stream:
                if token.startswith("[ERROR"):
                    yield (
                        f"data: {json.dumps({'type': 'error', 'content': token})}\n\n"
                    )
                elif token.startswith("TOKEN:"):
                    yield (
                        f"data: {json.dumps({'type': 'result', 'content': token[6:]})}\n\n"
                    )
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'content': str(e)})}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
