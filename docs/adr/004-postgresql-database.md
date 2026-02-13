# ADR 004: PostgreSQL as Primary Database

## Status
Accepted

## Context
We need a relational database for our microservices that provides:
- ACID compliance for transactional data
- Strong consistency guarantees
- JSON support for flexible schemas
- Horizontal read scaling
- Managed service availability
- Rich ecosystem and tooling

## Decision
We will use **PostgreSQL** as our primary relational database, deployed via Amazon RDS.

## Consequences

### Positive
- ACID compliance for data integrity
- Excellent JSON/JSONB support for semi-structured data
- Strong consistency model
- Read replicas for horizontal scaling
- Rich ecosystem (extensions, tools)
- AWS RDS managed service reduces operational burden
- Point-in-time recovery
- Multi-AZ deployment for high availability

### Negative
- Vertical scaling limits
- Write scaling challenges
- Connection pool management required
- Managed service costs

## Alternatives Considered

### MySQL
- **Rejected**: Less advanced JSON support, fewer features

### Amazon Aurora
- **Considered**: Better performance, MySQL/PostgreSQL compatible
- **Decision**: Standard PostgreSQL chosen for portability and cost

### CockroachDB
- **Rejected**: Distributed SQL adds complexity, smaller ecosystem

### MongoDB
- **Rejected**: No ACID transactions across documents (in earlier versions), eventual consistency model

## Decision Date
2024-01-22

## Decision Makers
- Principal Architect
- Database Administrator
- Backend Lead
