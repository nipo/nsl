# Base image with Python 3.11
FROM python:3.11-slim

# Install system dependencies and GHDL
RUN apt-get update && \
    apt-get install -y ghdl git make && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY tests/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the full repo (optional if you want it preloaded)
COPY . .
