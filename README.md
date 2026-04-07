# Symplichain Software Engineering Intern Hackathon

Welcome to the repository for my Symplichain Software Engineering Intern Hackathon submission. This repository contains solutions for the Hackathon's architecture, design, and DevOps challenges.

## Repository Contents

This repository is structured to seamlessly review the various responses to the Hackathon Challenge:

- **`Submission.md`**: The primary document containing detailed answers to all 4 parts of the challenge:
  - **Part 1:** Shared Gateway Problem (Rate Limiting & Queueing Architecture)
  - **Part 2:** Mobile Architecture (Interaction model and Tech Stack rationale)
  - **Part 3:** CI/CD and Deployment Pipeline explanations.
  - **Part 4:** Debugging (A step-by-step mitigation and methodology).

- **`.github/workflows/`**: Contains the GitHub Actions YAML files for deploying to Staging and Production.
  - `deploy-staging.yml`
  - `deploy-prod.yml`

- **`Dockerfile` & `docker-compose.yml`**: Supplementary containerization for the Django backend to enhance the deployment architecture and standardizing local developer environments.

- **`terraform/`**: Includes `main.tf` and `variables.tf` files with basic Infrastructure as Code (IaC) to migrate away from semi-manual AWS deployments towards a repeatable and robust setup.

## How to Review

1. Read the **`Submission.md`** for the comprehensive written architecture explanations and debugging reasoning.
2. Review the **`.github/workflows`** folder for the CI/CD pipeline implementations.
3. Review the **`Dockerfile`** and **`terraform/`** folder for the bonus Docker and IaC implementations.

## How to use `Submission.md`

For the final submission format required by the challenge prompt ("Submit a single PDF document..."):
- You can compile `Submission.md` into a PDF by using a VSCode Plugin (like `Markdown PDF`), right-clicking the document and selecting 'Export to PDF'. 
- Alternatively, you can open `Submission.md` in your browser (using an online Markdown renderer) or GitHub, and simply use the "Print to PDF" functionality.

Thank you for reviewing my Hackathon Submission!
