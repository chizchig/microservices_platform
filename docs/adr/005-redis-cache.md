# ADR 005: Redis for Caching and Session Storage

## Status
Accepted

## Context
Our microservices require:
- Low-latency data access
- Session storage
- Rate limiting counters
- Distributed locking
- Pub/sub messaging
- Cache with TTL support

## Decision
We will use **Redis** (Amazon ElastiCache) for caching, session storage, and real-time data needs.

## Consequences

### Positive
- Sub-millisecond latency
- Rich data structures (strings, hashes, lists, sets, sorted sets)
- Built-in pub/sub
- TTL support for cache expiration
- Cluster mode for horizontal scaling
- AWS ElastiCache managed service
- Persistence options (RDB, AOF)

### Negative
- Memory-only storage (cost considerations)
- Data size limited by available memory
- Single-threaded (CPU-bound for large instances)
- Requires connection pooling

## Alternatives Considered

### Memcached
- **Rejected**: Simpler data model, no persistence, no pub/sub

### Amazon DynamoDB DAX
- **Rejected**: AWS-specific, more expensive, less flexible

### Apache Kafka
- **Rejected**: Different use case (streaming vs. caching)

### Hazelcast
- **Rejected**: More complex deployment, smaller ecosystem

## Decision Date
2024-01-22

## Decision Makers
- Principal Architect
- Backend Lead
- Performance Engineer
