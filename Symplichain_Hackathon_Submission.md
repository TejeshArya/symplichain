# Symplichain Hackathon Submission

**Candidate:** [Your Name Here]  
**Role:** Software Engineering Intern Applicant  

---

## Part 1: Shared Gateway Problem

**Scenario:** Rate limit of 3 requests/sec to a shared external API, with >20 requests/sec coming during peak hours from 25 active customers. Need request pooling, rate limiting, fairness, and failure handling.

### 1. Architecture
We will utilize the existing stack: **Redis (ElastiCache)** for high-throughput queuing and state management, and **Celery** for asynchronous task execution.

* **Request Context (Django):** The Django view accepts the user's request, immediately acknowledges it (HTTP 202 Accepted, returning a Webhook/Job ID), and pushes the payload into a **Customer-Specific Redis Queue**.
* **Dispatcher (Celery Beat):** A scheduled task polling the queues fairly and dispatching precisely 3 tasks per second to the execution workers.
* **Execution Workers (Celery):** The workers that perform the outbound HTTP calls.

### 2. Rate Enforcement (≤3 per second)
To strictly enforce the ≤3 requests/sec limit, we use a **Token Bucket Algorithm** backed by Redis.
* **Redis Token Bucket:** A Redis key holds tokens (max 3). A background process or Lua script replenishes it exactly at a rate of 3 tokens per second.
* Before making the external API call, a Celery worker must acquire a token (`DECR`). If none are available, the task is re-queued with a delay.
* *Alternative approach:* Use Celery's built-in `rate_limit='3/s'` on the HTTP task. However, a global Redis lock/token bucket is safer across multiple generic worker nodes to guarantee a hard global limit.

### 3. Fairness
Instead of a giant single queue where Customer A's 100 requests block Customer B's 1 request, we implement isolated queues.
* **Customer-Specific Queues:** Each customer has their own Redis List (e.g., `queue:cust_A`, `queue:cust_B`).
* **Round-Robin Dispatching:** Our dispatcher iterates over a list of active customers. It pops *one* request from Customer A, then *one* from Customer B, then *one* from Customer C. 
* This mathematically guarantees that Customer B will have their request processed within the first few seconds regardless of Customer A's massive backlog.

### 4. Failure Handling
* **Exponential Backoff:** If the external API fails (e.g., 500 Server Error), we catch the exception and use Celery's `retry_backoff=True` feature. The wait time between retries doubles (e.g., 1s, 2s, 4s...) so we don't overwhelm the API.
* **Circuit Breaker Pattern:** If we detect a sustained complete outage (e.g., 10 consecutive failures), the system temporarily pauses active queue dispatching for 60 seconds (Circuit Open) to prevent dropping requests entirely or wasting resources.

---

## Part 2: Mobile Architecture

**Scenario:** A fluid, mobile-optimized version of the SymFlow web platform with minimal friction for Logistics partners/drivers.

### 1. Interaction Model: Hybrid Touch + Natural Language
**Why:** Truck drivers often wear gloves and require high focus. Tiny buttons and nested menus generate immense friction.
* **Primary (Voice via SymAI):** Drivers can tap a large "Push-to-Talk" zone anywhere on the screen and say: *"Delivery confirmed at Warehouse 4, proof of delivery attached."* SymAI parses this intent to update the job state.
* **Secondary (Large Gestures):** For tactile interactions, the app utilizes massive swipe targets (e.g., "Swipe to mark complete" - similar to answering a call) rather than small precision taps. 
* Optical Character Recognition (OCR) / automatic snapshot capture is leveraged so drivers don't have to carefully focus photos of PODs.

### 2. Tech Stack: React Native
**Why React Native over Native (Kotlin/Swift)?**
* **Code Reusability:** SymFlow's frontend is already React. By selecting React Native, we can reuse massive pools of logic, state management (Redux/Zustand), API hooks, and utility classes. 
* **Velocity & Resources:** A fast-moving startup cannot afford to maintain three divergent frontends (Web, Android, iOS) with three separate engineering teams. 
* **Over-the-Air Updates (OTA):** Important bug fixes in delivery logistics can't wait for a 48-hour App Store review. React Native allows for OTA updates directly to the edge devices via CodePush or Expo.

---

## Part 3: CI/CD and Deployment Pipeline

The pipeline is automated using GitHub Actions. To improve this process in the future, we could introduce **Docker** to containerize the environments (eliminating manual `pip install` on bare EC2 to guarantee environment parity) and **Terraform** to provision the EC2, RDS, and Redis infrastructure via code (IaC), allowing us to rapidly spin up identical test networks.

### Staging Deployment YAML (`.github/workflows/staging-deploy.yml`)
```yaml
name: Deploy to Staging

on:
  push:
    branches:
      - staging

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Setup Node.js (Frontend Build)
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Build Frontend
        working-directory: ./frontend
        run: |
          npm ci
          npm run build

      - name: Deploy Frontend to S3 & Invalidate Cache
        run: |
          aws s3 sync ./frontend/build s3://symplichain-staging-frontend --delete
          aws cloudfront create-invalidation --distribution-id ${{ secrets.STAGING_CLOUDFRONT_ID }} --paths "/*"

      - name: Deploy Backend to EC2
        uses: appleboy/ssh-action@v0.1.6
        with:
          host: ${{ secrets.STAGING_EC2_HOST }}
          username: ubuntu
          key: ${{ secrets.STAGING_EC2_SSH_KEY }}
          script: |
            cd /var/www/symplichain
            git pull origin staging
            source venv/bin/activate
            pip install -r requirements.txt
            python manage.py migrate
            python manage.py collectstatic --noinput
            sudo systemctl restart gunicorn
            sudo systemctl restart celery
```

### Production Deployment YAML (`.github/workflows/production-deploy.yml`)
*(This is identical to the staging YAML, but triggered `on: push: branches: [main]` and targeting Production server secrets/S3 buckets).*

*(See the attached GitHub repository files for the full structures).*

---

## Part 4: Debugging the Monday Outage

**Scenario:** POD photo uploads are failing. Path: Driver app -> Django API (EC2) -> S3 -> Celery -> Bedrock -> RDS.

### Debugging Steps (In Order)

**1. Check the Source Endpoint (Django EC2 Logs)**
* **Why:** I must verify if the request from the mobile app even reached our servers, and if Django successfully saved the file to S3 before handing it off to Celery.
* **Action:** SSH into the EC2 instance.
* **Command:** `tail -n 100 /var/log/nginx/error.log` and `tail -n 100 /var/log/gunicorn/django_error.log`
* **Analysis:** If I see HTTP 500s or S3 "Access Denied" errors, the pipeline stops here. If it returns HTTP 200, I move to Step 2.

**2. Check the Asynchronous Task Queue (Celery)**
* **Why:** If the file reached S3, Django handed the validation job to Celery. I need to know if the workers are alive and processing.
* **Action:** Open the **Celery Flower Dashboard**.
* **Analysis:** Are tasks accumulating in the "Pending" state? (Celery workers crashed or Redis is down). Are tasks in the "Failed" state? I will read the exception traceback. If the traceback says "Timeout from Bedrock", I move to Step 3.

**3. Check External AI Providers (AWS CloudWatch for Bedrock)**
* **Why:** Bedrock AI validation is the heaviest and most rate-limited step.
* **Action:** Open **AWS CloudWatch Logs / Metrics**.
* **Analysis:** I filter logs for Bedrock API calls. Given it's a "Monday Morning Outage" (high load), we likely hit an AWS quota or `ThrottlingException`.

**4. Check Database Write Viability (AWS RDS Console)**
* **Why:** If Bedrock validation succeeds, the worker tries to save to PostgreSQL. 
* **Action:** Open the **RDS Console**.
* **Analysis:** Monitor "Database Connections". An influx of Celery workers on Monday morning might have saturated the maximum connection pool locally, meaning the worker has the validated data but cannot execute the final `INSERT INTO` statement.

---

**Video Screen Recording Link:**  
*(Insert your video link here)*
