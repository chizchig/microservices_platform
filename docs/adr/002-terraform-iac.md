# ADR 002: Terraform for Infrastructure as Code

## Status
Accepted

## Context
We need a tool to manage our cloud infrastructure in a declarative, version-controlled manner. Requirements include:
- Multi-cloud support (AWS primary, potential GCP/Azure future)
- State management and collaboration
- Module reusability
- Plan/apply workflow for safe changes
- Integration with CI/CD pipelines

## Decision
We will use **Terraform** for Infrastructure as Code.

## Consequences

### Positive
- Declarative syntax (HCL) easy to read and maintain
- Excellent AWS provider support
- State management with locking (S3 + DynamoDB)
- Module system for code reuse
- Plan output for review before apply
- Large community and module registry
- Works well with CI/CD pipelines

### Negative
- State file management complexity
- No native rollback capability
- Can be slow for large infrastructures
- Cost estimation requires additional tools

## Alternatives Considered

### AWS CloudFormation
- **Rejected**: AWS-specific, verbose YAML/JSON, slower development cycle

### Pulumi
- **Rejected**: Less mature, smaller community, programming language approach adds complexity

### AWS CDK
- **Rejected**: AWS-specific, requires TypeScript/Python knowledge, abstraction layer adds complexity

## Decision Date
2024-01-15

## Decision Makers
- Principal Architect
- DevOps Lead
- Cloud Engineer
