import asyncio
import contextvars
from pathlib import Path
from typing import AsyncIterable, Optional

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.runnables import RunnableConfig
from langchain_openai import ChatOpenAI
from langgraph.graph import START, END, StateGraph, MessagesState

UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
_current_dataset = contextvars.ContextVar("_current_dataset", default="")


async def call_model(state: MessagesState, config: RunnableConfig) -> dict:
    configurable = config.get("configurable", {})

    llm = ChatOpenAI(
        base_url=configurable.get("api_url"),
        api_key=configurable.get("api_key", "sk-dummy"),
        model=configurable.get("model", "llama3.2"),
        temperature=0,
        streaming=True,
        timeout=300,
    )

    response = await llm.ainvoke(state["messages"])
    return {"messages": [response]}


def create_graph():
    workflow = StateGraph(MessagesState)
    workflow.add_node("agent", call_model)
    workflow.add_edge(START, "agent")
    return workflow.compile()


async def run_graph_stream(
    api_url: str,
    api_key: str,
    model: str,
    prompt: str,
    system_prompt: Optional[str] = None,
    dataset: Optional[str] = None,
) -> AsyncIterable[str]:
    _current_dataset.set(dataset or "")

    try:
        graph = create_graph()

        messages = []
        if system_prompt:
            messages.append(SystemMessage(content=system_prompt))
        messages.append(HumanMessage(content=prompt))

        inputs = {"messages": messages}
        config = {
            "configurable": {
                "api_url": api_url.rstrip("/") + "/v1"
                if "api/v1" not in api_url
                else api_url,
                "api_key": api_key or "sk-dummy",
                "model": model,
                "dataset": dataset or "",
            }
        }

        async for event in graph.astream_events(inputs, config=config, version="v2"):
            kind = event.get("event")

            if kind == "on_chat_model_stream":
                chunk = event.get("data", {}).get("chunk")
                if chunk and chunk.content:
                    yield f"TOKEN:{chunk.content}"
                    await asyncio.sleep(0.01)

    except asyncio.CancelledError:
        raise
    except Exception as e:
        yield f"[ERROR: {str(e)}]"
