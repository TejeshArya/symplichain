# Symplichain Software Engineering Intern Hackathon Submission

## Part 1: Shared Gateway Problem (40% weightage)

**Scenario:** Rate limit of exactly <= 3 req/sec to a shared external API across 25 active customers. Need fairness so high-volume customers do not block low-volume customers.

### 1. Architecture
I propose a **Message Queue with a Dispatcher and a Rate-Limited Worker Pool**. Given the existing stack (Celery + Redis), we can leverage it without introducing entirely new paradigms, but we need custom routing for fairness.
- **Queues (Redis):** Instead of one global `celery` queue, we create 25 distinct logical queues in Redis, one for each active customer (e.g., `api_queue_cust_A`, `api_queue_cust_B`).
- **Dispatcher (or Celery Beat task):** A lightweight background service that polls these customer queues using a **Round-Robin** algorithm. It pulls one request from `customer A`, one from `customer B`, and pushes them into an `execution_queue`.
- **Worker (Celery):** A Celery worker specifically assigned to consume from the `execution_queue`. This worker manages the precise outbound rate limit.

### 2. Rate enforcement
To guarantee exactly **≤3 requests per second**:
- **Token Bucket algorithm via Redis:** Before the worker makes an API call, it must acquire a token from Redis. The bucket capacity is 3, and a background task (or Redis Lua script) refills it at 3 tokens per second.
- Alternatively, utilizing Celery's built-in rate limits: `@app.task(rate_limit='3/s')`. However, Celery rate limits operate per worker process. To ensure a strict global limit across multiple distributed servers/workers, a **distributed lock or Token Bucket in Redis** is mandatory.

### 3. Fairness
- Emphasize **Round-Robin Queueing** driven by the Dispatcher.
- If Customer A floods 100 requests, they all go into `api_queue_cust_A`.
- If Customer B sends 1 request, it goes into `api_queue_cust_B`.
- The Dispatcher takes 1 request from queue A, then 1 from queue B, moving them to the `execution_queue`. 
- Thus, B's request will be processed immediately (or at worst, after one of A's requests), preventing starvation and ensuring complete fairness across the customer base.

### 4. Failure handling
- **5xx Server Errors (Temporary backend issue):** Implement **Exponential Backoff with Jitter**. First retry after 1s, then 2s, 4s, 8s maxing out at a threshold. The jitter prevents thundering herd problems.
- **429 Too Many Requests (Rate limit accidentally violated):** If the external API rejects us because it thinks we breached the limit (perhaps due to clock temporal drift or unstated API side-effects), immediately halt queue consumption for ~5 seconds (penalty box) and push the request back to the top of the queue.
- **Dead Letter Queue (DLQ):** After `X` unsuccessful retries (e.g., 5), push the request to a DLQ so we don't indefinitely block the queue, and emit a CloudWatch metric to alert the engineering team.

---

## Part 2: Mobile Architecture (20% weightage)

**Scenario:** Customer-facing mobile app of SymFlow web platform. Fluid, friction-less.

### Interaction Model
- **Hybrid Gesture / Natural Language / Speech-to-Text.**
- As a logistics app intended for drivers and warehouse workers, the users are often wearing gloves, driving, or handling packages with both hands. The primary entry model should be **Voice/Speech-to-Text** combined with "SymAI" (e.g., driver speaks: "Package 1234 delivered to the front desk, collected by John").
- UI must utilize bold, oversized gesture-based actions (e.g., **"Swipe right to mark delivered"**) rather than precision clicks (small buttons), as this minimizes physical friction in the field.

### Tech Stack
- **React Native (with Expo)**
- **Why?** Since the SymFlow web platform is built on React + Tailwind CSS, React Native is the pragmatic and cost-conscious choice. 
- It allows sharing core business logic, utility files, validation schemas, and state management (e.g., Redux APIs) with the web frontend.
- It provides a faster time-to-market using a single codebase for both iOS and Android.
- The learning curve for the existing engineering team is very low, reducing operational maintenance. While native Kotlin/Swift yields higher absolute performance, a typical B2B workflow app rarely requires high-fps graphic rendering that necessitates full native code.

---

## Part 3: CI/CD and Deployment Pipeline (20% weightage)

The CI/CD GitHub Actions YAML files, along with Docker and Terraform improvements, have been authored into the repository structure.

### Files included in the accompanying repository:
1. `.github/workflows/deploy-staging.yml` - Builds React frontend, syncs to S3, invalidates CloudFront, and updates the Staging EC2 via SSH commands.
2. `.github/workflows/deploy-prod.yml` - Same process but triggered on `main` branch pushing to Production environments.
3. `Dockerfile` - Containerizes the Django/Gunicorn app for consistent execution.
4. `docker-compose.yml` - Enables robust local multi-container development (Django, Celery, Postgres, Redis).
5. `terraform/main.tf` & `terraform/variables.tf` - Encodes the infrastructure into IaC (EC2, S3, RDS, ElastiCache, CloudFront) to replace the current semi-manual deployments.

---

## Part 4: Debugging (20% weightage)

**The Monday morning outage:** POD photo uploads failing.
Data Path: `Driver app -> Django API (EC2) -> S3 -> Celery -> Bedrock -> PostgreSQL (RDS)`

### Debugging Steps (In chronological order)

**1. Verify the Entry Point (Django API on EC2)**
- **Why:** I need to know if the image ever reaches our servers or if the failure happens immediately. Are we returning a 500 error to the mobile app, or is the upload succeeding but the async processing failing?
- **Action:** Check Nginx and Django logs on the EC2 instance.
- **Commands:** 
  - `tail -n 100 /var/log/nginx/access.log` and `/var/log/nginx/error.log` (look for 4xx or 5xx codes).
  - `grep "ERROR" /path/to/django/logs/app.log`
- If Django is logging AWS permission errors (`AccessDenied` on S3 upload), the credentials in Secrets Manager might have rotated or expired over the weekend.

**2. Check S3 Upload & Celery Task Trigger**
- **Why:** If the API logged a `200 OK`, S3 likely succeeded. The next layer is the message broker. Did the Celery task get triggered?
- **Action:** Open the **Celery Flower Dashboard**. 
- Look for the POD validation task. Are the tasks queued? Are they actively running? Did they transition to `FAILURE` state? Are the workers online? If the queue is massively backed up but workers are idle, Redis might be running out of memory, or the workers might be dead/zombified. 

**3. Analyze Bedrock Integration (CloudWatch)**
- **Why:** If Celery tasks are failing, the SymAI model validation via Bedrock might be the bottleneck. 
- **Action:** Open the **AWS CloudWatch Console**, navigate to Bedrock Metrics & Logs.
- Look for the Bedrock Invocation metrics (`Invocations`, `InvocationClientErrors`, `ThrottlingException`). A fine-tuned Sagemaker/Bedrock model might be offline, or we're hitting a hard quota limit due to a sudden Monday traffic surge.

**4. Database Verification (RDS Console)**
- **Why:** If Bedrock validation succeeds but results are lost, the database write is failing.
- **Action:** Open the **RDS Console** and review RDS CloudWatch metrics.
- Look at `DatabaseConnections` and `CPUUtilization`. Did the DB hit its connection limit (`max_connections`) due to a connection leak in the Celery workers over the weekend? 
- **Command:** Connect via `psql` and run `SELECT * FROM pg_stat_activity;` to check for frozen, deadlocked, or long-running transactions blocking the writes.
