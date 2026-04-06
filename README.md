# Symplichain Hackathon Submission

This repository contains the CI/CD pipeline configuration and architectural submission for the Symplichain Software Engineering Intern Hackathon.

## Repository Contents

*   `Symplichain_Hackathon_Submission.md`: The complete markdown document answering Parts 1, 2, and 4 (including detailed architectural reasoning and debugging plans). You can export this to a PDF for submission.
*   `.github/workflows/staging-deploy.yml`: The CI/CD pipeline for the staging environment (Part 3).
*   `.github/workflows/production-deploy.yml`: The CI/CD pipeline for the production environment (Part 3).

## Requirements Addressed

1.  **Shared Gateway Problem:** Custom queue structures using Redis and Celery. Token Bucket rate limiting. Fair Round-Robin processing execution.
2.  **Mobile Architecture:** Mobile-optimized interaction leveraging voice input (SymAI) and large gestures to reduce operating friction. Constructed using cross-platform UI tooling (React Native).
3.  **CI/CD Pipeline:** Fully configured push-to-deploy Github Actions mapping code branches to discrete Staging/Production environments using AWS credentials.
4.  **Monday Outage Debugging:** Logical data-path tracing from NGINX error logs -> Celery Flower inspection -> AWS CloudWatch metrics for Bedrock -> Postgres RDS connections.

## Submission Output

Please export the `Symplichain_Hackathon_Submission.md` to a PDF, attach the video recording link inside it, and submit the final file. You can simply push this structure to a public Github Repo to satisfy the repository requirement.
