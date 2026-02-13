# ADR 009: Jaeger for Distributed Tracing

## Status
Accepted

## Context
Our microservices architecture requires:
- Distributed request tracing
- Performance bottleneck identification
- Root cause analysis
- Service dependency visualization
- Latency analysis

## Decision
We will use **Jaeger** for distributed tracing.

## Consequences

### Positive
- Open source (CNCF graduated project)
- Native OpenTelemetry support
- Easy integration with Istio
- Scalable architecture
- Good UI for trace visualization
- Works with multiple storage backends

### Negative
- Additional infrastructure to maintain
- Storage requirements for trace data
- Sampling configuration complexity
- Potential performance impact

## Alternatives Considered

### Zipkin
- **Considered**: Simpler, older project
- **Decision**: Jaeger chosen for better performance and UI

### AWS X-Ray
- **Rejected**: AWS-specific, less flexible

### Tempo
- **Considered**: Grafana project, object storage only
- **Decision**: Jaeger chosen for maturity and features

### Honeycomb
- **Rejected**: SaaS, expensive at scale

## Decision Date
2024-01-28

## Decision Makers
- Principal Architect
- SRE Lead
- Backend Lead
