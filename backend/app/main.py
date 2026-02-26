from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(
    title="DevOps Assignment API",
    description="Backend API for PGAGI DevOps Assignment",
    version="1.0.0"
)

# CORS configuration - allow frontend to communicate
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"message": "DevOps Assignment Backend", "status": "running"}


@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "message": "Backend is running successfully"
    }


@app.get("/api/message")
async def get_message():
    return {
        "message": "You've successfully integrated the backend!"
    }
