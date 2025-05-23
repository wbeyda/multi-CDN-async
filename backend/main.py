import time
from fastapi import FastAPI
from celery import Celery, shared_task
from config import settings

app = FastAPI()

celery = Celery(
    __name__,
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND
)

@shared_task
def long_running_task(device_token: str):
    time.sleep(5)  # Simulate a long-running task
    with open("task.log", "a") as log_file:
        log_file.write(f"Task completed for {device_token} at {time.ctime()}\n")
    return f"Task completed for {device_token}"

@app.get("/task/{device_token}")
async def trigger_task(device_token: str):
    task = long_running_task.delay(device_token)
    return {"task_id": task.id, "message": "Task queued"}

@app.get("/task/status/{task_id}")
async def check_task_status(task_id: str):
    from celery.result import AsyncResult
    task = AsyncResult(task_id, app=celery)
    return {
        "task_id": task_id,
        "status": task.status,
        "result": task.result if task.status == "SUCCESS" else None
    }
