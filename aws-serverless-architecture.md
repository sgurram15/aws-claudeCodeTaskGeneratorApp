# Serverless Task Tracker — AWS Architecture

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              USERS / BROWSER                             │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │     CloudFront CDN     │
                        │  (Distribution Layer)  │
                        └─────┬───────────┬─────┘
                              │           │
              Static assets   │           │  API requests
              (HTML/CSS/JS)   │           │  /api/*
                              ▼           ▼
               ┌──────────────────┐   ┌──────────────────────────┐
               │    S3 Bucket     │   │  API Gateway (HTTP API)  │
               │                  │   │       /api/tasks          │
               │  index.html      │   │       /api/tasks/{id}     │
               │  style.css       │   └────────────┬─────────────┘
               │  app.js          │                │
               └──────────────────┘                ▼
                                       ┌───────────────────────┐
                                       │    AWS Lambda          │
                                       │                       │
                                       │  Flask + Web Adapter   │
                                       │  (existing app.py)     │
                                       └───────────┬───────────┘
                                                   │
                                                   ▼
                                       ┌───────────────────────┐
                                       │   DynamoDB Table       │
                                       │                       │
                                       │  PK: id (UUID)        │
                                       │  title                │
                                       │  description          │
                                       │  priority             │
                                       │  status               │
                                       │  due_date             │
                                       │  created_at           │
                                       └───────────────────────┘
```

## Component Breakdown

| Layer | AWS Service | Purpose |
|-------|-------------|---------|
| CDN | **CloudFront** | Single entry point, caches static assets, routes `/api/*` to API Gateway |
| Frontend | **S3** | Hosts `index.html`, `style.css`, `app.js` (origin-access-control, no public access) |
| API | **API Gateway HTTP API** | Routes REST methods to Lambda, handles CORS, throttling |
| Compute | **Lambda + Web Adapter** | Runs the existing Flask app unmodified via Lambda Web Adapter layer |
| Database | **DynamoDB** | Replaces SQLite — serverless, zero-admin, scales to zero |

## Why These Choices

| Decision | Rationale |
|----------|-----------|
| **HTTP API** over REST API | 70% cheaper, lower latency — sufficient for CRUD without WAF/caching |
| **Lambda Web Adapter** | Runs the existing Flask app with zero code changes — fastest migration path |
| **DynamoDB** over RDS/Aurora Serverless | True pay-per-request, no cold starts for DB connections, no VPC needed |
| **CloudFront + S3** over serving from Lambda | Offloads static files, reduces Lambda invocations and cost |
| **Single Lambda** (Lambdalith) | The app is small; one function keeps deployment simple with shared routing |

## DynamoDB Table Design

```
Table: TaskTrackerTasks
─────────────────────────────────────────────
Partition Key:  id        (String, UUID)
─────────────────────────────────────────────
Attributes:
  title        String
  description  String
  priority     String  (low | medium | high)
  status       String  (open | done)
  due_date     String  (YYYY-MM-DD, nullable)
  created_at   String  (ISO 8601)
─────────────────────────────────────────────
Capacity: On-Demand (PAY_PER_REQUEST)
```

For the list-all query, a **Scan** is acceptable given the single-user/small-dataset nature. If scale grows, add a GSI on `status` + `created_at` for filtered queries.

## Request Flow

```
Browser → CloudFront
  ├── GET /index.html, /static/* → S3 (cached at edge)
  └── POST/GET/PUT/DELETE /api/* → API Gateway → Lambda (Flask)
                                                      │
                                                      ▼
                                                   DynamoDB
```

## Cost at Low Traffic (~1,000 requests/day)

| Service | Estimated Monthly Cost |
|---------|----------------------|
| Lambda (128 MB, ~100ms avg) | ~$0.02 |
| API Gateway HTTP API | ~$0.03 |
| DynamoDB On-Demand | ~$0.01 |
| S3 + CloudFront | ~$0.50 (mostly CloudFront minimum) |
| **Total** | **< $1/month** |

## Migration Path (no code changes needed)

1. Replace `db.py` to use `boto3` DynamoDB client instead of sqlite3
2. Add Lambda Web Adapter layer — Flask routes stay as-is
3. Move static files to S3
4. Deploy with SAM or CDK

The Lambda Web Adapter approach means `app.py` routes, validation logic, and the frontend JavaScript remain identical — only the data layer (`db.py`) changes to DynamoDB.
