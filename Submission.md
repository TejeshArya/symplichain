Symplichain Software Engineering Intern Hackathon Submission

Name: Tejesh
GitHub Repository (Contains CI/CD, Docker & Terraform code): https://github.com/TejeshArya/symplichain

==================================================

PART 1: Shared Gateway Problem (40% weightage)

Scenario: Rate limit of exactly <= 3 req/sec to a shared external API across 25 active customers. Need fairness so high-volume customers do not block low-volume customers.

1. Architecture
I propose a Message Queue with a Dispatcher and a Rate-Limited Worker Pool. Given the existing stack (Celery + Redis), we can leverage it without introducing entirely new systems, but we need custom routing for fairness.
- Queues (Redis): Instead of one global celery queue, we create 25 distinct logical queues in Redis, one for each active customer (e.g., Queue_Customer_A, Queue_Customer_B).
- Dispatcher: A lightweight background service that polls these customer queues using a Round-Robin algorithm. It pulls one request from Customer A, one from Customer B, and pushes them into a final Execution Queue.
- Worker (Celery): A Celery worker specifically assigned to consume from the Execution Queue. This worker manages the precise outbound rate limit.

2. Rate Enforcement
To guarantee exactly <= 3 requests per second:
- Token Bucket algorithm via Redis: Before the worker makes an API call, it must acquire a token from Redis. The bucket capacity is 3, and a background task refills it at 3 tokens per second.
- Why not Celery Rate limits?: Celery's built-in rate limits operate per worker process. To ensure a strict global limit across multiple distributed servers, a central distributed lock or Token Bucket in Redis is mandatory.

3. Fairness
- This is achieved via the Round-Robin Queueing managed by the Dispatcher.
- If Customer A floods 100 requests, they all go into Queue_Customer_A. If Customer B sends 1 request, it goes into Queue_Customer_B.
- The Dispatcher takes 1 request from queue A, then 1 from queue B, moving them to the Execution Queue. 
- Thus, B's request will be processed immediately (or at worst, after one of A's requests), preventing starvation and ensuring complete fairness across the customer base.

4. Failure Handling
- 5xx Server Errors (Temporary backend issue): Implement Exponential Backoff with Jitter. First retry after 1s, then 2s, 4s, 8s maxing out at a threshold. The jitter prevents thundering herd problems.
- 429 Too Many Requests: If the external API rejects us, immediately halt queue consumption for ~5 seconds (penalty box) and push the request back to the top of the queue.
- Dead Letter Queue (DLQ): After 5 unsuccessful retries, push the request to a DLQ so we do not indefinitely block the queue, and emit an alert to the engineering team.

==================================================

PART 2: Mobile Architecture (20% weightage)

Scenario: Customer-facing mobile app of SymFlow web platform. Fluid, friction-less.

1. Interaction Model
- Hybrid Gesture and Voice First (Speech-to-Text).
- As a logistics app intended for drivers and warehouse workers, the users are often wearing gloves, driving, or handling packages. The primary entry model should be Voice/Speech-to-Text combined with SymAI validation (e.g., driver speaks: "Package 1234 delivered to the front desk, collected by John").
- The UI must utilize bold, oversized gesture-based actions (e.g., "Swipe right to mark delivered") rather than precision clicks (small buttons), as this minimizes physical friction in the field.

2. Tech Stack
- React Native (with Expo)
- Why? Since the SymFlow web platform is built on React + Tailwind CSS, React Native is the pragmatic and cost-conscious choice. 
- It allows sharing core business logic, utility files, validation schemas, and state management logic with the web frontend.
- It provides a faster time-to-market using a single codebase for both iOS and Android. 

==================================================

PART 3: CI/CD and Deployment Pipeline (20% weightage)

The CI/CD GitHub Actions files, along with Docker and Terraform improvements, have been authored into the GitHub repository.

Files written in the repository to solve this:
1. .github/workflows/deploy-staging.yml - Builds React frontend, syncs to S3, invalidates CloudFront, and updates the Staging EC2 via SSH commands.
2. .github/workflows/deploy-prod.yml - Same process but triggered on the main branch pushing to Production environments.
3. Dockerfile - Containerizes the Django/Gunicorn app for consistent local execution.
4. docker-compose.yml - Enables robust local multi-container development (Django, Celery, Postgres, Redis).
5. terraform/main.tf & variables.tf - Encodes the infrastructure into Infrastructure-as-code (EC2, S3, RDS, ElastiCache, CloudFront) to replace the manual deployments.

==================================================

PART 4: Debugging (20% weightage)

The Monday morning outage: POD photo uploads failing.
Data Path: Driver app -> Django API (EC2) -> S3 -> Celery -> Bedrock -> PostgreSQL (RDS)

Debugging Steps (In chronological order):

Step 1: Verify the Entry Point (Django API on EC2)
- Why: I need to know if the image ever reaches our servers or if the failure happens immediately. Are we returning a 500 error to the mobile app?
- Action: Check Nginx and Django logs on the EC2 instance using the tail and grep commands. 
- If Django is logging AWS permission errors (AccessDenied on S3 upload), the IAM credentials in Secrets Manager might have rotated or expired over the weekend.

Step 2: Check S3 Upload & Celery Task Trigger
- Why: If the API logged a 200 OK, S3 likely succeeded. The next layer is the message broker. Did the Celery task get triggered?
- Action: Open the Celery Flower Dashboard. 
- Look for the POD validation task. Are the tasks queued? Are they actively running? Did they transition to a FAILURE state? If the queue is massively backed up but workers are idle, Redis might be running out of memory. 

Step 3: Analyze Bedrock Integration (CloudWatch)
- Why: If Celery tasks are failing, the SymAI model validation via Bedrock might be the bottleneck. 
- Action: Open the AWS CloudWatch Console, navigate to Bedrock Metrics & Logs.
- Look for the Bedrock Invocation metrics and ThrottlingException. A fine-tuned Sagemaker/Bedrock model might be offline, or we are hitting a hard quota limit due to a sudden Monday traffic surge.

Step 4: Database Verification (RDS Console)
- Why: If Bedrock validation succeeds but results are lost, the database write is failing.
- Action: Open the RDS Console and review RDS CloudWatch metrics.
- Look at DatabaseConnections and CPUUtilization. Did the DB hit its connection limit due to a connection leak in the Celery workers over the weekend? I would connect via psql and run queries to check for frozen, deadlocked, or long-running transactions blocking the writes.
