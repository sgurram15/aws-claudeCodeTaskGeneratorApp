#!/bin/bash
exec gunicorn --bind :${PORT:-8000} --workers 1 --threads 2 app:app
